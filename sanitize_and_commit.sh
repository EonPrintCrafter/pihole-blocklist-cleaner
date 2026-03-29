# Updated sed command
sed 's/\./\\./g' "$output_static" | sed 's#^#(^|\\.)#' | sed 's#$#($|\\/)#' > "$output_pihole_regex"