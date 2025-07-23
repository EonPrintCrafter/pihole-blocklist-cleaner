#!/bin/bash
set -euo pipefail

workspace="${GITHUB_WORKSPACE:-$(pwd)}"
input_file="$workspace/blocklists.txt"
date_str=$(date -u +'%Y-%m-%d')
output_file="$workspace/blocklist_${date_str}.txt"

temp_domains=$(mktemp)

while IFS= read -r url; do
    [[ -z "$url" || "${url:0:1}" == "#" ]] && continue

    if ! curl --retry 3 --retry-delay 5 -sfL "$url" -o /tmp/list.tmp; then
        echo "Failed to download $url" >&2
        continue
    fi

    grep -E -v '^[[:space:]]*(#|!|@@|$)' /tmp/list.tmp |
    grep -E -v '(\|\||\*|\^|\@|\|)' |
    sed -E 's/^(0\.0\.0\.0|127\.0\.0\.1|::)\s+//; s/^https?:\/\///' |
    sed -E 's/\/.*//; s/[[:space:]]*#.*//; s/[[:space:]]+$//; s/^\.+//' |
    grep -E '\.' |
    grep -Ev '[^A-Za-z0-9\.\-]' |
    tr '[:upper:]' '[:lower:]' >> "$temp_domains"

done < "$input_file"

sort -u "$temp_domains" > "$output_file"
rm "$temp_domains"
