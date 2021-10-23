#!/bin/bash
set -euo pipefail

if [[ -n ${EVENT_REPOSITORY} ]]; then mod_name=$(jq '.[] | if .repository==env.EVENT_REPOSITORY then .name else empty end' mods.json); fi

echo -n "::set-output name=matrix::"
{ 
    if [[ -v mod_name ]]; then
        jq ".include[] | if has($mod_name) then . else empty end " mod-sets.json | jq -sc '.'
    else
        jq -c '.include' mod-sets.json
    fi
    
    jq -c '.[]' mods.json |
    while read i; do
        repo=$(echo $i | jq -cr '.repository')

        if [[ $repo == ${EVENT_REPOSITORY} ]]; then
            ref=$EVENT_REF
        else
            url=$(echo $i | jq -cr '.url')
            branch=$(git remote show $url | grep 'HEAD branch' | cut -d' ' -f5)
            ref=$(git ls-remote -h $url $branch | awk '{print $1}')
        fi
        
        echo $i $(echo $ref | jq -R '{ref: .}') |
        jq -s '{name: .[0].name, ref:.[1].ref}'
    done |
    jq -s '.' 
} | 
jq -s '.[1] as $modrefs | .[0][] | reduce $modrefs[] as $refs (. ; if has($refs.name) then .[$refs.name] |= $refs.ref else . end)' |
jq -sc '{include: [.]}'
