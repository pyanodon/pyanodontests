#!/bin/bash
set -euo pipefail

mkdir -p ./factorio/mods
cp './mod-list.json' ./factorio/mods/
jq -c '.[]' mods.json |
while read -r i; do
    mod_repo=$(echo "$i" | jq -cr '.repository')
    mod_name=$(echo "$i" | jq -cr '.name')

    if [[ -d ./"$mod_repo" ]]; then
        mkdir ./factorio/mods/"$mod_name"
        mv ./"$mod_repo"/* ./factorio/mods/"$mod_name"
        rm -r ./"$mod_repo"
    fi
done

