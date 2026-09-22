#!/usr/bin/env bash
set -euo pipefail

COMPILER="${1:-dmd}"

HERE="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
)"

ROOT="$(
    cd "$HERE/../.."
    pwd
)"

GEO3_COMMIT="$(
    tr -d '[:space:]' \
        < "$HERE/geo3-d.commit"
)"

CORE_VERSION="$(
    tr -d '[:space:]' \
        < "$HERE/euclid-core.version"
)"

if ! [[ "$GEO3_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo 'ERROR: invalid geo3-d commit pin'
    exit 1
fi

if ! [[ "$CORE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'ERROR: invalid euclid-core-d version pin'
    exit 1
fi

TMP="$(
    mktemp -d \
        "${TMPDIR:-/tmp}/geo-family-consumer.XXXXXX"
)"

trap 'rm -rf "$TMP"' EXIT

GEO3="$TMP/geo3-d"
CONSUMER="$TMP/consumer"

echo '--- family consumer configuration ---'
printf 'geo-d:    %s\n' "$ROOT"
printf 'geo3-d:   %s\n' "$GEO3_COMMIT"
printf 'Core:     %s\n' "$CORE_VERSION"
printf 'compiler: %s\n' "$COMPILER"
printf 'temp:     %s\n' "$TMP"

echo
echo '--- fetch pinned geo3-d ---'

git init -q "$GEO3"

git -C "$GEO3" remote add \
    origin \
    https://github.com/alex-1974/geo3-d.git

git -C "$GEO3" fetch \
    --quiet \
    --depth=1 \
    origin \
    "$GEO3_COMMIT"

git -C "$GEO3" checkout \
    --quiet \
    --detach \
    FETCH_HEAD

ACTUAL_GEO3="$(
    git -C "$GEO3" rev-parse HEAD
)"

printf 'resolved geo3-d: %s\n' "$ACTUAL_GEO3"

test "$ACTUAL_GEO3" = "$GEO3_COMMIT"

echo
echo '--- verify sibling Core manifests ---'

for manifest in \
    "$ROOT/dub.sdl" \
    "$GEO3/dub.sdl"
do
    grep -Eq \
        'dependency[[:space:]]+"euclid-core-d"[[:space:]]+version=' \
        "$manifest"

    if grep -nE \
        'dependency[[:space:]]+"euclid-core-d".*path=' \
        "$manifest"
    then
        echo "ERROR: path-based Core dependency in $manifest"
        exit 1
    fi
done

echo 'PASS: both siblings use versioned Core dependencies'

echo
echo '--- create temporary root consumer ---'

mkdir -p "$CONSUMER/source"

cp \
    "$HERE/source/app.d" \
    "$CONSUMER/source/app.d"

python3 - \
    "$CONSUMER/dub.json" \
    "$ROOT" \
    "$GEO3" <<'PY_MANIFEST'
import json
from pathlib import Path
import sys

output = Path(sys.argv[1])
geo = str(Path(sys.argv[2]).resolve())
geo3 = str(Path(sys.argv[3]).resolve())

data = {
    "name": "geo-family-consumer-test",
    "description": (
        "Durable geo-d / geo3-d coexistence verification"
    ),
    "license": "MIT",
    "targetType": "executable",
    "dependencies": {
        "geo-d": {
            "path": geo,
        },
        "geo3-d": {
            "path": geo3,
        },
    },
}

output.write_text(
    json.dumps(
        data,
        indent=4,
    )
    + "\n"
)
PY_MANIFEST

python3 - \
    "$CONSUMER/dub.selections.json" \
    "$CORE_VERSION" <<'PY_LOCK'
import json
from pathlib import Path
import sys

output = Path(sys.argv[1])
version = sys.argv[2]

data = {
    "fileVersion": 1,
    "versions": {
        "euclid-core-d": version,
    },
}

output.write_text(
    json.dumps(
        data,
        indent=4,
    )
    + "\n"
)
PY_LOCK

echo
echo '--- verify Core remains transitive only ---'

if grep -F 'euclid-core-d' "$CONSUMER/dub.json"; then
    echo 'ERROR: root consumer directly injects euclid-core-d'
    exit 1
fi

echo 'PASS: root consumer depends only on geo-d and geo3-d'

echo
echo '--- resolve package graph ---'

mapfile -t IMPORT_PATHS < <(
    cd "$CONSUMER"

    dub describe \
        --cache=local \
        --data=import-paths \
        --data-list \
        --compiler="$COMPILER"
)

printf '%s\n' "${IMPORT_PATHS[@]}"

echo
echo '--- verify exact Core lock ---'

python3 - \
    "$CONSUMER/dub.selections.json" \
    "$CORE_VERSION" <<'PY_VERIFY_LOCK'
import json
from pathlib import Path
import sys

data = json.loads(
    Path(sys.argv[1]).read_text()
)

expected = sys.argv[2]

actual = (
    data
    .get("versions", {})
    .get("euclid-core-d")
)

if actual != expected:
    raise SystemExit(
        "ERROR: expected euclid-core-d "
        + expected
        + ", got "
        + repr(actual)
    )

print(
    "PASS: euclid-core-d locked to "
    + expected
)
PY_VERIFY_LOCK

echo
echo '--- verify one registry-backed Core import path ---'

python3 - \
    "$CORE_VERSION" \
    "${IMPORT_PATHS[@]}" <<'PY_PATHS'
from pathlib import Path
import sys

version = sys.argv[1]

paths = [
    Path(value).resolve()
    for value in sys.argv[2:]
]

core_paths = [
    path
    for path in paths
    if "euclid-core-d" in path.parts
]

if len(core_paths) != 1:
    raise SystemExit(
        "ERROR: expected exactly one euclid-core-d import path, got "
        + str(len(core_paths))
        + ": "
        + repr([str(path) for path in core_paths])
    )

core = core_paths[0]
parts = core.parts

if version not in parts:
    raise SystemExit(
        "ERROR: Core import path does not contain pinned version "
        + version
        + ": "
        + str(core)
    )

if ".dub" not in parts or "packages" not in parts:
    raise SystemExit(
        "ERROR: Core did not resolve from the DUB package cache: "
        + str(core)
    )

print(
    "PASS: exactly one registry-backed Core import path"
)

print(
    "Core:",
    core,
)
PY_PATHS

echo
echo '--- run family consumer ---'

(
    cd "$CONSUMER"

    dub run \
        --cache=local \
        --compiler="$COMPILER" \
        --force
)

echo
echo 'PASS: durable family consumer'
