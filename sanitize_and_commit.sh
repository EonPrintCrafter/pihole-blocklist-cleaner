#!/bin/bash
set -x  # Print every command (debug mode)

workspace="${GITHUB_WORKSPACE:-$(pwd)}"
input_file="$workspace/blocklists.txt"
date_str=$(date -u +'%Y-%m-%d')
output_file="$workspace/blocklist_${date_str}.txt"

echo "Starting blocklist update at $(date -u)"
echo "Reading lists from $input_file"
echo "Output file: $output_file"

if [[ ! -f "$input_file" ]]; then
  echo "ERROR: blocklists.txt not found at $input_file"
  exit 2
fi

temp_domains=$(mktemp)
echo "Temporary domains file: $temp_domains"

while IFS= read -r url; do
    [[ -z "$url" || "${url:0:1}" == "#" ]] && continue

    echo "Downloading $url ..."
    if ! curl --retry 3 --retry-delay 5 -sfL "$url" -o /tmp/list.tmp; then
        echo "ERROR: Failed to download $url" >&2
        continue
    fi

    echo "Filtering domains from $url ..."
    grep -E -v '^[[:space:]]*(#|!|@@|$)' /tmp/list.tmp | \
    sed -E 's/^(0\.0\.0\.0|127\.0\.0\.1|::)\s+//' | \
    sed -E 's/^https?:\/\///' | \
    sed -E 's/\/.*//' | \
    sed -E 's/[[:space:]]*#.*//' | \
    sed -E 's/[[:space:]]+$//' | \
    sed -E 's/^\.+//' | \
    tr '[:upper:]' '[:lower:]' | \
    grep -E '^[a-z0-9.-]+$' | \                      # Only a-z,0-9, dot, dash allowed
    grep -E -v '(^-|-$|--|\.\.|^-|\.$)' | \          # No leading/trailing hyphen or dot, no double dash/dot
    grep -E -v '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | \   # Exclude pure IP addresses
    awk 'length($0) >= 3 && length($0) <= 253' >> "$temp_domains"   # Domain length limits
done < "$input_file"

echo "Sorting and deduplicating domains..."
sort -u "$temp_domains" > "$output_file"
rm "$temp_domains"
echo "Blocklist update complete: $(wc -l < "$output_file") domains written to $output_file"
