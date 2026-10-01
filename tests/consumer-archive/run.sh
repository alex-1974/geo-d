#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
compiler="${1:-dmd}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git -C "$root" archive --format=tar HEAD > "$work/consumer.tar"
python3 "$root/tools/verify-consumer-archive.py" --archive "$work/consumer.tar"
python3 "$root/tests/consumer-archive/test_gate.py"

mkdir "$work/package"
tar -xf "$work/consumer.tar" -C "$work/package"
cp -R "$root/tests/consumer" "$work/consumer"
python3 - "$work/consumer/dub.sdl" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace('targetPath "../../build/consumer"', 'targetPath "build"')
text = text.replace('path="../.."', 'path="../package"')
path.write_text(text)
PY

# The dependency is the extracted consumer package, never the Git checkout.
cd "$work/consumer"
dub run --compiler="$compiler" --force
