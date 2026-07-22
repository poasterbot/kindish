#!/usr/bin/env python3
"""Send one primary-pointer tap to Kindish's local QEMU VNC server."""

import argparse
import socket
import struct
import time


def receive_exact(sock: socket.socket, count: int) -> bytes:
    chunks = []
    remaining = count
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            raise RuntimeError("VNC server closed the connection")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def connect_vnc(host: str, port: int) -> tuple[socket.socket, int, int]:
    sock = socket.create_connection((host, port), timeout=5)
    version = receive_exact(sock, 12)
    if not version.startswith(b"RFB 003."):
        raise RuntimeError(f"unexpected VNC banner: {version!r}")

    sock.sendall(b"RFB 003.008\n")
    security_type_count = receive_exact(sock, 1)[0]
    if security_type_count == 0:
        message_length = struct.unpack(">I", receive_exact(sock, 4))[0]
        message = receive_exact(sock, message_length).decode(errors="replace")
        raise RuntimeError(f"VNC security negotiation failed: {message}")

    security_types = receive_exact(sock, security_type_count)
    if 1 not in security_types:
        raise RuntimeError("VNC server does not permit an unauthenticated local connection")
    sock.sendall(b"\x01")

    security_result = struct.unpack(">I", receive_exact(sock, 4))[0]
    if security_result != 0:
        message_length = struct.unpack(">I", receive_exact(sock, 4))[0]
        message = receive_exact(sock, message_length).decode(errors="replace")
        raise RuntimeError(f"VNC authentication failed: {message}")

    sock.sendall(b"\x01")
    server_init = receive_exact(sock, 24)
    width, height = struct.unpack(">HH", server_init[:4])
    name_length = struct.unpack(">I", server_init[20:24])[0]
    receive_exact(sock, name_length)
    return sock, width, height


def pointer_event(sock: socket.socket, buttons: int, x: int, y: int) -> None:
    sock.sendall(struct.pack(">BBHH", 5, buttons, x, y))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("x", type=int)
    parser.add_argument("y", type=int)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5906)
    parser.add_argument("--hold-ms", type=int, default=80)
    args = parser.parse_args()

    sock, width, height = connect_vnc(args.host, args.port)
    with sock:
        if not 0 <= args.x < width or not 0 <= args.y < height:
            raise SystemExit(f"tap ({args.x}, {args.y}) is outside {width}x{height}")
        pointer_event(sock, 0, args.x, args.y)
        pointer_event(sock, 1, args.x, args.y)
        time.sleep(args.hold_ms / 1000)
        pointer_event(sock, 0, args.x, args.y)


if __name__ == "__main__":
    main()
