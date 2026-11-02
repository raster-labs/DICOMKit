#!/usr/bin/env python3
"""Reject DICOM payloads in tracked files, including renamed and archived inputs.

Synthetic files are prohibited too. Tests must generate them outside the checkout.
This is a repository-content guard, not a PHI classifier or a Git-history purge.
Only tracked working-tree files are scanned; deleted files are omitted. Archive
members are inspected in memory, never extracted, with fail-closed size limits.
"""
from __future__ import annotations

import argparse
import bz2
import gzip
import io
import json
import lzma
from pathlib import Path
import struct
import subprocess
import tarfile
import zipfile

DICOM_EXTENSIONS = {".dcm", ".dicom", ".ima", ".dcmdata"}
ARCHIVE_EXTENSIONS = {".zip", ".tar", ".gz", ".tgz", ".bz2", ".xz", ".7z", ".rar"}
VRS = {v.encode() for v in "AE AS AT CS DA DS DT FD FL IS LO LT OB OD OF OL OV OW PN SH SL SQ SS ST SV TM UC UI UL UN UR US UT UV".split()}
LONG_VRS = {v.encode() for v in "OB OD OF OL OV OW SQ UC UN UR UT".split()}
START_GROUPS = {0x0002, 0x0008, 0x0010, 0x0018, 0x0020, 0x0028, 0x0040, 0x0070, 0x7FE0}
MAX_BYTES = 128 * 1024 * 1024
MAX_DEPTH = 4
MAX_MEMBERS = 10000


def raw_dataset(data: bytes) -> bool:
    """Recognize plausible preamble-free explicit/implicit datasets, either order."""
    for order in ("<", ">"):
        for explicit in (True, False):
            offset = 0
            count = 0
            previous = (-1, -1)
            while offset + 8 <= len(data):
                tag = struct.unpack_from(order + "HH", data, offset)
                if (count == 0 and tag[0] not in START_GROUPS) or tag < previous:
                    break
                if explicit:
                    vr = data[offset + 4:offset + 6]
                    if vr not in VRS:
                        break
                    long = vr in LONG_VRS
                    header = 12 if long else 8
                    if offset + header > len(data):
                        break
                    length = struct.unpack_from(order + ("I" if long else "H"), data, offset + (8 if long else 6))[0]
                else:
                    header = 8
                    length = struct.unpack_from(order + "I", data, offset + 4)[0]
                if length % 2 or offset + header + length > len(data):
                    break
                count += 1
                if count >= 3:
                    return True
                offset += header + length
                previous = tag
    return False


def inspect_payload(name: str, data: bytes, findings: list[dict], depth: int = 0,
                    budget: list[int] | None = None) -> None:
    budget = budget if budget is not None else [MAX_BYTES, MAX_MEMBERS]

    def reject(reason: str) -> None:
        findings.append({"path": name, "reason": reason})

    leaf = Path(name.rsplit("!", 1)[-1])
    if name.startswith("Documentation/2026a-milestones/") and leaf.suffix.lower() in {".bin", ".dat", ".pdu", ".pcap"}:
        reject("opaque milestone wire payload or peer database")
        return
    if leaf.suffix.lower() in DICOM_EXTENSIONS or leaf.name.upper() == "DICOMDIR":
        reject("DICOM filename")
        return
    if data[128:132] == b"DICM":
        reject("DICOM Part 10 signature")
        return
    if raw_dataset(data):
        reject("preamble-free DICOM dataset")
        return
    if data.startswith(b"version https://git-lfs.github.com/spec/v1"):
        reject("uninspected Git LFS payload")
        return

    is_zip = data.startswith((b"PK\x03\x04", b"PK\x05\x06", b"PK\x07\x08"))
    is_gzip = data.startswith(b"\x1f\x8b")
    is_bzip = data.startswith(b"BZh")
    is_xz = data.startswith(b"\xfd7zXZ\x00")
    is_tar = data[257:262] == b"ustar" or leaf.suffix.lower() == ".tar"
    if not (is_zip or is_gzip or is_bzip or is_xz or is_tar or leaf.suffix.lower() in ARCHIVE_EXTENSIONS):
        return
    if depth >= MAX_DEPTH:
        reject("archive nesting limit exceeded")
        return

    def member(member_name: str, stream, size: int | None = None) -> None:
        if budget[1] <= 0 or (size is not None and size > budget[0]):
            raise ValueError("archive scan budget exceeded")
        content = stream.read(budget[0] + 1)
        if len(content) > budget[0]:
            raise ValueError("archive byte budget exceeded")
        budget[0] -= len(content)
        budget[1] -= 1
        inspect_payload(name + "!" + member_name, content, findings, depth + 1, budget)

    try:
        if is_zip:
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                for info in archive.infolist():
                    if not info.is_dir():
                        with archive.open(info) as stream:
                            member(info.filename, stream, info.file_size)
        elif is_tar:
            with tarfile.open(fileobj=io.BytesIO(data), mode="r:") as archive:
                for info in archive:
                    if info.isfile():
                        with archive.extractfile(info) as stream:
                            member(info.name, stream, info.size)
                    elif not info.isdir():
                        raise ValueError("uninspected archive link/special file")
        elif is_gzip or is_bzip or is_xz:
            opener = gzip.open if is_gzip else bz2.BZ2File if is_bzip else lzma.LZMAFile
            # Detect tar from its content even when the outer name is .tgz.
            with opener(io.BytesIO(data), "rb") as stream:
                member(leaf.stem, stream)
        else:
            raise ValueError("unsupported or malformed archive")
    except (OSError, ValueError, EOFError, RuntimeError, zipfile.BadZipFile, tarfile.TarError, lzma.LZMAError):
        reject("archive could not be completely inspected")


def scan(root: Path) -> dict:
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    findings: list[dict] = []
    scanned = 0
    for name in filter(None, names):
        path = root / name
        if path.is_symlink():
            # Never follow a tracked link outside the checkout or hide payloads
            # behind a link. The evidence tree needs no tracked symlinks.
            findings.append({"path": name, "reason": "uninspected symbolic link"})
            continue
        if not path.exists():
            continue
        scanned += 1
        try:
            with path.open("rb") as stream:
                data = stream.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                findings.append({"path": name, "reason": "file scan byte limit exceeded"})
            else:
                inspect_payload(name, data, findings)
        except OSError:
            findings.append({"path": name, "reason": "file unreadable"})
    return {"tracked_files_scanned": scanned, "findings": findings,
            "status": "failed" if findings else "passed",
            "scope": "tracked working tree; Git history and other refs are not scanned"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path("."))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = scan(args.root.resolve())
    if args.report:
        args.report.write_text(json.dumps(result, indent=2) + "\n")
    print(f"[no-dicom] {result['tracked_files_scanned']} tracked files; {len(result['findings'])} prohibited/uninspected payloads")
    for finding in result["findings"]:
        print(f"  {finding['path']}: {finding['reason']}")
    return 1 if result["findings"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
