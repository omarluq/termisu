# Entry point for code coverage analysis.
#
# This file requires all specs to build a single binary for kcov.
# Usage: crystal build run_specs.cr -o bin/run_specs
#
# See: .github/workflows/coverage.yml
require "./spec/**"
