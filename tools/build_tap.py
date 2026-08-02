#!/usr/bin/env python3
"""Build the complete COOPER RUN TAP image.

The output contains a BASIC autoloader, a 6912-byte loading screen at 16384,
and the game code at 32768. No third-party Python packages are required.
"""
from __future__ import annotations
import argparse
import struct
from pathlib import Path

CODE_ADDRESS = 32768
SCREEN_ADDRESS = 16384


def checksum(block: bytes) -> int:
    value = 0
    for byte in block:
        value ^= byte
    return value


def make_header(block_type: int, name: str, length: int, param1: int, param2: int) -> bytes:
    encoded_name = name.ljust(10)[:10].encode("latin-1")
    return bytes([block_type]) + encoded_name + struct.pack("<HHH", length, param1, param2)


def tap_block(flag: int, payload: bytes) -> bytes:
    body = bytes([flag]) + payload
    body += bytes([checksum(body)])
    return struct.pack("<H", len(body)) + body


def code_blocks(name: str, data: bytes, load_address: int) -> bytes:
    header = make_header(3, name, len(data), load_address, 0x8000)
    return tap_block(0x00, header) + tap_block(0xFF, data)


def build_tap(loader_path: Path, screen_path: Path, code_path: Path, output_path: Path) -> None:
    basic = loader_path.read_bytes()
    if len(basic) < 2:
        raise ValueError("The BASIC loader block is too short.")
    screen = screen_path.read_bytes()
    if len(screen) != 6912:
        raise ValueError(f"Expected a 6912-byte loading screen, found {len(screen)} bytes.")
    code = code_path.read_bytes()
    if not code:
        raise ValueError("The compiled game code is empty.")

    basic_length = len(basic) - 2  # Exclude flag and checksum.
    basic_header = make_header(0, "COOPER RUN", basic_length, 10, basic_length)

    tap = tap_block(0x00, basic_header)
    tap += struct.pack("<H", len(basic)) + basic
    tap += code_blocks("screen", screen, SCREEN_ADDRESS)
    tap += code_blocks("cooper", code, CODE_ADDRESS)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(tap)
    print(f"Built {output_path} ({len(tap)} bytes)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the complete COOPER RUN TAP image.")
    parser.add_argument("--loader", type=Path, default=Path("assets/basic_loader.bin"))
    parser.add_argument("--screen", type=Path, default=Path("assets/loading_screen.scr"))
    parser.add_argument("--code", type=Path, default=Path("build/cooper.bin"))
    parser.add_argument("--output", type=Path, default=Path("build/CooperRun.tap"))
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    build_tap(args.loader, args.screen, args.code, args.output)
