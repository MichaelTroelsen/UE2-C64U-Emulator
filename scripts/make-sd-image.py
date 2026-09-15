#!/usr/bin/env python3
"""Build a sample SD-card image, portably.

`make-sd-image.sh` does the same thing but formats the volume with `hdiutil`, `newfs_msdos` and
`diskutil`, so it only runs on macOS. This script generates the identical sample files and then
hands the directory to `ue2-mkimage` (crates/ue2-vfat/src/bin/ue2-mkimage.rs), which writes the
MBR and the FAT32 volume with the same `ue2-vfat` code `--usb-dir` uses. It therefore works on
Linux, in WSL and on Windows.

    scripts/make-sd-image.py run/sd.img [sizeMB] [extra-file ...]

The sample files are byte-compatible with the shell script's, because `scripts/smoke-sd.ctl`
asserts their sizes (`hello.prg PRG 29`, `readme.txt TXT 71`, `demo.d64 D64 171K`).
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SECTOR = 256
SECTORS = 683  # 35 tracks -> 174848 bytes, "171K" in the browser
BAM, DIR, DATA = 357, 358, 336  # track 18/0, 18/1, 17/0


def track_sectors(track: int) -> int:
    """Sectors per track in the 35-track layout."""
    if track <= 17:
        return 21
    if track <= 24:
        return 19
    if track <= 30:
        return 18
    return 17


def pad(text: str, fill: int, width: int) -> bytes:
    """`text` as PETSCII (identical to ASCII for the upper-case set used here), padded to `width`."""
    raw = text.encode("ascii")
    if len(raw) > width:
        raise ValueError(f"{text!r} does not fit in {width} bytes")
    return raw + bytes([fill]) * (width - len(raw))


def hello_prg() -> bytes:
    """Tokenised BASIC: load address $0801, line 10 `PRINT"HELLO FROM UE2EMU"`, end of program."""
    body = b"\x01\x08\x1a\x08\x0a\x00\x99\x22" + pad("HELLO FROM UE2EMU", 0, 17) + b"\x22\x00\x00\x00"
    assert len(body) == 29, f"smoke-sd.ctl expects 29 bytes, got {len(body)}"
    return body


def demo_d64(prg: bytes) -> bytes:
    """A 35-track D64 holding one PRG `HELLO` at 17/0, disk name `UE2EMU DEMO` id `UE`."""
    img = bytearray(SECTOR * SECTORS)

    # BAM: link to 18/1, DOS version 'A', then free count + 3-byte free bitmap per track.
    bam = bytearray(b"\x12\x01\x41\x00")
    for track in range(1, 36):
        n = track_sectors(track)
        used = 0x1 if track == 17 else 0x3 if track == 18 else 0  # 17/0 data; 18/0 BAM, 18/1 dir
        bits = ((1 << n) - 1) & ~used
        free = n - sum((used >> s) & 1 for s in range(n))
        bam += bytes([free, bits & 0xFF, (bits >> 8) & 0xFF, (bits >> 16) & 0xFF])
    bam += pad("UE2EMU DEMO", 0xA0, 16) + b"\xa0\xa0" + pad("UE", 0, 2) + b"\xa0" + pad("2A", 0, 2) + b"\xa0" * 4
    img[BAM * SECTOR : BAM * SECTOR + len(bam)] = bam

    # Directory: last sector, entry 0 = closed PRG at 17/0, one block.
    entry = b"\x00\xff\x82\x11\x00" + pad("HELLO", 0xA0, 16) + b"\x00" * 9 + b"\x01\x00"
    assert len(entry) == 32, len(entry)
    img[DIR * SECTOR : DIR * SECTOR + len(entry)] = entry

    # Data: last block, index of the last used byte, then the PRG.
    block = bytes([0x00, len(prg) + 1]) + prg
    img[DATA * SECTOR : DATA * SECTOR + len(block)] = block
    return bytes(img)


README = "UE2-C64U-Emulator sample SD card.\nCreated by scripts/make-sd-image.py.\n"


def find_mkimage(repo: Path) -> list[str]:
    """`$UE2_MKIMAGE`, else a built binary, else build it through cargo."""
    if env := os.environ.get("UE2_MKIMAGE"):
        return [env]
    target = Path(os.environ.get("CARGO_TARGET_DIR", repo / "target"))
    for profile in ("release", "debug"):
        for name in ("ue2-mkimage", "ue2-mkimage.exe"):
            candidate = target / profile / name
            if candidate.is_file():
                return [str(candidate)]
    if not shutil.which("cargo"):
        sys.exit("ue2-mkimage is not built and cargo is not on PATH; set UE2_MKIMAGE to its path")
    return ["cargo", "run", "--release", "--quiet", "-p", "ue2-vfat", "--bin", "ue2-mkimage", "--"]


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        sys.exit(__doc__)
    image = Path(argv[0])
    size_mb = 64
    extras: list[Path] = []
    rest = argv[1:]
    if rest and rest[0].isdigit():
        size_mb, rest = int(rest[0]), rest[1:]
    if size_mb < 40:
        sys.exit(f"size {size_mb} MB is below the 40 MB minimum")
    extras = [Path(p) for p in rest]
    for extra in extras:
        if not extra.is_file():
            sys.exit(f"{extra}: not a file")

    repo = Path(__file__).resolve().parent.parent
    image.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="ue2-sd-") as tmp:
        files = Path(tmp)
        prg = hello_prg()
        (files / "hello.prg").write_bytes(prg)
        (files / "demo.d64").write_bytes(demo_d64(prg))
        (files / "readme.txt").write_text(README, newline="\n")
        for extra in extras:
            shutil.copy2(extra, files / extra.name)

        cmd = find_mkimage(repo) + [str(image), str(files), "--size", f"{size_mb}M", "--label", "UE2SD", "--force"]
        proc = subprocess.run(cmd, cwd=repo)
        return proc.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
