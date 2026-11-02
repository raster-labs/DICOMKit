import gzip
import io
from pathlib import Path
import struct
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

import check_no_dicom as guard


class NoDICOMTests(unittest.TestCase):
    def inspect(self, name, data, **kwargs):
        findings = []
        guard.inspect_payload(name, data, findings, **kwargs)
        return findings

    def test_extensions_and_directory_name(self):
        for name in ["a.dcm", "a.DICOM", "a.IMA", "DICOMDIR", "request.dcmdata"]:
            self.assertTrue(self.inspect(name, b"invalid"))
        self.assertTrue(self.inspect("Documentation/2026a-milestones/M7/wire/request.bin", b"short capture"))
        self.assertTrue(self.inspect("Documentation/2026a-milestones/M6/database/index.dat", b"peer index"))

    def test_extensionless_and_renamed_part10(self):
        for name in ["image", "evidence.bin", "README.txt"]:
            self.assertTrue(self.inspect(name, bytes(128) + b"DICM"))

    def test_raw_explicit_and_implicit_datasets_both_orders(self):
        for order in ["<", ">"]:
            for explicit in [True, False]:
                data = b""
                for group, element in [(8, 0x16), (8, 0x18), (0x10, 0x20)]:
                    data += struct.pack(order + "HH", group, element)
                    data += b"UI" + struct.pack(order + "H", 4) if explicit else struct.pack(order + "I", 4)
                    data += b"1.2\0"
                self.assertTrue(self.inspect("raw.bin", data))

    def test_text_images_and_source_are_allowed(self):
        for data in [b"DICM in documentation", b"\x89PNG\r\n\x1a\n", b"let name = \"file.dcm\"", bytes(256)]:
            self.assertEqual(self.inspect("source.txt", data), [])

    def test_nested_archive_detection_without_extraction(self):
        tar = io.BytesIO()
        with tarfile.open(fileobj=tar, mode="w") as archive:
            data = bytes(128) + b"DICM"
            info = tarfile.TarInfo("../../renamed.bin")
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
        zipped = io.BytesIO()
        with zipfile.ZipFile(zipped, "w") as archive:
            archive.writestr("payload.tgz", gzip.compress(tar.getvalue()))
        findings = self.inspect("not-an-archive.bin", zipped.getvalue())
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0]["reason"], "DICOM Part 10 signature")

    def test_clean_archive(self):
        self.assertEqual(self.inspect("log.gz", gzip.compress(b"synthetic test log")), [])

    def test_archive_failure_limits_and_lfs_fail_closed(self):
        for name, data in [("bad.zip", b"PK\x03\x04broken"), ("bad.gz", b"\x1f\x8b"),
                           ("unknown.7z", b"unknown"), ("lfs.bin", b"version https://git-lfs.github.com/spec/v1\n")]:
            self.assertTrue(self.inspect(name, data))
        self.assertTrue(self.inspect("log.gz", gzip.compress(b"x" * 100), budget=[10, 1]))
        self.assertTrue(self.inspect("log.gz", gzip.compress(b"x"), depth=guard.MAX_DEPTH))

    def test_tracked_only_and_symlinks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            subprocess.run(["git", "init", "-q", temp], check=True)
            (root / "source.txt").write_text("source")
            (root / "generated.dcm").write_bytes(bytes(128) + b"DICM")
            subprocess.run(["git", "add", "source.txt"], cwd=root, check=True)
            self.assertEqual(guard.scan(root)["status"], "passed")
            (root / "link").symlink_to(root / "generated.dcm")
            subprocess.run(["git", "add", "link"], cwd=root, check=True)
            self.assertEqual(guard.scan(root)["status"], "failed")
            (root / "link").unlink()
            self.assertEqual(guard.scan(root)["status"], "passed")


if __name__ == "__main__":
    unittest.main()
