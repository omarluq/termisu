"""Cirrus CI configuration for Termisu."""

load("github.com/cirrus-modules/helpers", "task", "container", "macos_instance", "freebsd_instance", "cache", "script")

# Crystal configuration
CRYSTAL_IMAGE = "crystallang/crystal:latest"
MACOS_IMAGE = "ghcr.io/cirruslabs/macos-runner:sonoma"
FREEBSD_IMAGE = "freebsd-15-0-amd64-ufs"

def crystal_env():
    return {"TERM": "xterm-256color"}

def shards_cache():
    return cache(
        name="shards",
        folder="lib",
        fingerprint_script="cat shard.yml",
        populate_script="shards install",
    )

def bin_cache():
    return cache(
        name="bin",
        folder="bin",
        fingerprint_script="cat shard.yml",
        populate_script="shards build ameba",
    )

# =============================================================================
# Lint & Format Tasks (Linux only)
# =============================================================================

def format_task():
    return task(
        name="format",
        instance=container(CRYSTAL_IMAGE),
        env=crystal_env(),
        instructions=[
            shards_cache(),
            script("format", "crystal tool format --check"),
        ],
    )

def lint_task():
    return task(
        name="lint",
        instance=container(CRYSTAL_IMAGE),
        env=crystal_env(),
        instructions=[
            shards_cache(),
            bin_cache(),
            script("lint", "bin/ameba"),
        ],
    )

# =============================================================================
# Spec Tasks (Multi-platform)
# =============================================================================

def spec_linux_task():
    """Run specs on Linux (epoll backend)."""
    return task(
        name="spec_linux",
        instance=container(CRYSTAL_IMAGE),
        env=crystal_env(),
        instructions=[
            shards_cache(),
            script("install_expect", "apt-get update && apt-get install -y expect"),
            script("spec", "unbuffer crystal spec -v"),
        ],
    )

def spec_macos_task():
    """Run specs on macOS (kqueue backend)."""
    return task(
        name="spec_macos",
        instance=macos_instance(MACOS_IMAGE),
        env=crystal_env(),
        instructions=[
            script("install_crystal", "brew install crystal"),
            shards_cache(),
            script("install_expect", "brew install expect"),
            script("spec", "unbuffer crystal spec -v"),
        ],
    )

def spec_freebsd_task():
    """Run specs on FreeBSD (kqueue backend)."""
    return task(
        name="spec_freebsd",
        instance=freebsd_instance(image_family=FREEBSD_IMAGE),
        env=crystal_env(),
        instructions=[
            script("install_crystal", "pkg install -y crystal shards"),
            shards_cache(),
            script("install_expect", "pkg install -y expect"),
            script("spec", "unbuffer crystal spec -v"),
        ],
    )

# def spec_windows_task():
#     """Run specs on Windows (poll backend)."""
#     return task(
#         name="spec_windows",
#         instance=windows_container(),
#         env=crystal_env(),
#         instructions=[
#             script("install_crystal", "choco install crystal -y"),
#             shards_cache(),
#             script("spec", "crystal spec -v"),
#         ],
#     )

# =============================================================================
# Main
# =============================================================================

def main(ctx):
    return [
        # Lint & format (Linux only)
        format_task(),
        lint_task(),
        # Specs (multi-platform)
        spec_linux_task(),
        spec_macos_task(),
        spec_freebsd_task(),
        # spec_windows_task(),  # TODO: Enable when Crystal Windows support matures
    ]
