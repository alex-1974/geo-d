#!/usr/bin/env python3
"""Verify a real git archive against the independent consumer manifest."""

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile


ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def verify(archive, manifest, commit, prefix=""):
    tracked = {}
    for entry in git("ls-tree", "-r", "-z", commit).split(b"\0"):
        if entry:
            metadata, path = entry.split(b"\t", 1)
            mode, kind, oid = metadata.decode().split()
            tracked[path.decode()] = (mode, kind, oid)

    required = set(manifest["required_files"])
    for tree in manifest["required_trees"]:
        paths = {p for p in tracked if p.startswith(tree)}
        if not paths:
            raise ValueError(f"required source tree is empty: {tree}")
        required.update(paths)

    errors = []
    seen = set()
    files = set()
    allowed_dirs = {str(parent) + "/" for path in required
                    for parent in PurePosixPath(path).parents
                    if str(parent) != "."}
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:*") as tar:
        for member in tar:
            if prefix and member.name.rstrip("/") == prefix.rstrip("/") and member.isdir():
                continue
            if prefix and not member.name.startswith(prefix):
                errors.append(f"path outside expected prefix: {member.name}")
                continue
            path = member.name[len(prefix):] if prefix else member.name
            parts = path.rstrip("/").split("/")
            if path.startswith("/") or any(p in ("", ".", "..") for p in parts):
                errors.append(f"non-canonical archive path: {path}")
                continue
            path = path.rstrip("/")
            if path in seen:
                errors.append(f"duplicate archive path: {path}")
            seen.add(path)
            if (path in manifest["excluded_files"] or
                    any(path == p.rstrip("/") or path.startswith(p)
                        for p in manifest["excluded_trees"])):
                errors.append(f"excluded path present: {path}")
            elif member.isdir():
                if path + "/" not in allowed_dirs:
                    errors.append(f"unapproved directory: {path}")
            elif not member.isfile():
                errors.append(f"unsupported member type: {path}")
            elif path not in required:
                errors.append(f"unapproved file: {path}")
            else:
                files.add(path)
                if path not in tracked:
                    errors.append(f"required file is not tracked: {path}")
                    continue
                mode, kind, oid = tracked[path]
                if kind != "blob" or mode not in ("100644", "100755"):
                    errors.append(f"required file is not a regular Git blob: {path}")
                    continue
                content = tar.extractfile(member).read()
                # Compare content to the selected Git object, independently of export-ignore.
                actual = hashlib.sha1(b"blob " + str(len(content)).encode() + b"\0" + content).hexdigest()
                if actual != oid:
                    errors.append(f"content differs from selected commit: {path}")
                if bool(member.mode & 0o111) != (mode == "100755"):
                    errors.append(f"executable mode differs from Git: {path}")

    errors.extend(f"required file missing: {p}" for p in sorted(required - files))
    if errors:
        raise ValueError("\n".join(errors))
    return len(files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default="HEAD", help="commit to qualify (default: HEAD)")
    parser.add_argument("--archive", type=Path, help="inspect an existing tar/tar.gz instead")
    parser.add_argument("--prefix", default="", help="exact archive prefix, e.g. geo-d-COMMIT/")
    args = parser.parse_args()
    if args.prefix and (not args.prefix.endswith("/") or not args.archive):
        parser.error("--prefix requires --archive and a trailing slash")
    try:
        commit = git("rev-parse", "--verify", args.ref + "^{commit}").decode().strip()
        manifest = json.loads(git("show", commit + ":tests/consumer-archive/manifest.json"))
        archive = args.archive.read_bytes() if args.archive else git("archive", "--format=tar", commit)
        count = verify(archive, manifest, commit, args.prefix)
    except (ValueError, OSError, subprocess.CalledProcessError, tarfile.TarError) as error:
        print(f"CONSUMER ARCHIVE FAIL: {error}", file=sys.stderr)
        return 1
    print(f"CONSUMER ARCHIVE PASS: {count} files; complete source; commit {commit}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
