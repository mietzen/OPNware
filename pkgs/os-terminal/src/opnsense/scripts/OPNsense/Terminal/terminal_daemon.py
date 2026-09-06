#!/usr/bin/env python3
"""
Interactive XTerm.js Host PTY WebSocket Daemon.
Spawns an interactive login shell for the authenticated OPNsense WebUI user.
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
import pwd
import re
import signal
import struct
import sys
import termios
import xml.etree.ElementTree as ET
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
DEFAULT_ROWS = 24
DEFAULT_COLS = 80
READ_CHUNK_SIZE = 4096

SESSION_PATH_PATTERN = re.compile(r"^[a-zA-Z0-9,-]+$")
SHELL_PATTERN = re.compile(r"^(/[a-zA-Z0-9_.-]+)+$")

KNOWN_SHELLS = {
    "csh": "/bin/csh",
    "sh": "/bin/sh",
    "bash": "/usr/local/bin/bash",
    "zsh": "/usr/local/bin/zsh",
}


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


def extract_authenticated_user(cookie_header: str) -> str:
    """Validate active OPNsense PHP session and extract username."""
    if not cookie_header:
        return ""

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
                                # PHP serialized format: (user_name|Username|user|auth_user)|s:<len>:"<username>"
                                m = re.search(
                                    r'(?:user_name|Username|user|auth_user)\|s:\d+:"([^"]+)"',
                                    content,
                                )
                                if m:
                                    return m.group(1)
                        except OSError:
                            pass
    return ""


def resolve_user_shell_from_config(username: str) -> str:
    """Read user's configured Login shell from /conf/config.xml."""
    config_paths = ["/conf/config.xml", "/usr/local/etc/config.xml"]
    for path in config_paths:
        if not os.path.isfile(path):
            continue
        try:
            tree = ET.parse(path)
            root = tree.getroot()
            for user_node in root.findall("./system/user"):
                name_elem = user_node.find("name")
                if name_elem is not None and name_elem.text == username:
                    shell_elem = user_node.find("shell")
                    if shell_elem is not None and shell_elem.text:
                        shell_val = shell_elem.text.strip()
                        if shell_val and os.path.isfile(shell_val) and os.access(shell_val, os.X_OK):
                            return shell_val
        except Exception:
            pass
    return ""


def resolve_shell(username: str, requested_shell: str = "", default_shell_setting: str = "auto") -> str:
    """Resolve effective shell path based on user login shell, settings, and availability."""
    # 1. Configured default shell setting if not 'auto'
    if default_shell_setting and default_shell_setting != "auto":
        candidate = KNOWN_SHELLS.get(default_shell_setting, default_shell_setting)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate

    # 2. User's Login Shell from /conf/config.xml (System: Access: Users)
    xml_shell = resolve_user_shell_from_config(username)
    if xml_shell and os.path.isfile(xml_shell) and os.access(xml_shell, os.X_OK):
        return xml_shell

    # 3. User's system shell from /etc/passwd
    try:
        pw = pwd.getpwnam(username)
        if pw.pw_shell and os.path.isfile(pw.pw_shell) and os.access(pw.pw_shell, os.X_OK):
            if "nologin" not in pw.pw_shell:
                return pw.pw_shell
    except KeyError:
        pass

    # 4. Fallback shell priority
    for candidate in ("/bin/csh", "/bin/sh", "/usr/local/bin/bash", "/usr/local/bin/zsh"):
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate

    return "/bin/sh"


ACTIVE_SESSIONS: dict[str, "HostTerminalSession"] = {}
MAX_SCROLLBACK_BYTES = 256 * 1024


