"""Cirrus CI configuration for Termisu."""

load("github.com/cirrus-modules/helpers", "task", "container", "cache", "script")

# Crystal configuration
IMAGE = "crystallang/crystal:latest"

def crystal_container():
    return container(IMAGE)

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

# Tasks
def format_task():
    return task(
        name="format",
        instance=crystal_container(),
        env=crystal_env(),
        instructions=[
            shards_cache(),
            script("format", "crystal tool format --check"),
        ],
    )

def lint_task():
    return task(
        name="lint",
        instance=crystal_container(),
        env=crystal_env(),
        instructions=[
            shards_cache(),
            bin_cache(),
            script("lint", "bin/ameba"),
        ],
    )

def spec_task():
    return task(
        name="spec",
        instance=crystal_container(),
        env=crystal_env(),
        instructions=[
            shards_cache(),
            script("install_expect", "apt-get update && apt-get install -y expect"),
            script("spec", "unbuffer crystal spec -v"),
        ],
    )

def main(ctx):
    return [
        format_task(),
        lint_task(),
        spec_task(),
    ]
