#!/bin/sh
# Build and validate the firmware without accessing a device.
set -eu
cd "$(dirname "$0")"
nix flake check -L
nix build -L