class HostTerminalSession:
    """Manages master PTY and interactive host shell process with background buffering."""

    def __init__(self, username: str, shell_path: str):
        self.username = username
        self.shell_path = shell_path
        self.master_fd: int | None = None
        self.pid: int | None = None
        self.closed = False
        self.history = bytearray()
        self.attached_queues: set[asyncio.Queue] = set()
        self.pty_task: asyncio.Task | None = None

    def start(self):
        """Fork and execute interactive login shell inside PTY."""
        if self.username == "root":
            try:
                pw = pwd.getpwnam("root")
            except KeyError:
                pw = pwd.struct_passwd(("root", "*", 0, 0, "System Administrator", "/root", "/bin/csh"))
            uid = 0
            gid = 0
            home = pw.pw_dir if os.path.isdir(pw.pw_dir) else "/root"
        else:
            try:
                pw = pwd.getpwnam(self.username)
                uid = pw.pw_uid
                gid = pw.pw_gid
                home = pw.pw_dir if os.path.isdir(pw.pw_dir) else "/tmp"
            except KeyError:
                raise PermissionError(f"User '{self.username}' does not have a local system account")

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

            # Prepare environment
            env = {
                "TERM": "xterm-256color",
                "USER": self.username,
                "LOGNAME": self.username,
                "HOME": home,
                "SHELL": self.shell_path,
                "PATH": "/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin",
                "LANG": "en_US.UTF-8",
                "LC_ALL": "en_US.UTF-8",
                "ENV": "/etc/profile",
            }
            os.environ.clear()
            os.environ.update(env)

            # Drop privileges for non-root user (mandatory failure on error)
            if uid != 0:
                try:
                    os.initgroups(self.username, gid)
                    os.setgid(gid)
                    os.setuid(uid)
                    if os.getuid() != uid or os.geteuid() != uid:
                        os._exit(1)
                except Exception:
                    os._exit(1)

            try:
                os.chdir(home)
            except OSError:
                try:
                    os.chdir("/tmp")
                except OSError:
                    pass

            shell_name = os.path.basename(self.shell_path)
            login_arg0 = f"-{shell_name}"
            cmd = [login_arg0]
            try:
                os.execv(self.shell_path, cmd)
            except Exception:
                try:
                    os.execv("/bin/sh", ["-sh"])
                except Exception:
                    os._exit(1)

        os.close(slave_fd)
        self.pid = pid

        flags = fcntl.fcntl(master_fd, fcntl.F_GETFL)
        fcntl.fcntl(master_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

        self.pty_task = asyncio.create_task(self._pty_reader_loop())

    async def _pty_reader_loop(self):
        """Continuously read PTY output, append to history, and broadcast to attached WebSockets."""
        loop = asyncio.get_running_loop()
        queue = asyncio.Queue()
        master_fd = self.master_fd

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
            while not self.closed:
                chunk = await queue.get()
                if chunk is None:
                    break

                self.history.extend(chunk)
                if len(self.history) > MAX_SCROLLBACK_BYTES:
                    del self.history[: len(self.history) - MAX_SCROLLBACK_BYTES]

                frame = encode_ws_frame(chunk, opcode=OPCODE_BIN)
                for q in list(self.attached_queues):
                    try:
                        q.put_nowait(frame)
                    except (asyncio.QueueFull, Exception):
                        pass
        except (asyncio.CancelledError, Exception):
            pass
        finally:
            try:
                if master_fd is not None:
                    loop.remove_reader(master_fd)
            except (ValueError, OSError):
                pass
            self.close()

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

        for q in list(self.attached_queues):
            try:
                q.put_nowait(None)
            except Exception:
                pass
        self.attached_queues.clear()

        if self.username in ACTIVE_SESSIONS and ACTIVE_SESSIONS[self.username] is self:
            del ACTIVE_SESSIONS[self.username]

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


async def ws_writer_loop(writer: asyncio.StreamWriter, send_queue: asyncio.Queue):
    """Drain frames from send_queue and transmit to client."""
    try:
        while True:
            frame = await send_queue.get()
            if frame is None:
                break
            writer.write(frame)
            await writer.drain()
    except (asyncio.CancelledError, Exception):
        pass


async def handle_ws_input(session: HostTerminalSession, reader: asyncio.StreamReader, send_queue: asyncio.Queue):
    """Read WebSocket frames from browser and write to PTY."""
    while not session.closed:
        opcode, data = await parse_ws_frame(reader)
        if opcode is None or opcode == OPCODE_CLOSE:
            break
        elif opcode == OPCODE_PING:
            try:
                send_queue.put_nowait(encode_ws_frame(data, opcode=OPCODE_PONG))
            except Exception:
                break
        elif opcode in (OPCODE_TEXT, OPCODE_BIN):
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
            elif data.startswith(b"\x00{") and b"ping" in data:
                try:
                    send_queue.put_nowait(encode_ws_frame(b"\x00{\"type\":\"pong\"}", opcode=OPCODE_TEXT))
                    continue
                except Exception:
                    break
            session.write(data)


def create_ws_handler(default_shell_setting: str):
    """Create connection handler with persistent session management."""
    async def handle_ws_conn(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
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

        cookie_header = headers.get("cookie", "")
        username = extract_authenticated_user(cookie_header)
        if not username:
            writer.write(b"HTTP/1.1 401 Unauthorized\r\n\r\n")
            await writer.drain()
            writer.close()
            return

        parsed_url = urlparse(path_line.split(" ")[1] if len(path_line.split(" ")) > 1 else "")
        params = parse_qs(parsed_url.query)
        reset_requested = params.get("reset", ["0"])[0] == "1"

        shell_path = resolve_shell(username, default_shell_setting=default_shell_setting)

        session = ACTIVE_SESSIONS.get(username)
        if reset_requested or session is None or session.closed or session.shell_path != shell_path:
            if session and not session.closed:
                session.close()
            session = HostTerminalSession(username, shell_path)
            try:
                session.start()
                ACTIVE_SESSIONS[username] = session
            except Exception as e:
                err_msg = f"\r\n\x1b[31mFailed to start terminal session for '{username}': {e}\x1b[0m\r\n"
                try:
                    writer.write(encode_ws_frame(err_msg.encode("utf-8"), opcode=OPCODE_TEXT))
                    await writer.drain()
                except Exception:
                    pass
                session.close()
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

        send_queue: asyncio.Queue = asyncio.Queue(maxsize=1024)
        writer_task = asyncio.create_task(ws_writer_loop(writer, send_queue))

        # Replay scrollback buffer so terminal output is preserved
        if session.history:
            try:
                send_queue.put_nowait(encode_ws_frame(bytes(session.history), opcode=OPCODE_BIN))
            except Exception:
                pass

        session.attached_queues.add(send_queue)

        ws_task = asyncio.create_task(handle_ws_input(session, reader, send_queue))
        try:
            done, pending = await asyncio.wait(
                [ws_task, writer_task],
                return_when=asyncio.FIRST_COMPLETED
            )
            for t in pending:
                t.cancel()
        finally:
            session.attached_queues.discard(send_queue)
            try:
                send_queue.put_nowait(encode_ws_frame(b"", opcode=OPCODE_CLOSE))
            except Exception:
                pass
            try:
                send_queue.put_nowait(None)
            except Exception:
                pass
            try:
                await asyncio.wait_for(writer_task, timeout=1.0)
            except Exception:
                writer_task.cancel()
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

    return handle_ws_conn


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
    parser = argparse.ArgumentParser(description="OPNware Web Terminal Host PTY WebSocket Daemon")
    parser.add_argument("--host", default=DEFAULT_HOST, help="Bind host")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Bind port")
    parser.add_argument("--default-shell", default="auto", help="Default shell setting")
    parser.add_argument("--pidfile", default=None, help="PID file path")
    args = parser.parse_args()

    if args.pidfile:
        write_pid(args.pidfile)

    handler = create_ws_handler(args.default_shell)
    server = await asyncio.start_server(handler, args.host, args.port)

    loop = asyncio.get_running_loop()
    stop_event = asyncio.Event()

    def on_signal():
        stop_event.set()

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, on_signal)

    print(f"Web Terminal Daemon listening on {args.host}:{args.port} (PID {os.getpid()})")

    try:
        await stop_event.wait()
    finally:
        server.close()
        await server.wait_closed()
        if args.pidfile:
            remove_pid(args.pidfile)


if __name__ == "__main__":
    asyncio.run(main())
