#!/bin/bash
set -euo pipefail

if [[ -n ${EVENT_REPOSITORY} ]]; then mod_name=$(jq '.[] | if .repository==env.EVENT_REPOSITORY then .name else empty end' mods.json); fi

(echo "matrix="
{ 
    if [ ${mod_name:+1} ]; then
        jq ".include[] | if .mods | any(.==$mod_name) then . else empty end" mod-sets.json | jq -sc '.'
    else
        jq -c '.include' mod-sets.json
    fi

    jq -c '.[]' mods.json |
    while read -r i; do
        repo=$(echo "$i" | jq -cr '.repository')

        if [[ $repo == "${EVENT_REPOSITORY}" ]]; then
            ref=$EVENT_REF
        else
            url=$(echo "$i" | jq -cr '.url')
            branch=$(git remote show "$url" | grep 'HEAD branch' | cut -d' ' -f5)
            ref=$(git ls-remote -h "$url" "$branch" | awk '{print $1}')
        fi
        
        echo "$i" "$(echo "$ref" | jq -R '{ref: .}')" |
        jq -s '{name: .[0].name, repository: .[0].repository, ref:.[1].ref}'
    done |
    jq -s '.' 
} | 
jq -s '.[1] as $modrefs | .[0][].mods |= reduce $modrefs[] as $refs (. ; map_values(if .==$refs.name then $refs.repository + "@" + $refs.ref else . end))' |
jq -c '{include: .[0]}') >> $GITHUB_OUTPUT
