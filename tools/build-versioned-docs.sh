#!/usr/bin/env bash
set -euo pipefail

root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    pwd
)"

cd "$root"

latest_version='v2.0.0'

versions=(
    'v1.0.0'
    'v2.0.0'
)

work_dir="$root/build/versioned-docs"
sources_dir="$work_dir/sources"
site_dir="$work_dir/site"

rm -rf "$work_dir"

mkdir -p \
    "$sources_dir" \
    "$site_dir"

echo 'Building versioned API documentation...'
echo

for version in "${versions[@]}"; do
    source_dir="$sources_dir/$version"
    version_site="$site_dir/$version"

    echo "=== $version ==="

    if ! git rev-parse --verify --quiet "$version^{commit}" >/dev/null; then
        echo "error: missing release tag: $version" >&2
        exit 1
    fi

    mkdir -p "$source_dir"

    git archive "$version" |
        tar -x -C "$source_dir"

    (
        cd "$source_dir"
        bash tools/build-docs.sh
    )

    mkdir -p "$version_site"

    cp -a \
        "$source_dir/build/ddox/site/." \
        "$version_site/"

    if [[ ! -f "$version_site/geo.html" ]]; then
        echo "error: missing generated package page for $version" >&2
        exit 1
    fi

    echo "PASS: $version"
    echo
done

echo '=== Assemble latest stable documentation ==='

latest_site="$site_dir/$latest_version"

if [[ ! -d "$latest_site" ]]; then
    echo "error: latest stable documentation not built: $latest_version" >&2
    exit 1
fi

cp -a \
    "$latest_site/." \
    "$site_dir/"

cat > "$site_dir/versions.html" <<EOF2
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>geo-d API documentation versions</title>
</head>
<body>
  <h1>geo-d API documentation</h1>

  <p>
    The root documentation follows the current stable release:
    <strong>${latest_version}</strong>.
  </p>

  <ul>
    <li>
      <a href="./geo.html">${latest_version} — latest stable</a>
    </li>
    <li>
      <a href="./v2.0.0/geo.html">v2.0.0</a>
    </li>
    <li>
      <a href="./v1.0.0/geo.html">v1.0.0</a>
    </li>
  </ul>
</body>
</html>
EOF2

echo
echo '=== Verify version separation ==='

test -f "$site_dir/geo.html"
test -f "$site_dir/v2.0.0/geo.html"
test -f "$site_dir/v1.0.0/geo.html"
test -f "$site_dir/versions.html"

cmp \
    "$site_dir/geo.html" \
    "$site_dir/v2.0.0/geo.html"

grep -Rq \
    'Polyline2View' \
    "$site_dir/v2.0.0" \
    --include='*.html'

grep -Rq \
    'Orientation2' \
    "$site_dir/v2.0.0" \
    --include='*.html'

if grep -Rq \
    'Polyline2View' \
    "$site_dir/v1.0.0" \
    --include='*.html'
then
    echo 'error: v2 Polyline2View leaked into v1.0.0 documentation' >&2
    exit 1
fi

echo 'PASS: root documentation matches v2.0.0'
echo 'PASS: v2.0.0 contains canonical v2 API'
echo 'PASS: v1.0.0 remains historical v1 API'

echo
echo 'Documentation generated:'
echo "  $site_dir/"
echo "  $site_dir/v2.0.0/"
echo "  $site_dir/v1.0.0/"
echo "  $site_dir/versions.html"
