#!/usr/bin/env python3
"""Extend the stock wifid scan deadline for qemu-user scheduling latency."""

from pathlib import Path
import sys


OFFSET = 0x5333E
STOCK_MOVW_10000 = bytes.fromhex("42 f2 10 71")
PATCHED_MOVW_60000 = bytes.fromhex("4e f6 60 21")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} WIFID", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    image = bytearray(path.read_bytes())
    instruction = bytes(image[OFFSET : OFFSET + 4])
    if instruction == PATCHED_MOVW_60000:
        return 0
    if instruction != STOCK_MOVW_10000:
        print(
            f"refusing to patch unexpected wifid instruction at {OFFSET:#x}: "
            f"{instruction.hex(' ')}",
            file=sys.stderr,
        )
        return 1

    image[OFFSET : OFFSET + 4] = PATCHED_MOVW_60000
    path.write_bytes(image)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
