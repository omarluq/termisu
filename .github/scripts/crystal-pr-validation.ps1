param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('sdk121', 'sdk122', 'pr-base', 'pr-head')]
    [string]$Configuration,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location $repo
New-Item -ItemType Directory -Force -Path $OutputDirectory, bin | Out-Null
$env:NO_COLOR = '1'
$head = '7c0e4bc7b3c545ba52f62ce110886bedf4ea4c74'
$base = '3e2cd3824953481ce8d89eea78050f525a9f89ee'
$version = if ($Configuration -eq 'sdk121') { '1.21.0' } else { '1.22.2' }
$expectedRetained = if ($Configuration -in 'sdk122', 'pr-base') { 32 } else { 0 }
$source = 'installed SDK'
$env:CRYSTAL_PATH = $null
$installedCrystalPath = (& crystal env CRYSTAL_PATH) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve installed standard library' }
$installedSources = @($installedCrystalPath.Split([IO.Path]::PathSeparator) | Where-Object {
    $_ -and (Test-Path (Join-Path $_ 'crystal/system/thread.cr'))
} | ForEach-Object { (Resolve-Path $_).Path })
if ($installedSources.Count -ne 1) { throw 'Ambiguous installed standard library source' }
if ($Configuration -ne 'sdk121') {
    $actual = (& git -C crystal-pr rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $head) { throw 'Unexpected upstream PR head' }
}
if ($Configuration -in 'pr-base', 'pr-head') {
    $directory = if ($Configuration -eq 'pr-base') { 'crystal-base' } else { 'crystal-pr' }
    $source = if ($Configuration -eq 'pr-base') { $base } else { $head }
    $actual = (& git -C $directory rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $source) { throw 'Unexpected standard library source' }
    $env:CRYSTAL_PATH = (Resolve-Path "$directory/src").Path
}
$compiler = (& crystal --version) -join "`n"
if ($LASTEXITCODE -ne 0 -or $compiler -notmatch "Crystal $([regex]::Escape($version)) ") {
    throw 'Unexpected compiler version'
}
$manifest = [ordered]@{
    configuration = $Configuration
    termisuHead = $env:GITHUB_SHA
    upstreamHead = $head
    upstreamBase = $base
    standardLibrary = $source
    crystal = $version
    compiler = $compiler
    crystalPath = (& crystal env CRYSTAL_PATH) -join "`n"
    installedCrystalPath = $installedCrystalPath
    installedStandardLibrary = $installedSources[0]
    expectedRetainedSemaphores = $expectedRetained
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputDirectory 'manifest.json')

