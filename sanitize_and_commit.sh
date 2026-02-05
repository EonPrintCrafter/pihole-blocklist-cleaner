#!/bin/bash

set -euo pipefail

# ────────────────────────────────────────────────────────────────
# 🎨 Terminal Colors
# ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ────────────────────────────────────────────────────────────────
# 📁 Paths and Filenames
# ────────────────────────────────────────────────────────────────
workspace="${GITHUB_WORKSPACE:-$(pwd)}"
input_file="$workspace/blocklists.txt"
date_str=$(date -u +'%Y-%m-%d')
output_versioned="$workspace/blocklist_${date_str}.txt"
output_static="$workspace/blocklist.txt"

echo -e "${BLUE}Starting Pi-hole blocklist update at $(date -u)${NC}"
echo -e "${BLUE}Reading blocklist URLs from: $input_file${NC}"
echo -e "${BLUE}Output will be saved to:${NC}"
echo -e "${BLUE} - $output_versioned${NC}"
echo -e "${BLUE} - $output_static${NC}"

[[ -f "$input_file" ]] || { echo -e "${RED}ERROR: blocklists.txt not found at $input_file${NC}"; exit 2; }

# ────────────────────────────────────────────────────────────────
# 🧪 Temporary Workspace
# ────────────────────────────────────────────────────────────────
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
temp_domains="$tmpdir/domains.tmp"

echo -e "${BLUE}Temporary working directory: $tmpdir${NC}"

# ────────────────────────────────────────────────────────────────
# 📥 Download & Parse (Enhanced for Pi-hole)
# ────────────────────────────────────────────────────────────────
while IFS= read -r url; do
    [[ -z "$url" || "${url:0:1}" == "#" ]] && continue

    echo -e "${YELLOW}Downloading: $url ...${NC}"
    if ! curl --retry 3 --retry-delay 5 -sfL "$url" -o "$tmpdir/list.tmp"; then
        echo -e "${RED}ERROR: Failed to download $url - skipping${NC}" >&2
        continue
    fi

    [[ -s "$tmpdir/list.tmp" ]] || { 
        echo -e "${YELLOW}WARNING: Downloaded list is empty for $url - skipping${NC}"; 
        continue 
    }

    echo -e "${YELLOW}Filtering valid domains from $url ...${NC}"

    # Enhanced parsing for various list formats
    grep -Ev '^\s*(#|!|@@|\$)' "$tmpdir/list.tmp" | \
    sed -E 's/^(0\.0\.0\.0|127\.0\.0\.1|::)\s+//' | \
    sed -E 's#^\|\|([^/^]+)\^.*#\1#' | \
    sed -E 's#^https?://([^/]+).*#\1#' | \
    sed -E 's/^\*\.//' | \
    sed -E 's/[[:space:]]+#.*//' | \
    tr '[:upper:]' '[:lower:]' | \
    grep -E '^[a-z0-9.-]+$' | \
    grep -Ev '(^-|-$|\.\.|--)' | \
    awk 'length($0) >= 3 && length($0) <= 253' | \
    grep -Ev '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >> "$temp_domains" || \
    echo -e "${RED}WARNING: Some domains from $url could not be filtered${NC}"

done < "$input_file"

# ────────────────────────────────────────────────────────────────
# 🧹 Sort & Save
# ────────────────────────────────────────────────────────────────
echo -e "${BLUE}Sorting and deduplicating domains...${NC}"
sort -u "$temp_domains" > "$output_versioned"
cp "$output_versioned" "$output_static"

count=$(wc -l < "$output_static")
echo -e "${GREEN}Blocklist update complete: $count domains written.${NC}"
echo -e "${GREEN}Static Pi-hole URL output available at: $output_static${NC}"

# ────────────────────────────────────────────────────────────────
# 📋 Generate Pi-hole compatible formats (ADDED SECTION)
# ────────────────────────────────────────────────────────────────
echo -e "${BLUE}Generating Pi-hole compatible formats...${NC}"

# 1. Pi-hole local.list format (0.0.0.0 format)
output_pihole_local="$workspace/pi-hole-local.list"
sed 's/^/0.0.0.0 /' "$output_static" > "$output_pihole_local"
echo -e "${GREEN}Pi-hole local.list format: $output_pihole_local${NC}"

# 2. Pi-hole regex list format (for regex blacklist)
output_pihole_regex="$workspace/pi-hole-regex.list"
sed 's/\./\\./g' "$output_static" | sed 's/^/(^|\\.)/' | sed 's/$/($|\\/)/' > "$output_pihole_regex"
echo -e "${GREEN}Pi-hole regex format: $output_pihole_regex${NC}"

# 3. Pi-hole wildcard blocklist (for DNS blocking)
output_pihole_wildcard="$workspace/pi-hole-wildcard.list"
awk '{print "||" $0 "^"}' "$output_static" > "$output_pihole_wildcard"
echo -e "${GREEN}Adblock/wildcard format: $output_pihole_wildcard${NC}"

# ────────────────────────────────────────────────────────────────
# 🚀 Optional GitHub Commit
# ────────────────────────────────────────────────────────────────
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo -e "${BLUE}Committing new blocklists to GitHub...${NC}"
    git config --global user.email "bot@example.com"
    git config --global user.name "Blocklist Bot"

    git add "$output_static" "$output_versioned" "$output_pihole_local" "$output_pihole_regex" "$output_pihole_wildcard"

    if git diff --cached --quiet; then
        echo -e "${YELLOW}No changes to commit.${NC}"
    else
        git commit -m "Update blocklist on $date_str"
        git push
        echo -e "${GREEN}Blocklists committed and pushed.${NC}"
    fi
fi
