#!/bin/bash

set -e

repo=$1
version=${2:-latest}

jq_match=$(cat)

if [[ $version != latest ]]; then version="tags/$version"; fi

deb_arch=$(dpkg --print-architecture)
uname_m=$(uname -m)

curl -sL "https://api.github.com/repos/$repo/releases/$version" |
  jq -r \
    --arg deb_arch "$deb_arch" \
    --arg uname_m "$uname_m" \
    '.assets[] | first(select(.name | '"$jq_match"')).browser_download_url' |
  while read -r line; do
    cd "$(mktemp -d)"
    curl -sLO "$line"
    printf "$PWD/${line##*/}"
  done
