"""Cirrus CI - FreeBSD specs (GitHub Actions handles Linux/macOS)."""

load("github.com/cirrus-modules/helpers", "task", "freebsd_instance", "cache", "script")

FREEBSD_VERSION = "15.0"
FREEBSD_IMAGE = "freebsd-15-0-amd64-ufs"

CRYSTAL_VERSION = "1.19.1"

def main(ctx):
    return [
        task(
            name="Tests / Run Tests (freebsd-%s)" % FREEBSD_VERSION,
            instance=freebsd_instance(image_family=FREEBSD_IMAGE),
            env={"TERM": "xterm-256color"},
            instructions=[
                script("install", """
                    pkg install -y shards terminfo-db expect wget llvm20
                    wget -O /tmp/crystal.tar.gz https://github.com/crystal-lang/crystal/releases/download/%s/crystal-%s-1-freebsd-amd64.tar.gz
                    tar xzf /tmp/crystal.tar.gz -C /usr/local
                    rm /tmp/crystal.tar.gz
                """ % (CRYSTAL_VERSION, CRYSTAL_VERSION)),
                cache(name="shards", folder="lib", fingerprint_script="cat shard.yml", populate_script="shards install"),
                script("spec", "expect_unbuffer crystal spec -v"),
            ],
        ),
    ]
