"""Cirrus CI configuration for Termisu."""

load("github.com/cirrus-modules/helpers", "task", "container", "macos_instance", "freebsd_instance", "cache", "script")

# =============================================================================
# Configuration
# =============================================================================

CRYSTAL_IMAGE = "crystallang/crystal:latest"
MACOS_IMAGE = "ghcr.io/cirruslabs/macos-runner:sonoma"
FREEBSD_IMAGE = "freebsd-15-0-amd64-ufs"

ENV = {"TERM": "xterm-256color"}
ENV_FREEBSD = {"TERM": "xterm"}  # FreeBSD base doesn't include xterm-256color terminfo

# Platform definitions: (name, instance, env, crystal_install, expect_install, spec_cmd)
PLATFORMS = [
    ("linux", container(CRYSTAL_IMAGE), ENV, None, "apt-get update && apt-get install -y expect", "unbuffer crystal spec -v"),
    ("macos", macos_instance(MACOS_IMAGE), ENV, "brew install crystal", "brew install expect", "unbuffer crystal spec -v"),
    ("freebsd", freebsd_instance(image_family=FREEBSD_IMAGE), ENV_FREEBSD, "pkg install -y crystal shards", "pkg install -y expect", "expect_unbuffer crystal spec -v"),
    # ("windows", windows_container(), ENV, "choco install crystal -y", None, "crystal spec -v"),
]

# =============================================================================
# Caches
# =============================================================================

def shards_cache():
    return cache(name="shards", folder="lib", fingerprint_script="cat shard.yml", populate_script="shards install")

def bin_cache():
    return cache(name="bin", folder="bin", fingerprint_script="cat shard.yml", populate_script="shards build ameba")

# =============================================================================
# Task Builders
# =============================================================================

def make_task(name, instance, instructions, env=ENV):
    """Build a task with common settings."""
    return task(name=name, instance=instance, env=env, instructions=instructions)

def spec_task(platform, instance, env, crystal_install=None, expect_install=None, spec_cmd="crystal spec -v"):
    """Build a spec task for a given platform."""
    instructions = []
    if crystal_install:
        instructions.append(script("install_crystal", crystal_install))
    instructions.append(shards_cache())
    if expect_install:
        instructions.append(script("install_expect", expect_install))
    instructions.append(script("spec", spec_cmd))
    return make_task("spec_" + platform, instance, instructions, env)

# =============================================================================
# Main
# =============================================================================

def main(ctx):
    linux = container(CRYSTAL_IMAGE)

    return [
        # Lint & format (Linux only)
        make_task("format", linux, [shards_cache(), script("format", "crystal tool format --check")]),
        make_task("lint", linux, [shards_cache(), bin_cache(), script("lint", "bin/ameba")]),
        # Specs (multi-platform)
    ] + [spec_task(name, inst, env, crystal, expect, cmd) for name, inst, env, crystal, expect, cmd in PLATFORMS]