function Assert-State([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Build-Probe([string]$Source, [string]$Name) {
    & crystal build $Source -o "bin/$Name.exe" --error-on-warnings
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $Name" }
}

function Invoke-Probe([string]$Name, [bool]$ExpectedFailure = $false) {
    $directory = Join-Path $OutputDirectory $Name
    $arguments = @('-NoProfile', '-File', "$PSScriptRoot/windows-console-probe.ps1",
        '-ProbePath', "bin/$Name.exe", '-OutputDirectory', $directory)
    if ($ExpectedFailure) { $arguments += '-AllowFailure' }
    & pwsh @arguments | Out-Host
    $status = $LASTEXITCODE
    Assert-State ($status -eq 0) "$Name supervision failed"
    $native = Get-Content -Raw (Join-Path $directory 'process-result.json') | ConvertFrom-Json
    Assert-State ($native.supervisionCompleted -eq $true -and $native.timedOut -eq $false) "$Name supervision incomplete"
    $expectedExit = if ($ExpectedFailure) { 1 } else { 0 }
    Assert-State ($native.exitCode -eq $expectedExit) "$Name returned an unexpected native exit code"
    $stdout = Get-Content -Raw (Join-Path $directory 'stdout.log')
    $stderr = Get-Content -Raw (Join-Path $directory 'stderr.log')
    Assert-State ([string]::IsNullOrWhiteSpace($stderr)) "$Name wrote to stderr"
    return $stdout
}

Build-Probe '.github/scripts/sdk-thread-cleanup.cr' 'sdk-thread-cleanup'
$sdk = (Invoke-Probe 'sdk-thread-cleanup') | ConvertFrom-Json
Assert-State ($sdk.probe -eq 'sdk-thread-cleanup' -and $sdk.crystal -eq $version) 'Wrong SDK proof identity'
Assert-State ($sdk.platform -eq 'windows' -and $sdk.pointer_bytes -eq 8) 'Wrong native SDK host'
Assert-State ($sdk.phases.Count -eq 2) 'Missing SDK ordering controls'
foreach ($phase in $sdk.phases) {
    $expected = if ($phase.mode -eq 'join-first') { $expectedRetained } else { 0 }
    Assert-State ($phase.mode -in 'join-first', 'exit-first') 'Unknown SDK phase'
    Assert-State ($phase.samples -eq 32 -and $phase.forced_order_samples -eq 32) 'SDK order not forced'
    Assert-State ($phase.terminated_threads -eq 32 -and $phase.closed_thread_handles -eq 32) 'SDK workers not confirmed closed'
    $inspected = if ($Configuration -eq 'sdk121') { 0 } else { 32 }
    Assert-State ($phase.inspected_semaphores -eq $inspected) 'SDK semaphore preconditions missing'
    Assert-State ($phase.open_semaphores_after_join -eq $expected -and $phase.open_semaphores_after_gc -eq $expected) 'Unexpected SDK semaphore retention'
    Assert-State (([long]$phase.process_handles_after_join - [long]$phase.process_handles_before) -eq $expected) 'Unexpected SDK handle growth after join'
    Assert-State (([long]$phase.process_handles_after_gc - [long]$phase.process_handles_before) -eq $expected) 'Unexpected SDK handle growth after GC'
}
Assert-State ($sdk.phases[0].mode -eq 'exit-first' -and $sdk.phases[1].mode -eq 'join-first') 'SDK phase controls changed'

$regression = 'not applicable: SDK1.21 has no thread semaphore'
if ($Configuration -ne 'sdk121') {
    Build-Probe 'crystal-pr/spec/std/thread_spec.cr' 'upstream-thread-spec'
    $expectedFailure = $expectedRetained -eq 32
    $output = Invoke-Probe 'upstream-thread-spec' $expectedFailure
    if ($expectedFailure) {
        Assert-State ($output.Contains('6 examples, 1 failures, 0 errors, 0 pending')) 'Expected exactly one executed regression failure'
        Assert-State ($output.Contains('after_join.should eq(0)')) 'Wrong upstream regression failed'
        $regression = 'expected native semaphore assertion failure'
    } else {
        Assert-State ($output.Contains('6 examples, 0 failures, 0 errors, 0 pending')) 'Upstream thread specs did not pass'
        $regression = '6/0/0/0'
    }
}

Build-Probe 'spec/termisu/system/console_spec.cr' 'windows-console-probe'
$contracts = Invoke-Probe 'windows-console-probe'
Assert-State ($contracts.Contains('44 examples, 0 failures, 0 errors, 0 pending')) 'Termisu native console contracts did not pass'

Build-Probe '.github/scripts/termisu-thread-cleanup.cr' 'termisu-thread-cleanup'
$termisu = (Invoke-Probe 'termisu-thread-cleanup') | ConvertFrom-Json
Assert-State ($termisu.probe -eq 'termisu-readiness-cleanup' -and $termisu.crystal -eq $version) 'Wrong Termisu lifecycle identity'
Assert-State ($termisu.platform -eq 'windows' -and $termisu.pointer_bytes -eq 8) 'Wrong native Termisu host'
Assert-State ($termisu.samples -eq 32 -and $termisu.terminated_threads -eq 32) 'Missing Termisu worker termination'
Assert-State ($termisu.closed_thread_handles -eq 32 -and $termisu.closed_owned_handles -eq 160) 'Termisu-owned handles remain open'
$inspected = if ($Configuration -eq 'sdk121') { 0 } else { 32 }
Assert-State ($termisu.inspected_semaphores -eq $inspected) 'Missing Termisu SDK semaphore inspection'
if ($Configuration -in 'sdk121', 'pr-head') {
    Assert-State ($termisu.open_semaphores_after_close -eq 0 -and $termisu.open_semaphores_after_gc -eq 0) 'Fixed Termisu lifecycle retained SDK semaphores'
    Assert-State (([long]$termisu.process_handles_after_close - [long]$termisu.process_handles_before) -eq 0) 'Fixed Termisu lifecycle retained handles after close'
    Assert-State (([long]$termisu.process_handles_after_gc - [long]$termisu.process_handles_before) -eq 0) 'Fixed Termisu lifecycle retained process handles'
}
$result = [ordered]@{
    manifest = $manifest
    sdkProof = $sdk
    upstreamRegression = $regression
    termisuNativeContracts = '44/0/0/0'
    termisuLifecycle = $termisu
    limits = 'Windows x64; real production readiness lease with idle event input plus console contracts; no ConPTY or full-application claim'
}
$result | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutputDirectory 'result.json')
Write-Host "Validated $Configuration against pinned Crystal PR17884"
