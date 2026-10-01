#!/usr/bin/env python3
"""Negative controls using a real archive and independently damaged copies."""

import io
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ArchiveGateControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.archive = subprocess.check_output(
            ["git", "-C", str(ROOT), "archive", "--format=tar", "HEAD"])

    def check(self, *, omit=None, change=None, extra=None, prefix="", diagnostic=None):
        buffer = io.BytesIO()
        with tarfile.open(fileobj=io.BytesIO(self.archive)) as source:
            with tarfile.open(fileobj=buffer, mode="w") as target:
                for member in source:
                    if member.name == omit:
                        continue
                    data = source.extractfile(member).read() if member.isfile() else None
                    if member.name == change:
                        data += b"\n// archive tampering control\n"
                        member.size = len(data)
                    member.name = prefix + member.name
                    target.addfile(member, io.BytesIO(data) if data is not None else None)
                if extra:
                    target.addfile(extra, io.BytesIO(b"x") if extra.isfile() else None)
        with tempfile.TemporaryDirectory() as work:
            archive = Path(work) / "control.tar"
            archive.write_bytes(buffer.getvalue())
            command = ["python3", str(ROOT / "tools/verify-consumer-archive.py"),
                       "--archive", str(archive)]
            if prefix:
                command.extend(["--prefix", prefix])
            result = subprocess.run(command, capture_output=True, text=True)
        if diagnostic:
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(diagnostic, result.stderr)
        else:
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_valid_archive_and_prefixed_archive(self):
        self.check()
        self.check(prefix="geo-d-control/")

    def test_missing_license(self):
        self.check(omit="LICENSE", diagnostic="required file missing: LICENSE")

    def test_missing_internal_production_module(self):
        path = "source/geo/internal/segment_polygon_clip_p1.d"
        self.check(omit=path, diagnostic="required file missing: " + path)

    def test_changed_production_content(self):
        path = "source/geo/package.d"
        self.check(change=path, diagnostic="content differs from selected commit: " + path)

    def test_leaked_research_and_unknown_file(self):
        for path, diagnostic in [("research/probe.d", "excluded path present"),
                                 ("docs/unapproved.md", "unapproved file")]:
            with self.subTest(path=path):
                member = tarfile.TarInfo(path)
                member.size = 1
                self.check(extra=member, diagnostic=diagnostic)

    def test_duplicate_path(self):
        member = tarfile.TarInfo("LICENSE")
        member.size = 1
        self.check(extra=member, diagnostic="duplicate archive path: LICENSE")

    def test_link_and_noncanonical_path(self):
        member = tarfile.TarInfo("source/linked.d")
        member.type = tarfile.SYMTYPE
        member.linkname = "package.d"
        self.check(extra=member, diagnostic="unsupported member type")
        member = tarfile.TarInfo("../escape")
        member.size = 1
        self.check(extra=member, diagnostic="non-canonical archive path")


if __name__ == "__main__":
    unittest.main()
