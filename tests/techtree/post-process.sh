#!/bin/bash
set -euo pipefail

cat ./factorio/script-output/tech_tree_log.txt | sed $'s,^ERROR:\s.*,\e[31m&\e[m,'
