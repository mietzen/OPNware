#!/usr/bin/env python3
"""
Interactive XTerm.js PTY WebSocket Bridge Daemon.
Connects browser XTerm clients to container shells via podman exec.
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
DEFAULT_PORT = 7681
DEFAULT_SHELL = "/bin/sh"
DEFAULT_ROWS = 24
DEFAULT_COLS = 80
READ_CHUNK_SIZE = 4096

CID_PATTERN = re.compile(r"^[a-zA-Z0-9_.-]+$")
SHELL_PATTERN = re.compile(r"^(/[a-zA-Z0-9_.-]+)+$")
SESSION_PATH_PATTERN = re.compile(r"^[a-zA-Z0-9,-]+$")


def compute_ws_accept(key: str) -> str:
    """Compute RFC6455 Sec-WebSocket-Accept token."""
    raw = (key.strip() + WS_GUID).encode("utf-8")
    return base64.b64encode(hashlib.sha1(raw).digest()).decode("utf-8")


def encode_ws_frame(payload: bytes, opcode: int = OPCODE_BIN) -> bytes:
    """Encode an unmasked server-to-client WebSocket frame."""
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
    """Read exactly n bytes or raise EOFError."""
    buf = await reader.readexactly(n)
    return buf


async def parse_ws_frame(reader: asyncio.StreamReader):
    """Read and decode a masked client WebSocket frame."""
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


def set_winsize(fd: int, rows: int, cols: int):
    """Set terminal window size on master PTY."""
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    except OSError:
        pass


def is_authenticated_session(cookie_header: str) -> bool:
    """Validate active authenticated OPNsense PHP session."""
    if not cookie_header:
        return False

    session_dirs = [
        os.getenv("OPNSENSE_SESSION_DIR", "/var/lib/php/sessions"),
        "/tmp",
        "/var/tmp",
    ]

    for part in cookie_header.split(";"):
        part = part.strip()
        if part.startswith("PHPSESSID="):
            sid = part.split("=", 1)[1].strip()
            if SESSION_PATH_PATTERN.match(sid):
                for sdir in session_dirs:
                    sfile = os.path.join(sdir, f"sess_{sid}")
                    if os.path.exists(sfile) and os.path.getsize(sfile) > 0:
                        try:
                            with open(sfile, "r", errors="ignore") as f:
                                content = f.read()
                                if any(marker in content for marker in ("user_name|", "Username|", "user|", "logged_in|")):
                                    return True
                        except OSError:
                            pass
    return False


class TerminalSession:
    """Manages master PTY and container shell process."""

    def __init__(self, cid: str, shell: str):
        self.cid = cid
        self.shell = shell or DEFAULT_SHELL
        self.master_fd = None
        self.pid = None
        self.closed = False

    def start(self):
        """Fork and execute podman exec inside a PTY."""
        master_fd, slave_fd = pty.openpty()
        self.master_fd = master_fd

        set_winsize(master_fd, DEFAULT_ROWS, DEFAULT_COLS)

        pid = os.fork()
        if pid == 0:
            os.close(master_fd)
            os.setsid()
            try:
                fcntl.ioctl(slave_fd, termios.TIOCSCTTY, 0)
            except OSError:
                pass

            os.dup2(slave_fd, 0)
            os.dup2(slave_fd, 1)
            os.dup2(slave_fd, 2)
            if slave_fd > 2:
                os.close(slave_fd)

            cmd = ["/usr/local/bin/podman", "exec", "-it", "--", self.cid, self.shell]
            os.environ["TERM"] = "xterm-256color"
            try:
                os.execv(cmd[0], cmd)
            except Exception:
                os._exit(1)

        os.close(slave_fd)
        self.pid = pid

        flags = fcntl.fcntl(master_fd, fcntl.F_GETFL)
        fcntl.fcntl(master_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

    def write(self, data: bytes):
        """Write user input keystrokes to master PTY."""
        if not self.closed and self.master_fd is not None:
            try:
                os.write(self.master_fd, data)
            except OSError:
                pass

    def resize(self, rows: int, cols: int):
        """Resize PTY window."""
        if not self.closed and self.master_fd is not None:
            set_winsize(self.master_fd, rows, cols)

    def close(self):
        """Terminate child process, close PTY, and reap process."""
        if self.closed:
            return
        self.closed = True

        if self.master_fd is not None:
            try:
                os.close(self.master_fd)
            except OSError:
                pass
            self.master_fd = None

        if self.pid is not None:
            try:
                os.kill(self.pid, signal.SIGTERM)
            except (ProcessLookupError, OSError):
                pass

            try:
                reaped_pid, _ = os.waitpid(self.pid, os.WNOHANG)
                if reaped_pid == 0:
                    try:
                        os.kill(self.pid, signal.SIGKILL)
                    except (ProcessLookupError, OSError):
                        pass
                    os.waitpid(self.pid, os.WNOHANG)
            except (ChildProcessError, OSError):
                pass

            self.pid = None


async def handle_pty_read(session: TerminalSession, writer: asyncio.StreamWriter):
    """Read ANSI binary output from master PTY and stream to WebSocket."""
    loop = asyncio.get_running_loop()
    queue = asyncio.Queue()
    master_fd = session.master_fd

    def on_read():
        try:
            chunk = os.read(master_fd, READ_CHUNK_SIZE)
            if chunk:
                queue.put_nowait(chunk)
            else:
                queue.put_nowait(None)
        except (BlockingIOError, InterruptedError):
            return
        except OSError as e:
            if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK, errno.EINTR):
                return
            queue.put_nowait(None)
        except Exception:
            queue.put_nowait(None)

    if master_fd is not None:
        loop.add_reader(master_fd, on_read)

    try:
        while not session.closed:
            data = await queue.get()
            if data is None:
                break
            frame = encode_ws_frame(data, opcode=OPCODE_BIN)
            writer.write(frame)
            await writer.drain()
    except (asyncio.CancelledError, ConnectionResetError, BrokenPipeError):
        pass
    finally:
        try:
            if master_fd is not None:
                loop.remove_reader(master_fd)
        except (ValueError, OSError):
            pass


async def handle_ws_input(session: TerminalSession, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    """Read WebSocket frames from browser and write to PTY."""
    while not session.closed:
        opcode, data = await parse_ws_frame(reader)
        if opcode is None or opcode == OPCODE_CLOSE:
            break
        elif opcode == OPCODE_PING:
            writer.write(encode_ws_frame(data, opcode=OPCODE_PONG))
            await writer.drain()
        elif opcode in (OPCODE_TEXT, OPCODE_BIN):
            # Control frame prefix (\x00{"type":"resize",...})
            if data.startswith(b"\x00{") and b"resize" in data:
                try:
                    msg = json.loads(data[1:].decode("utf-8"))
                    if msg.get("type") == "resize":
                        r = int(msg.get("rows", DEFAULT_ROWS))
                        c = int(msg.get("cols", DEFAULT_COLS))
                        session.resize(r, c)
                        continue
                except Exception:
                    pass
            session.write(data)


async def handle_ws_conn(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    """Handle WebSocket handshake and bridge session."""
    headers = {}
    path_line = ""

    while True:
        line = await reader.readline()
        if not line or line == b"\r\n":
            break
        decoded = line.decode("utf-8", errors="ignore").rstrip("\r\n")
        if not path_line and (decoded.startswith("GET ") or "HTTP/" in decoded):
            path_line = decoded
            continue
        if ":" in decoded:
            k, v = decoded.split(":", 1)
            headers[k.strip().lower()] = v.strip()

    ws_key = headers.get("sec-websocket-key")
    if not ws_key:
        writer.write(b"HTTP/1.1 400 Bad Request\r\n\r\n")
        await writer.drain()
        writer.close()
        return

    # Check authentication
    cookie_header = headers.get("cookie", "")
    if not is_authenticated_session(cookie_header):
        writer.write(b"HTTP/1.1 401 Unauthorized\r\n\r\n")
        await writer.drain()
        writer.close()
        return

    parsed_url = urlparse(path_line.split(" ")[1] if len(path_line.split(" ")) > 1 else "")
    params = parse_qs(parsed_url.query)
    cid = params.get("cid", [""])[0]
    shell = params.get("shell", [DEFAULT_SHELL])[0]

    if not cid or not CID_PATTERN.match(cid):
        writer.write(b"HTTP/1.1 400 Invalid or missing container ID\r\n\r\n")
        await writer.drain()
        writer.close()
        return

    if not SHELL_PATTERN.match(shell):
        writer.write(b"HTTP/1.1 400 Invalid shell path\r\n\r\n")
        await writer.drain()
        writer.close()
        return

    accept_val = compute_ws_accept(ws_key)
    handshake_resp = (
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Accept: {accept_val}\r\n\r\n"
    )
    writer.write(handshake_resp.encode("utf-8"))
    await writer.drain()

    session = TerminalSession(cid, shell)
    session.start()

    pty_task = asyncio.create_task(handle_pty_read(session, writer))
    ws_task = asyncio.create_task(handle_ws_input(session, reader, writer))

    done, pending = await asyncio.wait(
        [pty_task, ws_task],
        return_when=asyncio.FIRST_COMPLETED
    )

    for task in pending:
        task.cancel()

    session.close()

    try:
        writer.write(encode_ws_frame(b"", opcode=OPCODE_CLOSE))
        await writer.drain()
    except (ConnectionResetError, BrokenPipeError, OSError):
        pass

    writer.close()
    try:
        await writer.wait_closed()
    except Exception:
        pass


def write_pid(path: str):
    """Write daemon process ID to file."""
    if path:
        dir_name = os.path.dirname(path)
        if dir_name:
            os.makedirs(dir_name, exist_ok=True)
        with open(path, "w") as f:
            f.write(f"{os.getpid()}\n")


def remove_pid(path: str):
    """Remove PID file on shutdown."""
    if path and os.path.exists(path):
        try:
            os.remove(path)
        except OSError:
            pass


async def main():
    parser = argparse.ArgumentParser(description="Podman XTerm PTY WebSocket Bridge Daemon")
    parser.add_argument("--host", default=DEFAULT_HOST, help="Bind host")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Bind port")
    parser.add_argument("--pidfile", default=None, help="PID file path")
    args = parser.parse_args()

    if args.pidfile:
        write_pid(args.pidfile)

    server = await asyncio.start_server(handle_ws_conn, args.host, args.port)

    loop = asyncio.get_running_loop()
    stop_event = asyncio.Event()

    def on_signal():
        stop_event.set()

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, on_signal)

    print(f"Podman Terminal Daemon listening on {args.host}:{args.port} (PID {os.getpid()})")

    try:
        await stop_event.wait()
    finally:
        server.close()
        await server.wait_closed()
        if args.pidfile:
            remove_pid(args.pidfile)


if __name__ == "__main__":
    asyncio.run(main())
