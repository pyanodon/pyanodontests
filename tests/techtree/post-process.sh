#!/bin/bash
set -euo pipefail

< ./factorio/script-output/tech_tree_log.txt sed $'s,^ERROR:\s.*,\e[31m&\e[m,'

! grep -q 'ERROR:' ./factorio/script-output/tech_tree_log.txt
