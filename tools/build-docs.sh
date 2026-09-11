#!/usr/bin/env bash
set -euo pipefail

root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    pwd
)"

cd "$root"

ddox_version="0.16.24"

work_dir="build/ddox"
site_dir="$work_dir/site"
json_file="$work_dir/docs.json"
dummy_file="$work_dir/__dummy.html"

rm -rf "$work_dir"
mkdir -p "$site_dir"

mapfile -t public_sources < <(
    find source/geo \
        -maxdepth 1 \
        -type f \
        -name '*.d' \
        -print |
    sort
)

if ((${#public_sources[@]} == 0)); then
    echo "error: no public geo-d source modules found" >&2
    exit 1
fi

echo "Generating ddox input for ${#public_sources[@]} public modules..."

dmd \
    -o- \
    -w \
    -Xf"$json_file" \
    -Df"$dummy_file" \
    -version=Have_geo_d \
    -Isource \
    -preview=dip1000 \
    -vcolumns \
    "${public_sources[@]}"

rm -f "$dummy_file"

echo "Filtering public documented API..."

dub run "ddox@$ddox_version" -- \
    filter \
    --min-protection=Public \
    --only-documented \
    "$json_file"

echo "Generating HTML documentation..."

dub run "ddox@$ddox_version" -- \
    generate-html \
    --navigation-type=ModuleTree \
    "$json_file" \
    "$site_dir"

echo
echo "Documentation generated:"
echo "  $site_dir/index.html"
