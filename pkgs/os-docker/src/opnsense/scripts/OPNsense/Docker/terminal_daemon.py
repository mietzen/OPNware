#!/usr/bin/env python3
"""
Interactive XTerm.js PTY WebSocket Bridge Daemon for Docker.
Connects browser XTerm clients to container shells via docker exec.
"""

import argparse
import asyncio
import base64
import errno
import fcntl
import hashlib
import json
import os
import pty
import re
import signal
import struct
import sys
import termios
from urllib.parse import parse_qs, urlparse

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
OPCODE_CONT = 0x0
OPCODE_TEXT = 0x1
OPCODE_BIN = 0x2
OPCODE_CLOSE = 0x8
OPCODE_PING = 0x9
OPCODE_PONG = 0xA

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 7682
DEFAULT_SHELL = "/bin/sh"
DEFAULT_ROWS = 24
DEFAULT_COLS = 80
READ_CHUNK_SIZE = 4096

CID_PATTERN = re.compile(r"^[a-zA-Z0-9_.-]+$")
SHELL_PATTERN = re.compile(r"^(/[a-zA-Z0-9_.-]+)+$")
SESSION_PATH_PATTERN = re.compile(r"^[a-zA-Z0-9,-]+$")


def compute_ws_accept(key: str) -> str:
    raw = (key.strip() + WS_GUID).encode("utf-8")
    return base64.b64encode(hashlib.sha1(raw).digest()).decode("utf-8")


def encode_ws_frame(payload: bytes, opcode: int = OPCODE_BIN) -> bytes:
    length = len(payload)
    header = bytearray()
    header.append(0x80 | opcode)

    if length <= 125:
        header.append(length)
    elif length <= 65535:
        header.append(126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(127)
        header.extend(struct.pack("!Q", length))

    return bytes(header) + payload


async def read_exact(reader: asyncio.StreamReader, n: int) -> bytes:
    buf = await reader.readexactly(n)
    return buf


async def parse_ws_frame(reader: asyncio.StreamReader):
    try:
        head = await read_exact(reader, 2)
    except (asyncio.IncompleteReadError, EOFError):
        return None, None

    b0, b1 = head[0], head[1]
    fin = bool(b0 & 0x80)
    opcode = b0 & 0x0F
    is_masked = bool(b1 & 0x80)
    length = b1 & 0x7F

    if length == 126:
        ext = await read_exact(reader, 2)
        length = struct.unpack("!H", ext)[0]
    elif length == 127:
        ext = await read_exact(reader, 8)
        length = struct.unpack("!Q", ext)[0]

    mask = await read_exact(reader, 4) if is_masked else None
    data = await read_exact(reader, length) if length > 0 else b""

    if is_masked and mask:
        unmasked = bytearray(length)
        for i in range(length):
            unmasked[i] = data[i] ^ mask[i % 4]
        data = bytes(unmasked)

    return opcode, data


def set_pty_size(fd: int, rows: int, cols: int):
    try:
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)
    except Exception:
        pass


