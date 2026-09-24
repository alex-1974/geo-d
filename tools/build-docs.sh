#!/usr/bin/env bash
set -euo pipefail

root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    pwd
)"

cd "$root"

ddox_version="0.16.24"

compiler="dmd"

mapfile -t import_paths < <(
    PYTHONDONTWRITEBYTECODE=1 \
        python3 \
        "$root/tools/dub-import-paths.py" \
        --compiler "$compiler"
)

import_flags=()

for import_path in "${import_paths[@]}"; do
    import_flags+=(
        "-I$import_path"
    )
done

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

echo "Verifying public module metadata..."

required_module_metadata=(
    Authors
    Copyright
    License
    Date
)

for source in "${public_sources[@]}"; do
    module_line="$(
        grep -n -m1 -E             '^[[:space:]]*module[[:space:]]+[A-Za-z0-9_.]+[[:space:]]*;'             "$source" |
        cut -d: -f1 ||
        true
    )"

    if [[ -z "$module_line" ]]; then
        echo "error: missing module declaration: $source" >&2
        false
    fi

    if ((module_line <= 1)); then
        echo "error: missing module documentation before declaration: $source" >&2
        false
    fi

    for field in "${required_module_metadata[@]}"; do
        if ! head -n "$((module_line - 1))" "$source" |
            grep -Eq                 "^[[:space:]]*\\*[[:space:]]+$field:[[:space:]]*$"
        then
            echo "error: missing module Ddoc metadata '$field:' in $source" >&2
            false
        fi
    done
done

echo "PASS: public module metadata (${#public_sources[@]} modules)"
echo

echo "Generating ddox input for ${#public_sources[@]} public modules..."

"$compiler" \
    -o- \
    -w \
    -Xf"$json_file" \
    -Df"$dummy_file" \
    -version=Have_geo_d \
    "${import_flags[@]}" \
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

ddox_dir="$(
    dub list "ddox@$ddox_version" |
    sed -nE \
        "s|^[[:space:]]*ddox[[:space:]]+$ddox_version:[[:space:]]+(.*)$|\\1|p" |
    head -n 1
)"

if [[ -z "$ddox_dir" || ! -d "$ddox_dir/public" ]]; then
    echo "error: cannot locate ddox public assets" >&2
    false
fi

echo "Copying ddox static assets..."

cp -au \
    "$ddox_dir/public/." \
    "$site_dir/"

echo "Verifying generated public API documentation..."

for source in "${public_sources[@]}"; do
    filename="${source##*/}"

    if [[ "$filename" == "package.d" ]]; then
        module_page="$site_dir/geo.html"
    else
        module="${filename%.d}"
        module_page="$site_dir/geo/$module.html"
    fi

    if [[ ! -f "$module_page" ]]; then
        echo "error: missing public module page: $module_page" >&2
        false
    fi
done

if grep -Rqi \
    'geo\.internal' \
    "$site_dir" \
    --include='*.html'
then
    echo "error: internal geo modules leaked into public documentation" >&2
    false
fi

private_page="$(
    find "$site_dir/geo" \
        -type f \
        -name '*._*.html' \
        -print \
        -quit
)"

if [[ -n "$private_page" ]]; then
    echo "error: private implementation symbol leaked into documentation:" >&2
    echo "  $private_page" >&2
    false
fi

echo "PASS: public-only ddox documentation"

echo
echo "Verifying public API example audit..."

python3 \
    "$root/tools/verify-public-api-examples.py" \
    "$root/docs/public-api-example-audit.md" \
    "$site_dir"

echo
echo "Documentation generated:"
echo "  $site_dir/index.html"
