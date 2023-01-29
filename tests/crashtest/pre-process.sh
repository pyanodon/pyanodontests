#!/bin/bash
set -euo pipefail

mkdir ./factorio/mods/testmod
cp ./tests/crashtest/testmod/* ./factorio/mods/testmod