class ContainerSession:
    def __init__(self, cid: str, shell: str, rows: int, cols: int):
        self.cid = cid
        self.shell = shell
        self.rows = rows
        self.cols = cols
        self.master_fd = None
        self.pid = None
        self.history = bytearray()
        self.max_history = 100000

    def start(self):
        master_fd, slave_fd = pty.openpty()
        set_pty_size(master_fd, self.rows, self.cols)

        pid = os.fork()
        if pid == 0:
            # Child process
            os.close(master_fd)
            os.setsid()
            fcntl.ioctl(slave_fd, termios.TIOCSCTTY, 0)

            os.dup2(slave_fd, 0)
            os.dup2(slave_fd, 1)
            os.dup2(slave_fd, 2)
            if slave_fd > 2:
                os.close(slave_fd)

            cmd = [
                "/usr/local/bin/docker",
                "-H", "ssh://root@100.64.0.2",
                "exec",
                "-it",
                "-e", "TERM=xterm-256color",
                "-e", "LANG=en_US.UTF-8",
                self.cid,
                self.shell
            ]
            os.environ["TERM"] = "xterm-256color"
            os.environ["DOCKER_HOST"] = "ssh://root@100.64.0.2"
            try:
                os.execv(cmd[0], cmd)
            except Exception as e:
                print(f"Exec failed: {e}", file=sys.stderr)
                os._exit(1)
        else:
            # Parent
            os.close(slave_fd)
            # Set non-blocking on master_fd
            flags = fcntl.fcntl(master_fd, fcntl.F_GETFL)
            fcntl.fcntl(master_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

            self.master_fd = master_fd
            self.pid = pid

    def append_history(self, chunk: bytes):
        self.history.extend(chunk)
        if len(self.history) > self.max_history:
            self.history = self.history[-self.max_history:]

    def close(self):
        if self.master_fd is not None:
            try:
                os.close(self.master_fd)
            except Exception:
                pass
            self.master_fd = None

        if self.pid is not None:
            try:
                os.kill(self.pid, signal.SIGTERM)
            except Exception:
                pass
            try:
                os.waitpid(self.pid, os.WNOHANG)
            except Exception:
                pass
            self.pid = None


class TerminalDaemon:
    def __init__(self, host=DEFAULT_HOST, port=DEFAULT_PORT):
        self.host = host
        self.port = port
        self.sessions = {}

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        try:
            req_line = await reader.readline()
            if not req_line:
                writer.close()
                return

            req_str = req_line.decode("utf-8", errors="ignore")
            parts = req_str.strip().split()
            if len(parts) < 2 or parts[0].upper() != "GET":
                writer.close()
                return

            path = parts[1]
            headers = {}
            while True:
                line = await reader.readline()
                if not line or line == b"\r\n" or line == b"\n":
                    break
                line_str = line.decode("utf-8", errors="ignore").strip()
                if ":" in line_str:
                    k, v = line_str.split(":", 1)
                    headers[k.strip().lower()] = v.strip()

            sec_key = headers.get("sec-websocket-key")
            if not sec_key:
                writer.write(b"HTTP/1.1 400 Bad Request\r\n\r\nMissing Sec-WebSocket-Key")
                await writer.drain()
                writer.close()
                return

            accept_val = compute_ws_accept(sec_key)
            resp = (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept_val}\r\n"
                "\r\n"
            )
            writer.write(resp.encode("utf-8"))
            await writer.drain()

            parsed = urlparse(path)
            qs = parse_qs(parsed.query)

            cid = qs.get("id", [None])[0] or qs.get("cid", [None])[0]
            if not cid or not CID_PATTERN.match(cid):
                # Try path /api/docker/terminal/ws/<cid>
                path_match = re.search(r"/ws/([^/?]+)", parsed.path)
                if path_match:
                    cid = path_match.group(1)

            if not cid or not CID_PATTERN.match(cid):
                err_msg = "\r\n\x1b[31mError: Invalid or missing container ID.\x1b[0m\r\n"
                writer.write(encode_ws_frame(err_msg.encode("utf-8"), OPCODE_BIN))
                await writer.drain()
                writer.close()
                return

            shell = qs.get("shell", [DEFAULT_SHELL])[0]
            if not SHELL_PATTERN.match(shell):
                shell = DEFAULT_SHELL

            rows = int(qs.get("rows", [DEFAULT_ROWS])[0])
            cols = int(qs.get("cols", [DEFAULT_COLS])[0])

            session_key = f"{cid}_{shell}"
            session = self.sessions.get(session_key)

            # If existing session PID died, reset it
            if session:
                try:
                    res = os.waitpid(session.pid, os.WNOHANG)
                    if res[0] != 0:
                        session.close()
                        session = None
                except Exception:
                    session.close()
                    session = None

            if not session:
                session = ContainerSession(cid, shell, rows, cols)
                session.start()
                self.sessions[session_key] = session
            else:
                set_pty_size(session.master_fd, rows, cols)

            out_queue = asyncio.Queue()

            async def ws_sender():
                try:
                    while True:
                        payload, opcode = await out_queue.get()
                        frame = encode_ws_frame(payload, opcode)
                        writer.write(frame)
                        await writer.drain()
                        out_queue.task_done()
                except Exception:
                    pass

            sender_task = asyncio.create_task(ws_sender())

            # Send back history
            if session.history:
                await out_queue.put((bytes(session.history), OPCODE_BIN))

            loop = asyncio.get_running_loop()

            def on_pty_readable():
                if session.master_fd is None:
                    return
                try:
                    data = os.read(session.master_fd, READ_CHUNK_SIZE)
                    if data:
                        session.append_history(data)
                        asyncio.create_task(out_queue.put((data, OPCODE_BIN)))
                    else:
                        loop.remove_reader(session.master_fd)
                except (BlockingIOError, InterruptedError):
                    pass
                except OSError as e:
                    if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK, errno.EINTR):
                        pass
                    else:
                        try:
                            loop.remove_reader(session.master_fd)
                        except Exception:
                            pass

            loop.add_reader(session.master_fd, on_pty_readable)

            # Read WS frames from client
            try:
                while True:
                    opcode, data = await parse_ws_frame(reader)
                    if opcode is None or opcode == OPCODE_CLOSE:
                        break
                    elif opcode == OPCODE_PING:
                        await out_queue.put((data, OPCODE_PONG))
                    elif opcode in (OPCODE_TEXT, OPCODE_BIN):
                        if data:
                            # Check for JSON resize message
                            if data.startswith(b"{") and b"resize" in data:
                                try:
                                    msg = json.loads(data.decode("utf-8"))
                                    if msg.get("action") == "resize":
                                        r = int(msg.get("rows", rows))
                                        c = int(msg.get("cols", cols))
                                        set_pty_size(session.master_fd, r, c)
                                        continue
                                except Exception:
                                    pass
                            try:
                                os.write(session.master_fd, data)
                            except Exception:
                                break
            finally:
                try:
                    if session.master_fd is not None:
                        loop.remove_reader(session.master_fd)
                except Exception:
                    pass
                sender_task.cancel()
                writer.close()

        except Exception:
            writer.close()

    async def start(self):
        server = await asyncio.start_server(self.handle_client, self.host, self.port)
        async with server:
            await server.serve_forever()


def main():
    daemon = TerminalDaemon()
    try:
        asyncio.run(daemon.start())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
