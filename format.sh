#!/bin/sh
# Format the native build integration.
set -eu
cd "$(dirname "$0")"
nix fmt -- flake.nix
nix develop -c black nix
