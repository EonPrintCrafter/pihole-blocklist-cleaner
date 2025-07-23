#!/bin/bash

set -eo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

workspace="${GITHUB_WORKSPACE:-$(pwd)}"
input_file="$workspace/blocklists.txt"
date_str=$(date -u +'%Y-%m-%d')
output_file="$workspace/blocklist_${date_str}.txt"

echo -e "${BLUE}Starting Pi-hole blocklist update at $(date -u)${NC}"
echo -e "${BLUE}Reading blocklist URLs from ${input_file}${NC}"
echo -e "${BLUE}Output will be saved to ${output_file}${NC}"

if [[ ! -f "$input_file" ]]; then
  echo -e "${RED}ERROR: blocklists.txt not found at $input_file${NC}"
  exit 2
fi

temp_domains=$(mktemp)
trap 'rm -f "$temp_domains" /tmp/list.tmp' EXIT

echo -e "${BLUE}Temporary domains file: $temp_domains${NC}"

while IFS= read -r url; do
    # Skip empty lines and comments
    [[ -z "$url" || "${url:0:1}" == "#" ]] && continue

    echo -e "${YELLOW}Downloading $url ...${NC}"
    if ! curl --retry 3 --retry-delay 5 -sfL "$url" -o /tmp/list.tmp; then
        echo -e "${RED}ERROR: Failed to download $url - skipping${NC}" >&2
        continue
    fi

    if [[ ! -s /tmp/list.tmp ]]; then
        echo -e "${YELLOW}WARNING: Downloaded list is empty for $url - skipping${NC}"
        continue
    fi

    echo -e "${YELLOW}Filtering valid Pi-hole domains from $url ...${NC}"

    if ! grep -Ev '^\s*(#|!|@@|$)' /tmp/list.tmp | \
        sed -E 's/^(0\.0\.0\.0|127\.0\.0\.1|::)\s+//' | \
        sed -E 's/^https?:\/\/([^\/]+).*/\1/' | \
        sed -E 's/[[:space:]]+#.*//' | \
        tr '[:upper:]' '[:lower:]' | \
        grep -E '^[a-z0-9.-]+$' | \
        grep -Ev '(^-|-$|\.\.|--)' | \
        awk 'length($0) >= 3 && length($0) <= 253' | \
        grep -Ev '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >> "$temp_domains"; then
        echo -e "${RED}ERROR: Filtering pipeline failed for $url - skipping${NC}"
        continue
    fi

done < "$input_file"

echo -e "${BLUE}Sorting and deduplicating domains...${NC}"
sort -u "$temp_domains" > "$output_file"

count=$(wc -l < "$output_file")
echo -e "${GREEN}Blocklist update complete: $count domains written to $output_file${NC}"
