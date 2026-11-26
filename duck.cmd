: << 'DUCK_POLYGLOT'
@echo off & (where pythonw >nul 2>&1 && start "" pythonw -c "import sys; exec(compile(open(sys.argv[1], encoding='utf-8').read().split('#!PYTHON_' + 'START', 1)[1], sys.argv[1], 'exec'))" "%~f0" %* || start "" python -c "import sys; exec(compile(open(sys.argv[1], encoding='utf-8').read().split('#!PYTHON_' + 'START', 1)[1], sys.argv[1], 'exec'))" "%~f0" %*) & exit /b
DUCK_POLYGLOT
command -v python3 >/dev/null 2>&1 && exec python3 -c "import sys; exec(compile(open(sys.argv[1], encoding='utf-8').read().split('#!PYTHON_' + 'START', 1)[1], sys.argv[1], 'exec'))" "$0" "$@" || exec python -c "import sys; exec(compile(open(sys.argv[1], encoding='utf-8').read().split('#!PYTHON_' + 'START', 1)[1], sys.argv[1], 'exec'))" "$0" "$@"
#!PYTHON_START
# -*- coding: utf-8 -*-
"""
DUCK - Cross-Platform Single-File Intranet Communication, Unrestricted File Sharing & Multi-Protocol Remote Control Hub.
Works on Windows, Linux (Debian, Kali, Ubuntu, etc.), and macOS with one click / one command.
"""

import base64
import ctypes
import ftplib
import hashlib
import html
import http.server
import io
import json
import mimetypes
import os
import platform
import queue
import re
import secrets
import shutil
import socket
import socketserver
import struct
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
import uuid
import webbrowser
import zipfile
import zlib
from datetime import datetime
from pathlib import Path

try:
    import paramiko
    HAS_PARAMIKO = True
except ImportError:
    HAS_PARAMIKO = False

try:
    import tkinter as tk
    from tkinter import ttk, scrolledtext, messagebox
    HAS_TK = True
except ImportError:
    HAS_TK = False

APP_NAME = "Duck"
APP_VERSION = "1.6.1"

def _resolve_script_path():
    try:
        return Path(os.path.abspath(__file__))
    except NameError:
        # The polyglot launcher runs this file as `python -c "exec(...)" <duck.cmd>`,
        # where __file__ is undefined; the real path then lands in sys.argv[1..].
        for a in sys.argv:
            if a and a.lower().endswith("duck.cmd"):
                return Path(os.path.abspath(a))
        return Path("duck.cmd").resolve()

SCRIPT_PATH = _resolve_script_path()
GITHUB_REPO = os.environ.get("DUCK_GITHUB_REPO", "Digi-Worm/duck-hub")
if os.name == "nt":
    DATA_DIR = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "DuckHub"
else:
    DATA_DIR = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share")) / "DuckHub"
FILES_DIR = DATA_DIR / "files"
CHAT_FILE = DATA_DIR / "chat.json"
CLIPBOARD_FILE = DATA_DIR / "clipboard.txt"
CONFIG_FILE = DATA_DIR / "config.json"

try:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    FILES_DIR.mkdir(parents=True, exist_ok=True)
except PermissionError:
    import tempfile
    DATA_DIR = Path(tempfile.gettempdir()) / "DuckHub"
    FILES_DIR = DATA_DIR / "files"
    CHAT_FILE = DATA_DIR / "chat.json"
    CLIPBOARD_FILE = DATA_DIR / "clipboard.txt"
    CONFIG_FILE = DATA_DIR / "config.json"
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    FILES_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# System & Network Helpers
# ---------------------------------------------------------------------------

def get_lan_ips():
    """Return list of local IPv4 addresses, prioritizing primary LAN IP."""
    ips = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0.5)
        s.connect(("192.168.0.1", 80))
        primary = s.getsockname()[0]
        s.close()
        if primary and not primary.startswith("127."):
            ips.append(primary)
    except Exception:
        pass
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET):
            ip = info[4][0]
            if ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        pass
    if not ips:
        ips.append("127.0.0.1")
    return ips


def get_primary_ip():
    return get_lan_ips()[0]


def is_admin():
    if os.name != "nt":
        return os.geteuid() == 0
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def _hosts_file_path():
    if os.name == "nt":
        return Path(r"C:\Windows\System32\drivers\etc\hosts")
    return Path("/etc/hosts")


def check_duck_hosts_configured():
    """Check if 'duck' is mapped in OS hosts file."""
    hosts_path = _hosts_file_path()
    try:
        content = hosts_path.read_text(encoding="utf-8", errors="ignore")
        for line in content.splitlines():
            line = line.split("#", 1)[0].strip()
            parts = line.split()
            if len(parts) >= 2 and "duck" in [p.lower() for p in parts[1:]]:
                return True
    except Exception:
        pass
    return False


def register_hosts_and_firewall():
    """Configure hosts file for 'duck' & 'duck.local' and add firewall rules (requires Admin/root)."""
    hosts_path = _hosts_file_path()
    try:
        content = hosts_path.read_text(encoding="utf-8", errors="ignore")
        lines = content.splitlines()
        new_lines = [l for l in lines if "duck" not in l.lower().split("#")[0].split()]
        new_lines.append("127.0.0.1 duck duck.local # Duck Intranet Hub")
        hosts_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")

        if os.name == "nt":
            cmds = [
                'netsh advfirewall firewall delete rule name="Duck Intranet Hub" >nul 2>&1',
                'netsh advfirewall firewall add rule name="Duck Intranet Hub" dir=in action=allow protocol=TCP localport=80,8080',
                'netsh advfirewall firewall add rule name="Duck Intranet Discovery" dir=in action=allow protocol=UDP localport=137,5353,5355,45454',
            ]
            for c in cmds:
                subprocess.run(["cmd", "/c", c], creationflags=0x08000000)
        else:
            if shutil.which("ufw"):
                for rule in ("80/tcp", "8080/tcp", "137/udp", "5353/udp", "5355/udp", "45454/udp"):
                    subprocess.run(["ufw", "allow", rule], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True, "Registered 'duck' in hosts and configured firewall rules."
    except Exception as e:
        return False, str(e)


def elevate_register_hosts():
    """Trigger OS elevation (UAC on Windows, pkexec on Linux) to run --register-hosts."""
    script_path = str(SCRIPT_PATH)
    if os.name == "nt":
        params = f'-c "import sys; exec(compile(open(sys.argv[1], encoding=\'utf-8\').read().split(\'#!PYTHON_START\', 1)[1], sys.argv[1], \'exec\'))" "{script_path}" --register-hosts'
        rc = ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, params, None, 0)
        return rc > 32
    if shutil.which("pkexec"):
        subprocess.Popen(["pkexec", sys.executable, "-c", "import sys; exec(compile(open(sys.argv[1], encoding='utf-8').read().split('#!PYTHON_START', 1)[1], sys.argv[1], 'exec'))", script_path, "--register-hosts"])
        return True
    return False


# ---------------------------------------------------------------------------
# Pure-Python Windows Screen Capture (PNG via ctypes + zlib) & Input Control
# ---------------------------------------------------------------------------

if os.name == "nt":
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", ctypes.c_uint32),
        ("biWidth", ctypes.c_int32),
        ("biHeight", ctypes.c_int32),
        ("biPlanes", ctypes.c_uint16),
        ("biBitCount", ctypes.c_uint16),
        ("biCompression", ctypes.c_uint32),
        ("biSizeImage", ctypes.c_uint32),
        ("biXPelsPerMeter", ctypes.c_int32),
        ("biYPelsPerMeter", ctypes.c_int32),
        ("biClrUsed", ctypes.c_uint32),
        ("biClrImportant", ctypes.c_uint32),
    ]


def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    chunk = chunk_type + data
    return struct.pack("!I", len(data)) + chunk + struct.pack("!I", zlib.crc32(chunk) & 0xFFFFFFFF)


def capture_screen_png(scale: float = 0.6) -> bytes:
    """Capture primary screen on Windows, Linux (Debian/Kali/X11/Wayland), or macOS as PNG."""
    if os.name != "nt":
        import tempfile
        tmp = os.path.join(tempfile.gettempdir(), f"duck_scr_{threading.get_ident()}.png")
        try:
            if sys.platform == "darwin" and shutil.which("screencapture"):
                subprocess.run(["screencapture", "-x", tmp], timeout=5)
            elif shutil.which("scrot"):
                subprocess.run(["scrot", "-o", tmp], timeout=5)
            elif shutil.which("grim"):
                subprocess.run(["grim", tmp], timeout=5)
            elif shutil.which("import"):
                subprocess.run(["import", "-window", "root", tmp], timeout=5)
            elif shutil.which("gnome-screenshot"):
                subprocess.run(["gnome-screenshot", "-f", tmp], timeout=5)
            if os.path.exists(tmp):
                with open(tmp, "rb") as f:
                    data = f.read()
                os.remove(tmp)
                return data
        except Exception:
            pass
        return b""
    user32 = ctypes.windll.user32
    gdi32 = ctypes.windll.gdi32

    sw = user32.GetSystemMetrics(0)
    sh = user32.GetSystemMetrics(1)
    dw = max(320, int(sw * scale))
    dh = max(200, int(sh * scale))

    hwnd_dc = user32.GetDC(0)
    mem_dc = gdi32.CreateCompatibleDC(hwnd_dc)
    bmp = gdi32.CreateCompatibleBitmap(hwnd_dc, dw, dh)
    old_bmp = gdi32.SelectObject(mem_dc, bmp)

    gdi32.SetStretchBltMode(mem_dc, 3)  # COLORONCOLOR
    gdi32.StretchBlt(mem_dc, 0, 0, dw, dh, hwnd_dc, 0, 0, sw, sh, 0x00CC0020)

    bmi = BITMAPINFOHEADER()
    bmi.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bmi.biWidth = dw
    bmi.biHeight = -dh  # top-down
    bmi.biPlanes = 1
    bmi.biBitCount = 24
    bmi.biCompression = 0  # BI_RGB

    stride = ((dw * 3 + 3) & ~3)
    buf = ctypes.create_string_buffer(stride * dh)
    gdi32.GetDIBits(mem_dc, bmp, 0, dh, buf, ctypes.byref(bmi), 0)

    gdi32.SelectObject(mem_dc, old_bmp)
    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mem_dc)
    user32.ReleaseDC(0, hwnd_dc)

    raw = buf.raw
    # Convert BGR -> RGB scanlines with PNG filter byte 0
    rows = bytearray()
    row_bytes = dw * 3
    for y in range(dh):
        off = y * stride
        row = bytearray(raw[off:off + row_bytes])
        # swap B and R in-place
        row[0::3], row[2::3] = row[2::3], row[0::3]
        rows.append(0)
        rows.extend(row)

    compressed = zlib.compress(bytes(rows), level=1)
    ihdr = struct.pack("!IIBBBBB", dw, dh, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"IDAT", compressed)
        + _png_chunk(b"IEND", b"")
    )


def _linux_xdotool_input(payload: dict):
    """Execute mouse/keyboard input on Linux/Debian/Kali via xdotool if available."""
    if not shutil.which("xdotool"):
        return
    kind = payload.get("kind")
    try:
        if kind in ("move", "click", "dblclick", "rclick", "mousedown", "mouseup"):
            out = subprocess.check_output(["xdotool", "getdisplaygeometry"], text=True, timeout=2).strip().split()
            sw, sh = int(out[0]), int(out[1])
            ax = max(0, min(sw - 1, int(float(payload.get("x", 0.5)) * sw)))
            ay = max(0, min(sh - 1, int(float(payload.get("y", 0.5)) * sh)))
            subprocess.run(["xdotool", "mousemove", str(ax), str(ay)], timeout=2)
            if kind == "click":
                subprocess.run(["xdotool", "click", "1"], timeout=2)
            elif kind == "dblclick":
                subprocess.run(["xdotool", "click", "--repeat", "2", "1"], timeout=2)
            elif kind == "rclick":
                subprocess.run(["xdotool", "click", "3"], timeout=2)
            elif kind == "mousedown":
                subprocess.run(["xdotool", "mousedown", "1"], timeout=2)
            elif kind == "mouseup":
                subprocess.run(["xdotool", "mouseup", "1"], timeout=2)
        elif kind == "wheel":
            btn = "4" if int(payload.get("delta", 0)) > 0 else "5"
            subprocess.run(["xdotool", "click", btn], timeout=2)
        elif kind == "text":
            subprocess.run(["xdotool", "type", "--clearmodifiers", str(payload.get("text", ""))], timeout=3)
        elif kind == "key":
            kmap = {"Enter": "Return", "Backspace": "BackSpace", "Escape": "Escape", "Win": "Super_L", "ALT_TAB": "Alt+Tab", "WIN_D": "Super_L+d"}
            key = kmap.get(payload.get("key", ""), payload.get("key", ""))
            if key:
                subprocess.run(["xdotool", "key", key], timeout=2)
    except Exception:
        pass


def send_remote_input(payload: dict):
    """Execute mouse or keyboard input on host (Windows ctypes or Linux xdotool)."""
    if os.name != "nt":
        _linux_xdotool_input(payload)
        return
    user32 = ctypes.windll.user32
    sw = user32.GetSystemMetrics(0)
    sh = user32.GetSystemMetrics(1)
    kind = payload.get("kind")

    if kind in ("move", "click", "dblclick", "rclick", "mousedown", "mouseup"):
        nx = float(payload.get("x", 0.5))
        ny = float(payload.get("y", 0.5))
        ax = max(0, min(sw - 1, int(nx * sw)))
        ay = max(0, min(sh - 1, int(ny * sh)))
        user32.SetCursorPos(ax, ay)
        if kind == "click":
            user32.mouse_event(0x0002, 0, 0, 0, 0)
            user32.mouse_event(0x0004, 0, 0, 0, 0)
        elif kind == "dblclick":
            for _ in range(2):
                user32.mouse_event(0x0002, 0, 0, 0, 0)
                user32.mouse_event(0x0004, 0, 0, 0, 0)
                time.sleep(0.05)
        elif kind == "rclick":
            user32.mouse_event(0x0008, 0, 0, 0, 0)
            user32.mouse_event(0x0010, 0, 0, 0, 0)
        elif kind == "mousedown":
            user32.mouse_event(0x0002, 0, 0, 0, 0)
        elif kind == "mouseup":
            user32.mouse_event(0x0004, 0, 0, 0, 0)
    elif kind == "wheel":
        delta = int(payload.get("delta", 0))
        user32.mouse_event(0x0800, 0, 0, delta, 0)
    elif kind == "text":
        text = str(payload.get("text", ""))
        for ch in text:
            if ch == "\n":
                user32.keybd_event(0x0D, 0, 0, 0)
                user32.keybd_event(0x0D, 0, 2, 0)
            else:
                vk = user32.VkKeyScanW(ord(ch))
                if vk != -1:
                    shift = (vk >> 8) & 1
                    code = vk & 0xFF
                    if shift:
                        user32.keybd_event(0x10, 0, 0, 0)
                    user32.keybd_event(code, 0, 0, 0)
                    user32.keybd_event(code, 0, 2, 0)
                    if shift:
                        user32.keybd_event(0x10, 0, 2, 0)
    elif kind == "key":
        vk_map = {
            "Enter": 0x0D, "Backspace": 0x08, "Tab": 0x09, "Escape": 0x1B,
            "Space": 0x20, "ArrowLeft": 0x25, "ArrowUp": 0x26,
            "ArrowRight": 0x27, "ArrowDown": 0x28, "Delete": 0x2E,
            "Home": 0x24, "End": 0x23, "PageUp": 0x21, "PageDown": 0x22,
            "Win": 0x5B, "F1": 0x70, "F2": 0x71, "F3": 0x72, "F4": 0x73,
            "F5": 0x74, "F11": 0x7A, "F12": 0x7B,
        }
        key = payload.get("key", "")
        if key == "CTRL_ALT_DEL":
            subprocess.Popen(["taskmgr"], creationflags=0x08000000)
            return
        if key == "ALT_TAB":
            user32.keybd_event(0x12, 0, 0, 0)
            user32.keybd_event(0x09, 0, 0, 0)
            user32.keybd_event(0x09, 0, 2, 0)
            user32.keybd_event(0x12, 0, 2, 0)
            return
        if key == "WIN_D":
            user32.keybd_event(0x5B, 0, 0, 0)
            user32.keybd_event(0x44, 0, 0, 0)
            user32.keybd_event(0x44, 0, 2, 0)
            user32.keybd_event(0x5B, 0, 2, 0)
            return
        vk = vk_map.get(key)
        if vk:
            user32.keybd_event(vk, 0, 0, 0)
            user32.keybd_event(vk, 0, 2, 0)


# ---------------------------------------------------------------------------
# Intranet Name Resolution: mDNS (5353), LLMNR (5355), NBNS (137), Peer Beacon
# ---------------------------------------------------------------------------

def _parse_dns_name(data: bytes, offset: int):
    labels = []
    jumped = False
    orig_offset = offset
    while offset < len(data):
        length = data[offset]
        if length == 0:
            offset += 1
            break
        if (length & 0xC0) == 0xC0:
            if not jumped:
                orig_offset = offset + 2
            pointer = ((length & 0x3F) << 8) | data[offset + 1]
            offset = pointer
            jumped = True
        else:
            offset += 1
            labels.append(data[offset:offset + length].decode("utf-8", errors="ignore"))
            offset += length
    return ".".join(labels), (orig_offset if jumped else offset)


def _encode_dns_name(name: str) -> bytes:
    out = bytearray()
    for part in name.strip(".").split("."):
        b = part.encode("utf-8")
        out.append(len(b))
        out.extend(b)
    out.append(0)
    return bytes(out)


class IntranetDiscovery:
    """Runs mDNS, LLMNR, NBNS responders for 'duck' and Duck Peer Discovery."""

    def __init__(self, log_fn, get_port_fn):
        self.log = log_fn
        self.get_port = get_port_fn
        self.running = False
        self.peers = {}  # ip -> dict
        self.lock = threading.Lock()

    def start(self):
        self.running = True
        for target in (self._mdns_loop, self._llmnr_loop, self._nbns_loop, self._peer_beacon_loop, self._peer_listen_loop):
            t = threading.Thread(target=target, daemon=True)
            t.start()

    def stop(self):
        self.running = False

    def _build_dns_a_response(self, txid: int, qname: str, ip: str, flags: int = 0x8400, ttl: int = 120) -> bytes:
        header = struct.pack("!HHHHHH", txid, flags, 0, 1, 0, 0)
        name_bytes = _encode_dns_name(qname)
        rdata = socket.inet_aton(ip)
        answer = name_bytes + struct.pack("!HHIH", 1, 1, ttl, 4) + rdata
        return header + answer

    def _mdns_loop(self):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("", 5353))
            mreq = struct.pack("4sl", socket.inet_aton("224.0.0.251"), socket.INADDR_ANY)
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
            sock.settimeout(1.0)
            self.log("mDNS responder active (duck.local -> LAN IP)")
        except Exception as e:
            self.log(f"mDNS bind skipped: {e}")
            return

        while self.running:
            try:
                data, addr = sock.recvfrom(4096)
                if len(data) < 12:
                    continue
                txid, flags, qdcount = struct.unpack("!HHH", data[:6])
                if (flags & 0x8000) != 0 or qdcount == 0:
                    continue
                qname, off = _parse_dns_name(data, 12)
                if off + 4 > len(data):
                    continue
                qtype, qclass = struct.unpack("!HH", data[off:off + 4])
                ql = qname.lower().rstrip(".")
                if ql in ("duck", "duck.local") and qtype in (1, 255):
                    ip = get_primary_ip()
                    resp = self._build_dns_a_response(txid, qname, ip, flags=0x8400, ttl=120)
                    sock.sendto(resp, ("224.0.0.251", 5353))
            except socket.timeout:
                continue
            except Exception:
                continue

    def _llmnr_loop(self):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("", 5355))
            mreq = struct.pack("4sl", socket.inet_aton("224.0.0.252"), socket.INADDR_ANY)
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
            sock.settimeout(1.0)
            self.log("LLMNR responder active (duck -> LAN IP)")
        except Exception as e:
            self.log(f"LLMNR bind skipped: {e}")
            return

        while self.running:
            try:
                data, addr = sock.recvfrom(4096)
                if len(data) < 12:
                    continue
                txid, flags, qdcount = struct.unpack("!HHH", data[:6])
                if (flags & 0x8000) != 0 or qdcount == 0:
                    continue
                qname, off = _parse_dns_name(data, 12)
                if off + 4 > len(data):
                    continue
                qtype, _ = struct.unpack("!HH", data[off:off + 4])
                if qname.lower().rstrip(".") == "duck" and qtype in (1, 255):
                    ip = get_primary_ip()
                    resp = self._build_dns_a_response(txid, qname, ip, flags=0x8000, ttl=30)
                    sock.sendto(resp, addr)
            except socket.timeout:
                continue
            except Exception:
                continue

    def _nbns_loop(self):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("", 137))
            sock.settimeout(1.0)
            self.log("NetBIOS Name Service active (DUCK -> LAN IP)")
        except Exception as e:
            self.log(f"NBNS (UDP 137) skipped: {e}")
            return

        while self.running:
            try:
                data, addr = sock.recvfrom(1024)
                if len(data) < 50:
                    continue
                txid, flags, qdcount = struct.unpack("!HHH", data[:6])
                if (flags & 0x8000) != 0 or qdcount == 0:
                    continue
                # Decode NetBIOS first-level encoded name (32 bytes starting at index 13)
                if data[12] != 32:
                    continue
                enc = data[13:45]
                decoded = []
                for i in range(0, 32, 2):
                    c = ((enc[i] - 0x41) << 4) | (enc[i + 1] - 0x41)
                    decoded.append(chr(c))
                nb_name = "".join(decoded[:15]).strip().upper()
                if nb_name == "DUCK":
                    ip = get_primary_ip()
                    header = struct.pack("!HHHHHH", txid, 0x8500, 0, 1, 0, 0)
                    name_field = data[12:46]
                    rdata = struct.pack("!H", 0x0000) + socket.inet_aton(ip)
                    answer = name_field + struct.pack("!HHIH", 0x0020, 0x0001, 120, 6) + rdata
                    sock.sendto(header + answer, addr)
            except socket.timeout:
                continue
            except Exception:
                continue

    def _peer_beacon_loop(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        while self.running:
            try:
                payload = json.dumps({
                    "app": "duck",
                    "host": socket.gethostname(),
                    "os": platform.system(),
                    "ip": get_primary_ip(),
                    "port": self.get_port(),
                    "ts": time.time(),
                }).encode("utf-8")
                sock.sendto(payload, ("255.255.255.255", 45454))
            except Exception:
                pass
            time.sleep(5)

    def _peer_listen_loop(self):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("", 45454))
            sock.settimeout(1.0)
        except Exception:
            return
        while self.running:
            try:
                data, addr = sock.recvfrom(2048)
                info = json.loads(data.decode("utf-8", errors="ignore"))
                if info.get("app") == "duck":
                    ip = addr[0]
                    info["ip"] = ip
                    info["last_seen"] = time.time()
                    with self.lock:
                        self.peers[ip] = info
            except socket.timeout:
                continue
            except Exception:
                continue

    def get_peers(self):
        now = time.time()
        with self.lock:
            self.peers = {k: v for k, v in self.peers.items() if now - v.get("last_seen", 0) < 20}
            return list(self.peers.values())


# ---------------------------------------------------------------------------
# WebSocket Server Helper (RFC 6455 Pure Python)
# ---------------------------------------------------------------------------

WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


_HOSTNAME_CACHE = {}
_HOSTNAME_CACHE_LOCK = threading.Lock()


def _nbns_query_name(ip: str, timeout: float = 0.35) -> str:
    """Query NetBIOS Node Status (UDP 137) for the device's real Windows/Samba name."""
    txid = secrets.randbits(16)
    pkt = struct.pack("!HHHHHH", txid, 0x0000, 1, 0, 0, 0)
    pkt += _encode_dns_name("CKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    pkt += struct.pack("!HH", 0x0021, 0x0001)  # NBSTAT, IN
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.settimeout(timeout)
        s.sendto(pkt, (ip, 137))
        data, _ = s.recvfrom(1024)
        # Skip 12-byte header + encoded name + type/class/ttl/rdlen
        idx = 12
        while idx < len(data) and data[idx] != 0:
            idx += 1 + data[idx]
        idx += 1 + 10  # null + type(2) + class(2) + ttl(4) + rdlen(2)
        if idx >= len(data):
            return ""
        num_names = data[idx]
        idx += 1
        for _ in range(num_names):
            if idx + 18 > len(data):
                break
            raw_name = data[idx:idx + 15].decode("ascii", errors="ignore").strip()
            name_type = data[idx + 15]
            flags = struct.unpack("!H", data[idx + 16:idx + 18])[0]
            idx += 18
            is_group = bool(flags & 0x8000)
            if name_type == 0x00 and not is_group and raw_name and not raw_name.startswith("__"):
                return raw_name
    except Exception:
        pass
    finally:
        s.close()
    return ""


def _mdns_ptr_query(ip: str, timeout: float = 0.35) -> str:
    """Query mDNS (224.0.0.251:5353) reverse PTR for .local hostnames (macOS/iOS/Android/Linux)."""
    parts = ip.split(".")
    if len(parts) != 4:
        return ""
    rev_name = ".".join(reversed(parts)) + ".in-addr.arpa"
    txid = secrets.randbits(16)
    pkt = struct.pack("!HHHHHH", txid, 0x0000, 1, 0, 0, 0) + _encode_dns_name(rev_name) + struct.pack("!HH", 12, 1)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.settimeout(timeout)
        s.sendto(pkt, ("224.0.0.251", 5353))
        deadline = time.time() + timeout
        while time.time() < deadline:
            data, _ = s.recvfrom(1024)
            if len(data) < 12:
                continue
            ancount = struct.unpack("!H", data[6:8])[0]
            if ancount == 0:
                continue
            _, off = _parse_dns_name(data, 12)
            off += 4  # qtype + qclass
            for _ in range(ancount):
                if off >= len(data):
                    break
                _, off = _parse_dns_name(data, off)
                if off + 10 > len(data):
                    break
                rtype, _, _, rdlen = struct.unpack("!HHIH", data[off:off + 10])
                off += 10
                if rtype == 12 and off + rdlen <= len(data):  # PTR
                    target, _ = _parse_dns_name(data, off)
                    if target:
                        return target.split(".")[0]
                off += rdlen
    except Exception:
        pass
    finally:
        s.close()
    return ""


def resolve_hostname(ip):
    """Resolve real hostname for a LAN IP via rDNS, NetBIOS (UDP 137), and mDNS PTR."""
    if not ip:
        return ""
    if ip in ("127.0.0.1", "::1") or ip == get_primary_ip():
        return socket.gethostname()
    now = time.time()
    with _HOSTNAME_CACHE_LOCK:
        cached = _HOSTNAME_CACHE.get(ip)
        if cached and now - cached[1] < 60:
            return cached[0]

    name = ""
    try:
        rdns = socket.gethostbyaddr(ip)[0].split(".")[0]
        if rdns and rdns != ip:
            name = rdns
    except Exception:
        pass
    if not name:
        name = _nbns_query_name(ip)
    if not name:
        name = _mdns_ptr_query(ip)

    with _HOSTNAME_CACHE_LOCK:
        _HOSTNAME_CACHE[ip] = (name, now)
    return name


class WebSocketClient:
    def __init__(self, sock, addr, client_id, name, ip):
        self.sock = sock
        self.addr = addr
        self.id = client_id
        self.name = name
        self.ip = ip
        self.send_lock = threading.Lock()
        self.closed = False
        self.tcp_bridge = None
        self.ssh_client = None
        self.ssh_chan = None
        self.term_proc = None

    def send_frame(self, payload: bytes, opcode: int = 0x1):
        if self.closed:
            return
        header = bytearray([0x80 | opcode])
        length = len(payload)
        if length < 126:
            header.append(length)
        elif length < 65536:
            header.append(126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(127)
            header.extend(struct.pack("!Q", length))
        with self.send_lock:
            try:
                self.sock.sendall(bytes(header) + payload)
            except Exception:
                self.closed = True

    def send_json(self, obj: dict):
        self.send_frame(json.dumps(obj).encode("utf-8"), opcode=0x1)

    def recv_frame(self):
        def read_exact(n):
            buf = bytearray()
            while len(buf) < n:
                chunk = self.sock.recv(n - len(buf))
                if not chunk:
                    raise EOFError("WebSocket closed")
                buf.extend(chunk)
            return bytes(buf)

        b1, b2 = read_exact(2)
        opcode = b1 & 0x0F
        masked = (b2 & 0x80) != 0
        length = b2 & 0x7F
        if length == 126:
            length = struct.unpack("!H", read_exact(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", read_exact(8))[0]
        mask = read_exact(4) if masked else b""
        data = bytearray(read_exact(length))
        if masked:
            for i in range(length):
                data[i] ^= mask[i % 4]
        return opcode, bytes(data)

    def cleanup(self):
        self.closed = True
        for res in (self.tcp_bridge, self.ssh_chan, self.ssh_client):
            if res:
                try:
                    res.close()
                except Exception:
                    pass
        if self.term_proc:
            try:
                self.term_proc.kill()
            except Exception:
                pass


# ---------------------------------------------------------------------------
# Internet Tunnel (Cloudflare Quick Tunnel) & OTP Security Gate
# ---------------------------------------------------------------------------

OTP_GATE_HTML = """<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Duck Hub — OTP Required</title>
<style>
  body{margin:0;height:100vh;display:grid;place-items:center;background:#020617;color:#a5b4fc;font-family:'JetBrains Mono','Fira Code',Consolas,monospace;position:relative;overflow:hidden;}
  body::before{content:'';position:fixed;inset:0;z-index:0;pointer-events:none;
    background-image:linear-gradient(rgba(0,246,255,0.06) 1px,transparent 1px),linear-gradient(90deg,rgba(0,246,255,0.06) 1px,transparent 1px);
    background-size:44px 44px;
    mask-image:radial-gradient(ellipse at 50% 50%,#000 30%,transparent 75%);
    -webkit-mask-image:radial-gradient(ellipse at 50% 50%,#000 30%,transparent 75%);}
  body::after{content:'';position:fixed;inset:0;z-index:1;pointer-events:none;
    background:repeating-linear-gradient(0deg,transparent,transparent 2px,rgba(0,255,136,0.028) 2px,rgba(0,255,136,0.028) 3px);}
  .box{position:relative;z-index:2;background:rgba(15,23,42,0.92);border:1px solid #334155;border-radius:16px;padding:30px;width:350px;text-align:center;
    box-shadow:0 0 40px rgba(0,246,255,0.18),0 24px 60px rgba(0,0,0,0.65);backdrop-filter:blur(10px);}
  .logo{font-size:44px;margin-bottom:10px;filter:drop-shadow(0 0 16px #00f6ff);animation:pulse 2.4s ease-in-out infinite;}
  @keyframes pulse{0%,100%{filter:drop-shadow(0 0 10px #00f6ff)}50%{filter:drop-shadow(0 0 26px #00f6ff)}}
  h2{margin:0 0 6px;font-size:20px;font-weight:800;letter-spacing:0.5px;
    background:linear-gradient(90deg,#06b6d4,#00f6ff);-webkit-background-clip:text;-webkit-text-fill-color:transparent;}
  p{margin:0 0 18px;font-size:12.5px;color:#64748b;line-height:1.5;}
  input{width:100%;padding:13px;border-radius:10px;border:1px solid #334155;background:#020617;color:#00f6ff;font-size:24px;letter-spacing:7px;text-align:center;
    font-weight:700;outline:none;box-sizing:border-box;font-family:inherit;transition:all 0.2s;}
  input::placeholder{color:#334155;}
  input:focus{border-color:#00f6ff;box-shadow:0 0 18px rgba(0,246,255,0.45);}
  button{margin-top:16px;width:100%;padding:12px;border:none;border-radius:10px;background:linear-gradient(135deg,#00f6ff,#06b6d4);color:#020617;
    font-weight:800;font-size:14px;cursor:pointer;font-family:inherit;letter-spacing:0.5px;transition:all 0.2s;
    box-shadow:0 4px 18px rgba(6,182,212,0.4);}
  button:hover{transform:translateY(-2px);box-shadow:0 8px 28px #00f6ff;}
  .err{color:#ef4444;font-size:12px;margin-top:12px;min-height:16px;font-family:inherit;}
</style></head><body>
<div class="box">
  <div class="logo">🦆</div>
  <h2>DUCK ACCESS GATE</h2>
  <p>Enter the 6-digit OTP shown on the host dashboard</p>
  <input id="otp" maxlength="6" placeholder="000000" autofocus onkeydown="if(event.key==='Enter')verify()">
  <button onclick="verify()">UNLOCK DASHBOARD</button>
  <div class="err" id="err"></div>
</div>
<script>
async function verify(){
  const otp = document.getElementById('otp').value.trim();
  const r = await fetch('/api/otp/verify', {method:'POST', body: JSON.stringify({otp})});
  if(r.ok){ location.reload(); } else { document.getElementById('err').textContent = 'Invalid OTP. Check the host dashboard.'; }
}
</script></body></html>"""


class TunnelManager:
    """Manages Cloudflare Quick Tunnel and 6-digit OTP session security."""

    def __init__(self, log_fn, on_update_fn):
        self.log = log_fn
        self.on_update = on_update_fn
        self.active = False
        self.status = "offline"
        self.url = ""
        self.otp = ""
        self.secret = secrets.token_hex(16)
        self.proc = None
        self.error = ""

    def state_dict(self):
        return {
            "active": self.active,
            "status": self.status,
            "url": self.url,
            "otp": self.otp,
            "error": self.error,
        }

    def _new_otp(self):
        self.otp = f"{secrets.randbelow(900000) + 100000}"
        self.secret = secrets.token_hex(16)

    def session_token(self) -> str:
        if not self.otp:
            return ""
        return hashlib.sha256(f"{self.secret}:{self.otp}".encode("utf-8")).hexdigest()[:32]

    def verify_cookie(self, cookie_header: str) -> bool:
        if not self.active or not self.otp:
            return False
        expected = self.session_token()
        for part in (cookie_header or "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == "duck_session" and v == expected:
                return True
        return False

    def rotate_otp(self):
        if self.active:
            self._new_otp()
            self.log(f"Rotated Internet OTP: {self.otp}")
            self.on_update()

    def _ensure_cloudflared(self):
        found = shutil.which("cloudflared")
        if found:
            return found
        bin_dir = DATA_DIR / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        exe_name = "cloudflared.exe" if os.name == "nt" else "cloudflared"
        local_bin = bin_dir / exe_name
        if local_bin.exists() and local_bin.stat().st_size > 1_000_000:
            return str(local_bin)

        arch = platform.machine().lower()
        is_arm = "arm" in arch or "aarch64" in arch
        if os.name == "nt":
            dl_name = "cloudflared-windows-amd64.exe"
        elif sys.platform == "darwin":
            dl_name = "cloudflared-darwin-arm64.tgz" if is_arm else "cloudflared-darwin-amd64.tgz"
        else:
            dl_name = "cloudflared-linux-arm64" if is_arm else "cloudflared-linux-amd64"

        url = f"https://github.com/cloudflare/cloudflared/releases/latest/download/{dl_name}"
        self.status = "downloading"
        self.log(f"Downloading cloudflared ({dl_name})...")
        self.on_update()
        tmp_path = bin_dir / (dl_name + ".tmp")
        urllib.request.urlretrieve(url, tmp_path)
        if dl_name.endswith(".tgz"):
            import tarfile
            with tarfile.open(tmp_path, "r:gz") as tf:
                tf.extract("cloudflared", path=bin_dir)
            tmp_path.unlink(missing_ok=True)
        else:
            tmp_path.replace(local_bin)
        if os.name != "nt":
            os.chmod(local_bin, 0o755)
        return str(local_bin)

    def start(self, port: int):
        if self.active:
            return
        self.active = True
        self.error = ""
        self.url = ""
        self._new_otp()
        self.status = "starting"
        self.on_update()
        threading.Thread(target=self._run_worker, args=(port,), daemon=True).start()

    def _run_worker(self, port: int):
        try:
            cf_bin = self._ensure_cloudflared()
            self.status = "connecting"
            self.on_update()
            kwargs = {"stdout": subprocess.PIPE, "stderr": subprocess.STDOUT, "text": True, "bufsize": 1}
            if os.name == "nt":
                kwargs["creationflags"] = 0x08000000
            self.proc = subprocess.Popen([cf_bin, "tunnel", "--url", f"http://127.0.0.1:{port}", "--no-autoupdate"], **kwargs)
            for line in self.proc.stdout:
                if not self.active:
                    break
                m = re.search(r"https://[a-zA-Z0-9.-]+\.trycloudflare\.com", line)
                if m and not self.url:
                    self.url = m.group(0)
                    self.status = "online"
                    self.log(f"Internet Tunnel LIVE: {self.url} | OTP: {self.otp}")
                    self.on_update()
        except Exception as e:
            self.error = str(e)
            self.status = "error"
            self.active = False
            self.log(f"Tunnel error: {e}")
            self.on_update()

    def stop(self):
        self.active = False
        self.status = "offline"
        self.url = ""
        self.otp = ""
        if self.proc:
            try:
                self.proc.terminate()
            except Exception:
                pass
            self.proc = None
        self.log("Internet Tunnel stopped.")
        self.on_update()


# ---------------------------------------------------------------------------
# Application State
# ---------------------------------------------------------------------------

class DuckState:
    def __init__(self, log_fn):
        self.log = log_fn
        self.port = 80
        self.clients = {}  # client_id -> WebSocketClient
        self.clients_lock = threading.Lock()
        self.chat_lock = threading.Lock()
        self.messages = self._load_chat()
        self.clipboard = self._load_clipboard()
        self.discovery = IntranetDiscovery(log_fn, lambda: self.port)
        self.tunnel = TunnelManager(log_fn, lambda: self.broadcast({"type": "tunnel", "tunnel": self.tunnel.state_dict()}))
        self.latest_update = None

    def check_github_update(self):
        try:
            # Cache-bust the CDN: raw.githubusercontent.com can serve a stale copy for
            # minutes after a push, which made new releases invisible to the updater.
            url = f"https://raw.githubusercontent.com/{GITHUB_REPO}/main/duck.cmd?_={int(time.time())}"
            req = urllib.request.Request(url, headers={
                "User-Agent": "DuckHub-Updater",
                "Cache-Control": "no-cache",
                "Pragma": "no-cache",
            })
            with urllib.request.urlopen(req, timeout=8) as resp:
                head = resp.read(8192).decode("utf-8", errors="ignore")
            m = re.search(r'APP_VERSION\s*=\s*"([^"]+)"', head)
            if not m:
                return {"available": False, "current": APP_VERSION, "repo": GITHUB_REPO,
                        "error": "APP_VERSION not found in remote file"}
            remote_ver = m.group(1)
            cur_t = tuple(int(x) for x in re.findall(r"\d+", APP_VERSION)[:3])
            rem_t = tuple(int(x) for x in re.findall(r"\d+", remote_ver)[:3])
            avail = rem_t > cur_t
            info = {"available": avail, "current": APP_VERSION, "latest": remote_ver, "repo": GITHUB_REPO}
            if avail:
                self.latest_update = info
                self.broadcast({"type": "update_available", "update": info})
            return info
        except Exception as e:
            # Report the real failure instead of silently masquerading as "up to date":
            # a 404 (wrong/renamed repo) and a genuine "no update" used to look identical.
            code = getattr(e, "code", None)
            hint = " (repository not found — check GITHUB_REPO / DUCK_GITHUB_REPO)" if code == 404 else ""
            return {"available": False, "current": APP_VERSION, "repo": GITHUB_REPO,
                    "error": f"{type(e).__name__}: {e}{hint}"}

    def apply_github_update(self):
        # Cache-bust the CDN just like check_github_update, so apply never downloads
        # a stale copy older than the version the check just saw.
        url = f"https://raw.githubusercontent.com/{GITHUB_REPO}/main/duck.cmd?_={int(time.time())}"
        req = urllib.request.Request(url, headers={
            "User-Agent": "DuckHub-Updater",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
        })
        with urllib.request.urlopen(req, timeout=20) as resp:
            new_data = resp.read()
        if b"#!PYTHON_START" not in new_data:
            raise ValueError("Invalid update payload: missing polyglot marker")

        # Validate the download BEFORE touching the live file. A truncated or HTML-error
        # response used to overwrite duck.cmd and brick the app with no way back.
        payload = new_data.split(b"#!PYTHON_START", 1)[1].decode("utf-8", errors="replace")
        try:
            compile(payload, "duck.cmd", "exec")
        except SyntaxError as e:
            raise ValueError(f"Downloaded update failed to compile, aborted: {e}")

        cur_path = SCRIPT_PATH
        bak_path = cur_path.with_suffix(".cmd.bak")
        if cur_path.exists():
            shutil.copy2(cur_path, bak_path)

        # Write to a temp file in the same directory, then atomically replace, so an
        # interrupted write can never leave a half-written duck.cmd behind.
        tmp_path = cur_path.with_suffix(".cmd.new")
        try:
            tmp_path.write_bytes(new_data)
            os.replace(tmp_path, cur_path)
        except Exception:
            try:
                tmp_path.unlink()
            except Exception:
                pass
            raise

        self.log(f"Updated {cur_path.name} from GitHub ({GITHUB_REPO}). Restart Duck to apply.")
        return {"ok": True, "message": "Updated! Restart duck.cmd to run the new version."}

    def _load_chat(self):
        try:
            if CHAT_FILE.exists():
                return json.loads(CHAT_FILE.read_text(encoding="utf-8"))[-500:]
        except Exception:
            pass
        return [{
            "id": str(uuid.uuid4())[:8],
            "sender": "Duck System",
            "ip": get_primary_ip(),
            "channel": "general",
            "text": "Welcome to Duck Intranet Hub! Chat, share any file without restrictions, and control LAN devices.",
            "ts": datetime.now().strftime("%H:%M:%S"),
            "attachments": [],
        }]

    def _save_chat(self):
        try:
            CHAT_FILE.write_text(json.dumps(self.messages[-500:], indent=2), encoding="utf-8")
        except Exception:
            pass

    def _load_clipboard(self):
        try:
            if CLIPBOARD_FILE.exists():
                return CLIPBOARD_FILE.read_text(encoding="utf-8")
        except Exception:
            pass
        return ""

    def set_clipboard(self, text: str, sender: str):
        self.clipboard = text
        try:
            CLIPBOARD_FILE.write_text(text, encoding="utf-8")
        except Exception:
            pass
        self.broadcast({"type": "clipboard", "text": text, "sender": sender})

    def add_message(self, msg: dict):
        with self.chat_lock:
            self.messages.append(msg)
            if len(self.messages) > 500:
                self.messages = self.messages[-500:]
            self._save_chat()
        self.broadcast({"type": "chat", "message": msg})

    def clear_chat(self, sender: str):
        with self.chat_lock:
            self.messages = [{
                "id": str(uuid.uuid4())[:8],
                "sender": "Duck System",
                "ip": get_primary_ip(),
                "channel": "general",
                "text": f"Chat cleared by {sender}.",
                "ts": datetime.now().strftime("%H:%M:%S"),
                "attachments": [],
            }]
            self._save_chat()
        self.broadcast({"type": "chat_cleared", "messages": self.messages})

    def broadcast(self, obj: dict):
        with self.clients_lock:
            dead = []
            for cid, c in self.clients.items():
                if c.closed:
                    dead.append(cid)
                else:
                    c.send_json(obj)
            for cid in dead:
                self.clients.pop(cid, None)

    def broadcast_presence(self):
        with self.clients_lock:
            users = [{"id": c.id, "name": c.name, "ip": c.ip,
                      "hostname": getattr(c, "hostname", "") or c.name,
                      "self": False} for c in self.clients.values() if not c.closed]
        self.broadcast({"type": "presence", "users": users})


# ---------------------------------------------------------------------------
# Embedded Feature-Rich Web Dashboard (HTML + CSS + JS)
# ---------------------------------------------------------------------------

DASHBOARD_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Duck — Intranet Hub</title>
<style>
  :root {
    --bg: #020617;
    --panel: #0f172a;
    --panel2: #1e293b;
    --border: #334155;
    --text: #a5b4fc;
    --muted: #64748b;
    --accent: #06b6d4;
    --accent2: #8b5cf6;
    --green: #10b981;
    --red: #ef4444;
    --neon: #00f6ff;
    --matrix: #059669;
    --holo: rgba(100, 100, 255, 0.15);
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace;
    background: var(--bg);
    color: var(--text);
    height: 100vh;
    display: flex;
    overflow: hidden;
    position: relative;
  }
  body::before {
    content: '';
    position: absolute;
    inset: 0;
    z-index: -2;
    background: linear-gradient(135deg, transparent 45%, var(--holo) 50%), 
                radial-gradient(circle at 50% 50%, rgba(0,255,136,0.04) 0%, transparent 35%),
                #020617;
  }
  body::after {
    content: '';
    position: absolute;
    inset: 0;
    z-index: -1;
    pointer-events: none;
    background: repeating-linear-gradient(
      0deg,
      transparent,
      transparent calc(1px + 0.5px),
      rgba(0,255,136,0.03) calc(1px + 0.5px),
      rgba(0,255,136,0.03) calc(2px + 0.5px)
    );
  }
  .sidebar {
    width: 240px;
    background: var(--panel);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    padding: 16px 12px;
    gap: 8px;
    flex-shrink: 0;
  }
  .brand {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 10px 14px;
    border-bottom: 1px solid var(--border);
    margin-bottom: 6px;
  }
  .brand-logo {
    width: 40px; height: 40px;
    border-radius: 12px;
    background: linear-gradient(45deg, var(--neon), var(--matrix));
    display: grid; place-items: center;
    font-size: 22px; font-weight: 900; color: #020617;
    box-shadow: 0 0 20px var(--neon);
    animation: rot 4s linear infinite;
  }
  @keyframes rot { 0%,100%{transform: rotate(0deg)} 50%{transform: rotate(180deg)} }
  .brand-title {
    font-weight: 800; font-size: 18px; letter-spacing: 0.5px;
    background: linear-gradient(90deg, var(--accent), var(--neon));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  .brand-sub { font-size: 12px; color: var(--green); font-family: monospace; }
  .nav-btn {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 12px; border-radius: 8px;
    background: rgba(255,255,255,0.05); border: 1px solid var(--border);
    color: var(--muted);
    cursor: pointer; font-size: 14px; font-weight: 600;
    transition: all 0.2s; text-align: left;
  }
  .nav-btn:hover { 
    background: var(--accent); color: #020617;
    box-shadow: 0 0 20px var(--accent);
    transform: translateX(2px);
  }
  .nav-btn.active { 
    background: rgba(6,182,212,0.2); 
    border-color: var(--neon); 
    color: var(--accent);
    box-shadow: 0 0 20px var(--neon);
  }
  .sidebar-footer {
    margin-top: auto;
    padding-top: 12px;
    border-top: 1px solid var(--border);
    font-size: 12px;
    color: var(--muted);
    display: flex; flex-direction: column; gap: 6px;
  }
  .nick-input {
    background: var(--bg); border: 1px solid var(--border);
    color: var(--text); padding: 6px 8px; border-radius: 6px;
    font-size: 12px; width: 100%;
  }
  .main {
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .topbar {
    height: 54px;
    background: var(--panel);
    border-bottom: 1px solid var(--border);
    display: flex; align-items: center; justify-content: space-between;
    padding: 0 20px;
    flex-shrink: 0;
  }
  .topbar-info { display: flex; align-items: center; gap: 12px; font-size: 13px; color: var(--muted); }
  .pill {
    background: var(--panel2); border: 1px solid var(--border);
    padding: 4px 10px; border-radius: 999px; font-size: 12px; color: var(--text);
  }
  .pill.online { border-color: rgba(16, 185, 129, 0.4); color: var(--green); }
  .content { flex: 1; overflow: hidden; display: none; }
  .content.active { display: flex; flex-direction: column; }

  /* Chat */
  .chat-wrap { display: flex; flex: 1; overflow: hidden; }
  .chat-main { flex: 1; display: flex; flex-direction: column; overflow: hidden; }
  .chat-messages {
    flex: 1; overflow-y: auto; padding: 18px 22px;
    display: flex; flex-direction: column; gap: 12px;
  }
  .msg {
    background: rgba(15, 23, 42, 0.85); border: 1px solid var(--border);
    padding: 12px 16px; border-radius: 12px; max-width: 78%;
    align-self: flex-start;
    backdrop-filter: blur(10px);
    box-shadow: 0 0 15px rgba(0,0,0,0.4);
  }
  .msg.me { align-self: flex-end; background: rgba(30, 58, 95, 0.9); border-color: var(--neon); box-shadow: 0 0 18px rgba(0,246,255,0.25); }
  .msg-head { display: flex; gap: 10px; align-items: baseline; margin-bottom: 6px; font-size: 12px; }
  .msg-sender { font-weight: 700; color: var(--accent); }
  .msg.me .msg-sender { color: var(--neon); }
  .msg-meta { color: var(--muted); font-size: 11px; }
  .msg-body { font-size: 14px; line-height: 1.45; white-space: pre-wrap; word-break: break-word; }
  .msg-attach {
    margin-top: 8px; padding: 8px 10px; background: var(--bg);
    border: 1px solid var(--border); border-radius: 8px;
    display: flex; align-items: center; justify-content: space-between; gap: 10px; font-size: 12px;
  }
  .msg-attach img { max-width: 280px; max-height: 200px; border-radius: 6px; display: block; margin-top: 4px; }
  .chat-input-bar {
    padding: 12px 18px; background: var(--panel); border-top: 1px solid var(--border);
    display: flex; gap: 10px; align-items: center;
  }
  .chat-input {
    flex: 1; background: var(--bg); border: 1px solid var(--border);
    color: var(--text); padding: 10px 14px; border-radius: 10px;
    font-size: 14px; outline: none;
  }
  .chat-input:focus { border-color: var(--accent); }
  .chat-side {
    width: 260px; background: var(--panel); border-left: 1px solid var(--border);
    padding: 14px; display: flex; flex-direction: column; gap: 14px; overflow-y: auto;
  }
  .card {
    background: var(--panel2); border: 1px solid var(--border);
    border-radius: 12px; padding: 14px;
  }
  .card h3 { font-size: 13px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 10px; }
  .btn {
    background: linear-gradient(135deg, var(--neon), var(--accent)); color: #020617; border: none;
    padding: 10px 16px; border-radius: 8px; font-weight: 700;
    cursor: pointer; font-size: 13px; transition: all 0.2s; position: relative;
    overflow: hidden; font-family: inherit;
    box-shadow: 0 4px 15px rgba(6,182,212,0.35);
  }
  .btn:hover { opacity: 0.95; transform: translateY(-2px); box-shadow: 0 8px 25px var(--neon); }
  .btn:active { transform: translateY(0); }
  .btn::after {
    content: ''; position: absolute; top: 0; left: -100%;
    width: 100%; height: 100%;
    background: linear-gradient(90deg, transparent, rgba(255,255,255,0.35), transparent);
    transition: left 0.5s;
  }
  .btn:hover::after { left: 100%; }
  .btn.secondary { background: var(--panel2); color: var(--text); border: 1px solid var(--border); box-shadow: none; }
  .btn.blue { background: linear-gradient(135deg, var(--accent2), var(--accent)); color: #fff; }
  .btn.danger { background: linear-gradient(135deg, var(--red), #dc2626); color: #fff; }
  .btn.sm { padding: 6px 12px; font-size: 12px; }

  /* Files */
  .pad { padding: 20px; overflow-y: auto; flex: 1; display: flex; flex-direction: column; gap: 16px; }
  .dropzone {
    border: 2px dashed var(--border); border-radius: 14px;
    padding: 32px; text-align: center; background: linear-gradient(135deg, var(--panel), var(--panel2));
    cursor: pointer; transition: all 0.3s;
    box-shadow: 0 0 20px rgba(0,0,0,0.4);
  }
  .dropzone.drag { 
    border-color: var(--neon); 
    background: linear-gradient(135deg, rgba(6,182,212,0.12), var(--panel));
    box-shadow: 0 0 30px var(--neon);
  }
  .file-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 16px; }
  .file-card {
    background: var(--panel); border: 1px solid var(--border);
    border-radius: 12px; padding: 14px; display: flex; flex-direction: column; gap: 8px;
    transition: all 0.2s;
  }
  .file-card:hover { transform: translateY(-3px); box-shadow: 0 8px 30px rgba(6,182,212,0.35); border-color: var(--accent); }
  .file-name { font-weight: 600; font-size: 14px; word-break: break-all; }
  .file-meta { font-size: 12px; color: var(--muted); font-family: monospace; }
  .file-actions { display: flex; gap: 8px; flex-wrap: wrap; margin-top: auto; }
  .progress-wrap { height: 6px; background: var(--bg); border-radius: 4px; overflow: hidden; display: none; margin-top: 10px; }
  .progress-bar { height: 100%; background: linear-gradient(90deg, var(--neon), var(--green)); width: 0%; transition: width 0.3s; }

  /* Remote Desktop */
  .rd-toolbar {
    padding: 10px 18px; background: var(--panel); border-bottom: 1px solid var(--border);
    display: flex; gap: 10px; align-items: center; flex-wrap: wrap;
  }
  .rd-stage {
    flex: 1; background: #05070c; display: grid; place-items: center;
    overflow: auto; padding: 10px; position: relative;
  }
  #screenImg {
    max-width: 100%; max-height: 100%; border: 1px solid var(--border);
    border-radius: 6px; cursor: crosshair; user-select: none;
  }

  /* Terminal & Protocols */
  .term-out {
    flex: 1; background: #0a0f1c; border: 1px solid var(--border);
    border-radius: 10px; padding: 14px; font-family: 'JetBrains Mono', 'Fira Code', Consolas, monospace;
    font-size: 13px; color: #00ff88; overflow-y: auto; white-space: pre-wrap;
    min-height: 260px;
    box-shadow: 0 0 15px rgba(0,255,136,0.12) inset;
  }
  .proto-tabs { display: flex; gap: 8px; flex-wrap: wrap; }
  .grid-2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 16px; }
  .form-row { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; margin-bottom: 10px; }
  .inp {
    background: var(--panel2); border: 1px solid var(--border);
    color: var(--text); padding: 8px 12px; border-radius: 8px;
    font-size: 13px; outline: none; font-family: inherit;
  }
  .inp:focus { border-color: var(--neon); box-shadow: 0 0 10px rgba(0,246,255,0.35); }
  table { width: 100%; border-collapse: collapse; font-size: 13px; font-family: inherit; }
  th, td { text-align: left; padding: 8px 12px; border-bottom: 1px solid var(--border); }
  th { color: var(--neon); font-weight: 600; }

  /* Modal */
  .modal-bg {
    position: fixed; inset: 0; background: rgba(0,0,0,0.75);
    display: none; place-items: center; z-index: 99; padding: 20px;
  }
  .modal-bg.open { display: grid; }
  .modal-box {
    background: var(--panel); border: 1px solid var(--border);
    border-radius: 14px; max-width: 900px; width: 100%; max-height: 85vh;
    display: flex; flex-direction: column; overflow: hidden;
  }
  .modal-head {
    padding: 12px 16px; border-bottom: 1px solid var(--border);
    display: flex; justify-content: space-between; align-items: center;
  }
  .modal-body { padding: 16px; overflow: auto; flex: 1; }
  textarea.inp { width: 100%; min-height: 90px; font-family: inherit; }
  .toast-wrap { position: fixed; bottom: 18px; right: 18px; z-index: 200; display: flex; flex-direction: column; gap: 8px; max-width: 340px; }
  .toast {
    background: rgba(30, 41, 59, 0.96); border: 1px solid var(--accent); border-left: 4px solid var(--neon);
    color: var(--text); padding: 10px 14px; border-radius: 10px; font-size: 13px;
    box-shadow: 0 10px 28px rgba(0,0,0,0.55), 0 0 20px rgba(0,246,255,0.2); animation: slideIn 0.2s ease-out;
  }
  .toast-title { font-weight: 700; color: var(--neon); font-size: 12px; margin-bottom: 2px; }
  @keyframes slideIn { from { transform: translateX(30px); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
  @keyframes glitch { 0%,100%{transform:translate(0)} 25%{transform:translate(-2px,2px)} 75%{transform:translate(2px,-2px)} }
  @keyframes pulseGlow { 0%,100%{box-shadow:0 0 12px rgba(0,246,255,0.3)} 50%{box-shadow:0 0 26px rgba(0,246,255,0.75)} }

  /* Group Call (in chat) */
  .call-tile { position: relative; background: #020617; border: 1px solid var(--border); border-radius: 10px; overflow: hidden; display: flex; flex-direction: column; aspect-ratio: 16/9; min-height: 140px; }
  .call-tile video { width: 100%; height: 100%; object-fit: cover; display: block; background: #020617; }
  .call-tile-label { position: absolute; bottom: 6px; left: 6px; font-size: 11px; font-weight: 700; color: #fff; text-shadow: 0 0 6px rgba(0,0,0,0.8); pointer-events: none; z-index: 2; }

  /* Mobile responsiveness */
  @media (max-width: 768px) {
    body { flex-direction: column; }
    .sidebar { width: 100%; height: auto; border-right: none; border-bottom: 1px solid var(--border); padding: 10px 8px; flex-direction: row; overflow-x: auto; gap: 6px; }
    .sidebar .brand { border: none; margin-bottom: 0; padding: 6px 8px; }
    .sidebar .brand-title { font-size: 14px; }
    .sidebar .brand-sub { display: none; }
    .sidebar .nav-btn { white-space: nowrap; padding: 8px 10px; font-size: 12px; gap: 6px; flex-shrink: 0; }
    .sidebar .sidebar-footer { display: none; }
    .main { flex: none; height: calc(100vh - 110px); min-height: 400px; }
    .topbar { padding: 0 10px; height: 44px; }
    .topbar-info { gap: 6px; font-size: 11px; }
    .topbar-info .pill { padding: 3px 8px; font-size: 11px; }
    .chat-wrap { flex-direction: column; height: 100%; }
    .chat-side { width: 100%; height: 200px; border-left: none; border-top: 1px solid var(--border); }
    .chat-main { flex: 1; }
    .call-preview { grid-template-columns: 1fr; }
    .grid-2 { grid-template-columns: 1fr; }
    .call-controls { gap: 6px; }
    .btn.sm { padding: 6px 10px; font-size: 11px; }
  }

  @media (max-width: 480px) {
    .sidebar { padding: 6px 4px; gap: 4px; }
    .nav-btn { padding: 6px 8px; font-size: 11px; gap: 4px; }
    .pad { padding: 10px; }
    .call-preview { min-height: 140px; }
    .call-controls { flex-direction: column; align-items: stretch; }
    .call-controls button { width: 100%; }
  }
</style>
</head>
<body>
  <canvas id="matrixRain" style="position:fixed;inset:0;z-index:-3;opacity:0.30;pointer-events:none;"></canvas>
  <div class="grid-overlay" style="position:fixed;inset:0;z-index:-1;pointer-events:none;background-image:linear-gradient(rgba(0,246,255,0.055) 1px,transparent 1px),linear-gradient(90deg,rgba(0,246,255,0.055) 1px,transparent 1px);background-size:48px 48px;mask-image:radial-gradient(ellipse at 50% 40%,#000 35%,transparent 78%);-webkit-mask-image:radial-gradient(ellipse at 50% 40%,#000 35%,transparent 78%);"></div>
  <aside class="sidebar">
    <div class="brand">
      <div class="brand-logo">🦆</div>
      <div>
        <div class="brand-title">DUCK HUB</div>
        <div class="brand-sub" id="connStatus">● Connecting...</div>
      </div>
    </div>
    <button class="nav-btn active" onclick="showTab('chat', this)">💬 Intranet Chat</button>
    <button class="nav-btn" onclick="showTab('files', this)">📁 File Vault</button>
    <button class="nav-btn" onclick="showTab('desktop', this)">🖥️ Remote Desktop</button>
    <button class="nav-btn" onclick="showTab('terminal', this)">⌨️ Remote Terminal</button>
    <button class="nav-btn" onclick="showTab('protocols', this)">🌐 All-Protocol Hub</button>
    <button class="nav-btn" onclick="showTab('devices', this)">📡 Devices & LAN</button>

    <div class="sidebar-footer">
      <label>Your Device Name</label>
      <input class="nick-input" id="nickInput" placeholder="Device nickname">
      <div id="hostUrlBox" style="font-size:11px; color:var(--accent);">http://duck</div>
    </div>
  </aside>

  <main class="main">
    <header class="topbar">
      <div class="topbar-info">
        <span class="pill online" id="hostPill">Host: loading...</span>
        <span class="pill" id="onlineCount">0 online</span>
      </div>
      <div style="display:flex; gap:8px; align-items:center;">
        <button class="btn secondary sm" id="notifBtn" onclick="enableAlerts()">🔔 Alerts</button>
        <button class="btn secondary sm" onclick="checkUpdates(true)">↻ Check Update</button>
        <button class="btn blue sm" id="tunnelBtn" onclick="toggleTunnel()">🌐 Go Online (Internet)</button>
        <button class="btn secondary sm" onclick="copyShareUrl()">📋 Copy http://duck</button>
        <button class="btn sm" onclick="showTab('files', document.querySelectorAll('.nav-btn')[1])">+ Share File</button>
      </div>
    </header>
    <div id="updateBanner" style="display:none; background:#1c2516; border-bottom:1px solid #2e4d1e; padding:8px 20px; align-items:center; justify-content:space-between; font-size:13px;">
      <span id="updateText" style="color:var(--green); font-weight:600;">🆕 New Duck update available!</span>
      <button class="btn sm" onclick="applyUpdate()">⬇ Update Now</button>
    </div>
    <div id="tunnelBanner" style="display:none; background:#121d33; border-bottom:1px solid var(--border); padding:8px 20px; align-items:center; justify-content:space-between; gap:12px; flex-wrap:wrap; font-size:13px;">
      <div style="display:flex; align-items:center; gap:10px; flex-wrap:wrap;">
        <span class="pill online" id="tunnelStatusPill">● Connecting...</span>
        <span>Share URL: <b id="tunnelUrlText" style="color:var(--accent);">...</b></span>
        <button class="btn secondary sm" onclick="copyText(document.getElementById('tunnelUrlText').textContent)">📋 Copy URL</button>
      </div>
      <div style="display:flex; align-items:center; gap:8px;">
        <span>OTP: <b id="tunnelOtpText" style="color:var(--green); font-size:15px; letter-spacing:2px;">------</b></span>
        <button class="btn secondary sm" onclick="copyText(document.getElementById('tunnelOtpText').textContent)">📋 Copy OTP</button>
        <button class="btn secondary sm" onclick="rotateOtp()">↻ New OTP</button>
      </div>
    </div>

    <!-- CHAT TAB -->
    <section id="tab-chat" class="content active">
      <!-- Incoming call prompt (shows when a peer starts a call) -->
      <div id="incomingCallBanner" style="display:none; background:#121d33; border-bottom:1px solid var(--accent); padding:8px 16px; font-size:13px; gap:10px; align-items:center; justify-content:space-between;">
        <span id="incomingCallText" style="color:var(--accent); font-weight:700;">📞 Incoming group call...</span>
        <div style="display:flex; gap:6px; align-items:center;">
          <button class="btn sm" onclick="acceptIncomingCall()">✅ Join Call</button>
          <button class="btn secondary sm" onclick="dismissIncomingCall()">✕ Dismiss</button>
        </div>
      </div>

      <!-- Call banner (shows during active call) -->
      <div id="callBanner" style="display:none; background:linear-gradient(135deg,var(--neon),var(--matrix)); color:#020617; padding:8px 16px; font-weight:700; font-size:13px; gap:10px; align-items:center; justify-content:space-between; border-radius:0 0 10px 10px;">
        <span style="display:flex; align-items:center; gap:8px;">
          🔴 GROUP CALL LIVE — <span id="callPeerCount">1</span> connected
          <span id="callTimerBanner" style="font-family:monospace; font-size:11px; margin-left:8px;">00:00</span>
        </span>
        <div style="display:flex; gap:6px; align-items:center;">
          <button class="btn sm" id="callMicBtn" onclick="toggleCallMic()" style="background:#020617; color:#fff;">🎙️ Mic On</button>
          <button class="btn sm" id="callVidBtn" onclick="toggleCallVideo()" style="background:#020617; color:#fff;">📷 Cam On</button>
          <button class="btn sm" id="callScreenBtn" onclick="toggleCallScreen()" style="background:#020617; color:#fff;">🖥️ Share</button>
          <button class="btn sm" onclick="hangupCall()" style="background:#7f1d1d; color:#fff;">📞 Hang Up</button>
        </div>
      </div>

      <div class="chat-wrap">
        <!-- Video grid (overlay on top of chat during call) -->
        <div id="callVideoGrid" style="display:none; position:absolute; inset:0; z-index:40; pointer-events:none; padding:10px; gap:8px; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));"></div>

        <div class="chat-main">
          <div class="chat-messages" id="chatMessages"></div>
          <div class="chat-input-bar">
            <input type="file" id="chatFileInput" style="display:none" multiple onchange="uploadChatFiles(this.files)">
            <button class="btn secondary" onclick="document.getElementById('chatFileInput').click()" title="Attach any file">📎</button>
            <button class="btn blue sm" id="callBtn" onclick="toggleGroupCall()">📞 Group Call</button>
            <input class="chat-input" id="chatInput" placeholder="Message all devices... (paste images or press Enter)" onkeydown="if(event.key==='Enter')sendChat()">
            <button class="btn" onclick="sendChat()">Send</button>
          </div>
        </div>
        <aside class="chat-side">
          <div class="card">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
              <h3 style="margin:0;">Online Devices</h3>
              <button class="btn secondary sm" onclick="clearChat()" title="Clear chat history">🗑 Clear Chat</button>
            </div>
            <div id="presenceList" style="display:flex; flex-direction:column; gap:6px; font-size:13px;"></div>
          </div>
          <div class="card">
            <h3>Shared Clipboard</h3>
            <textarea class="inp" id="clipBox" placeholder="Paste text here to sync across all devices..."></textarea>
            <div style="display:flex; gap:6px; margin-top:8px;">
              <button class="btn sm" onclick="syncClipboard()">Sync Now</button>
              <button class="btn secondary sm" onclick="copyClipboard()">Copy</button>
            </div>
          </div>
        </aside>
      </div>
    </section>

    <!-- FILES TAB -->
    <section id="tab-files" class="content">
      <div class="pad">
        <div class="dropzone" id="dropzone" onclick="document.getElementById('vaultFileInput').click()">
          <input type="file" id="vaultFileInput" style="display:none" multiple onchange="uploadVaultFiles(this.files)">
          <div style="font-size:28px; margin-bottom:6px;">📦</div>
          <div style="font-weight:600; font-size:15px;">Drop ANY file here or click to upload</div>
          <div style="font-size:12px; color:var(--muted); margin-top:4px;">Unrestricted: .exe, .iso, .zip, .apk, .mp4, code, documents — any size</div>
          <div class="progress-wrap" id="uploadProgWrap"><div class="progress-bar" id="uploadProgBar"></div></div>
          <div id="uploadStatus" style="font-size:12px; color:var(--accent); margin-top:6px;"></div>
        </div>
        <div style="display:flex; justify-content:space-between; align-items:center; gap:10px; flex-wrap:wrap;">
          <input class="inp" id="fileSearch" placeholder="Search files..." oninput="renderFiles()" style="min-width:240px;">
          <div style="display:flex; gap:8px;">
            <a class="btn secondary sm" href="/api/zip" style="text-decoration:none;">⬇ Download All (.zip)</a>
            <button class="btn secondary sm" onclick="loadFiles()">↻ Refresh</button>
          </div>
        </div>
        <div class="file-grid" id="fileGrid"></div>
      </div>
    </section>

    <!-- REMOTE DESKTOP TAB -->
    <section id="tab-desktop" class="content">
      <div class="rd-toolbar">
        <button class="btn sm" id="rdToggleBtn" onclick="toggleScreenStream()">▶ Start Live View</button>
        <label style="font-size:12px; color:var(--muted);">Quality/Scale:
          <select class="inp" id="rdScale" style="padding:4px 8px;">
            <option value="0.45">Fast (45%)</option>
            <option value="0.65" selected>Balanced (65%)</option>
            <option value="0.9">Sharp (90%)</option>
          </select>
        </label>
        <label style="font-size:12px; color:var(--muted);">
          <input type="checkbox" id="rdControlChk" checked> Enable Mouse & Keyboard
        </label>
        <input class="inp" id="rdTypeInput" placeholder="Type text to remote..." style="width:180px;" onkeydown="if(event.key==='Enter')sendRemoteText()">
        <button class="btn secondary sm" onclick="sendRemoteText()">Send Text</button>
        <button class="btn secondary sm" onclick="sendSpecialKey('Win')">⊞ Win</button>
        <button class="btn secondary sm" onclick="sendSpecialKey('ALT_TAB')">Alt+Tab</button>
        <button class="btn secondary sm" onclick="sendSpecialKey('WIN_D')">Show Desktop</button>
        <button class="btn secondary sm" onclick="sendSpecialKey('CTRL_ALT_DEL')">TaskMgr</button>
      </div>
      <div class="rd-stage">
        <img id="screenImg" alt="Click 'Start Live View' to stream host screen"
             onclick="handleScreenClick(event, 'click')"
             ondblclick="handleScreenClick(event, 'dblclick')"
             oncontextmenu="event.preventDefault(); handleScreenClick(event, 'rclick')"
             onwheel="handleScreenWheel(event)">
      </div>
    </section>

    <!-- TERMINAL TAB -->
    <section id="tab-terminal" class="content">
      <div class="pad">
        <div class="form-row">
          <select class="inp" id="termShell">
            <option value="powershell">PowerShell</option>
            <option value="cmd">CMD</option>
          </select>
          <input class="inp" id="termCmd" style="flex:1;" placeholder="Enter command to execute on host (e.g. ipconfig, dir, systeminfo)..." onkeydown="if(event.key==='Enter')runRemoteCmd()">
          <button class="btn" onclick="runRemoteCmd()">Run</button>
          <button class="btn secondary" onclick="document.getElementById('termOut').textContent=''">Clear</button>
        </div>
        <div class="term-out" id="termOut">Duck Remote Terminal ready. Type a command above.\n</div>
      </div>
    </section>

    <!-- ALL-PROTOCOL HUB TAB -->
    <section id="tab-protocols" class="content">
      <div class="pad">
        <div class="proto-tabs">
          <button class="btn sm" onclick="showProto('ssh')">SSH / SFTP</button>
          <button class="btn secondary sm" onclick="showProto('ftp')">FTP Client</button>
          <button class="btn secondary sm" onclick="showProto('tcp')">Telnet / Raw TCP & UDP</button>
          <button class="btn secondary sm" onclick="showProto('http')">HTTP / HTTPS Tester</button>
          <button class="btn secondary sm" onclick="showProto('rdp')">RDP / VNC / SMB</button>
        </div>

        <!-- SSH -->
        <div id="proto-ssh" class="card">
          <h3>SSH Remote Execution & Terminal</h3>
          <div class="form-row">
            <input class="inp" id="sshHost" placeholder="Host / IP (e.g. 192.168.0.105)">
            <input class="inp" id="sshPort" value="22" style="width:70px;">
            <input class="inp" id="sshUser" placeholder="Username">
            <input class="inp" id="sshPass" type="password" placeholder="Password">
            <button class="btn" onclick="sshConnect()">Connect SSH</button>
            <button class="btn danger sm" onclick="sshDisconnect()">Disconnect</button>
          </div>
          <div class="form-row">
            <input class="inp" id="sshCmd" style="flex:1;" placeholder="SSH command..." onkeydown="if(event.key==='Enter')sshSend()">
            <button class="btn blue sm" onclick="sshSend()">Send</button>
          </div>
          <div class="term-out" id="sshOut" style="height:240px;">SSH output will appear here...</div>
        </div>

        <!-- FTP -->
        <div id="proto-ftp" class="card" style="display:none;">
          <h3>FTP GUI Client</h3>
          <div class="form-row">
            <input class="inp" id="ftpHost" placeholder="FTP Host / IP">
            <input class="inp" id="ftpPort" value="21" style="width:70px;">
            <input class="inp" id="ftpUser" value="anonymous" placeholder="User">
            <input class="inp" id="ftpPass" type="password" placeholder="Password">
            <input class="inp" id="ftpPath" value="/" placeholder="Path">
            <button class="btn" onclick="ftpList()">List Directory</button>
          </div>
          <div id="ftpOut" style="max-height:280px; overflow:auto;"></div>
        </div>

        <!-- TCP / TELNET / UDP -->
        <div id="proto-tcp" class="card" style="display:none;">
          <h3>Telnet / Raw TCP & UDP Console</h3>
          <div class="form-row">
            <select class="inp" id="netProto"><option value="tcp">TCP / Telnet</option><option value="udp">UDP</option></select>
            <input class="inp" id="netHost" placeholder="Target IP / Host">
            <input class="inp" id="netPort" placeholder="Port" style="width:90px;">
            <button class="btn" onclick="netConnect()">Connect TCP</button>
            <button class="btn danger sm" onclick="netDisconnect()">Close</button>
          </div>
          <div class="form-row">
            <input class="inp" id="netSend" style="flex:1;" placeholder="Payload to send..." onkeydown="if(event.key==='Enter')netSendData()">
            <button class="btn blue sm" onclick="netSendData()">Send</button>
          </div>
          <div class="term-out" id="netOut" style="height:230px;"></div>
        </div>

        <!-- HTTP / HTTPS -->
        <div id="proto-http" class="card" style="display:none;">
          <h3>Internal HTTP / HTTPS Client</h3>
          <div class="form-row">
            <select class="inp" id="httpMethod"><option>GET</option><option>POST</option><option>PUT</option><option>DELETE</option></select>
            <input class="inp" id="httpUrl" style="flex:1;" placeholder="http://192.168.0.1/ or https://...">
            <button class="btn" onclick="sendHttpReq()">Send Request</button>
          </div>
          <textarea class="inp" id="httpBody" placeholder="Optional request body (JSON/text)..."></textarea>
          <div class="term-out" id="httpOut" style="height:220px; margin-top:10px;"></div>
        </div>

        <!-- RDP / VNC / SMB -->
        <div id="proto-rdp" class="card" style="display:none;">
          <h3>RDP / VNC / SMB Remote Launchers</h3>
          <div class="form-row">
            <input class="inp" id="rdpHost" placeholder="Target LAN IP (e.g. 192.168.0.105)">
            <input class="inp" id="rdpUser" placeholder="Username (optional)">
            <button class="btn" onclick="downloadRdp()">⬇ Download .RDP File</button>
            <button class="btn blue" onclick="launchHostTool('rdp')">Launch MSTSC on Host</button>
            <button class="btn secondary" onclick="launchHostTool('smb')">Open SMB Share (\\IP)</button>
          </div>
          <p style="font-size:12px; color:var(--muted);">Tip: Use the Devices & LAN Scanner tab to auto-discover devices with open RDP (3389), SSH (22), SMB (445), HTTP (80), FTP (21), or VNC (5900) ports.</p>
        </div>
      </div>
    </section>

    <!-- DEVICES & LAN TAB -->
    <section id="tab-devices" class="content">
      <div class="pad">
        <div class="grid-2">
          <div class="card">
            <h3>Discovered Duck Peers</h3>
            <div id="peerList" style="font-size:13px; color:var(--muted);">Scanning LAN for Duck peers...</div>
          </div>
          <div class="card">
            <h3>Intranet Scanner (ARP + Port Probe)</h3>
            <button class="btn" onclick="scanLan()" id="scanBtn">🔍 Scan Intranet Devices</button>
            <div id="scanStatus" style="font-size:12px; color:var(--muted); margin-top:8px;"></div>
          </div>
        </div>
        <div class="card">
          <h3>LAN Devices & Open Protocols</h3>
          <table>
            <thead><tr><th>IP Address</th><th>Hostname</th><th>MAC / Type</th><th>Open Ports / Protocols</th><th>Quick Connect</th></tr></thead>
            <tbody id="lanTableBody"><tr><td colspan="5" style="color:var(--muted);">Click "Scan Intranet Devices" to discover devices on your network.</td></tr></tbody>
          </table>
        </div>
      </div>
    </section>

    <!-- FILES TAB -->
  </main>

  <div class="toast-wrap" id="toastContainer"></div>

  <!-- PREVIEW MODAL -->
  <div class="modal-bg" id="previewModal" onclick="if(event.target===this)closeModal()">
    <div class="modal-box">
      <div class="modal-head">
        <span id="modalTitle" style="font-weight:600;">Preview</span>
        <button class="btn secondary sm" onclick="closeModal()">✕ Close</button>
      </div>
      <div class="modal-body" id="modalBody"></div>
    </div>
  </div>

<script>
/* ---- Matrix rain (hacker backdrop) ---- */
(function initMatrixRain() {
  const cv = document.getElementById('matrixRain');
  if (!cv) return;
  const ctx = cv.getContext('2d');
  const CHARS = 'アイウエオカキクケコサシスセソタチツテトナニヌネノ0123456789ABCDEF$#@%&*<>/\\|=+-';
  let cols = 0, rows = 0, drops = [], speed = [], cellW = 16, cellH = 18;

  function resize() {
    cv.width = window.innerWidth;
    cv.height = window.innerHeight;
    cols = Math.max(1, Math.floor(cv.width / cellW));
    rows = Math.max(1, Math.ceil(cv.height / cellH));
    drops = new Array(cols);
    speed = new Array(cols);
    for (let i = 0; i < cols; i++) {
      drops[i] = Math.random() * -rows;
      speed[i] = 0.5 + Math.random() * 0.9;
    }
  }

  let last = 0;
  function frame(ts) {
    if (ts - last > 55) {
      last = ts;
      ctx.fillStyle = 'rgba(2,6,23,0.16)';
      ctx.fillRect(0, 0, cv.width, cv.height);
      ctx.font = cellH + 'px monospace';
      for (let i = 0; i < cols; i++) {
        const ch = CHARS[(Math.random() * CHARS.length) | 0];
        const x = i * cellW;
        const y = drops[i] * cellH;
        // Head of the stream: bright cyan; tail: dim green
        ctx.fillStyle = 'rgba(0,246,255,0.95)';
        ctx.fillText(ch, x, y);
        ctx.fillStyle = 'rgba(5,150,105,' + (0.25 + Math.random() * 0.35).toFixed(2) + ')';
        ctx.fillText(CHARS[(Math.random() * CHARS.length) | 0], x, y - cellH * 2);
        drops[i] += speed[i];
        if (y > cv.height && Math.random() > 0.975) drops[i] = Math.random() * -20;
      }
    }
    requestAnimationFrame(frame);
  }

  resize();
  window.addEventListener('resize', resize);
  requestAnimationFrame(frame);
})();

let ws = null;
let myName = localStorage.getItem('duck_nick') || ('Device-' + Math.floor(100 + Math.random() * 900));
document.getElementById('nickInput').value = myName;
document.getElementById('nickInput').addEventListener('change', (e) => {
  myName = e.target.value.trim() || myName;
  localStorage.setItem('duck_nick', myName);
  if (ws && ws.readyState === 1) ws.send(JSON.stringify({type: 'hello', name: myName}));
});

let allFiles = [];
let screenTimer = null;

function showTab(name, btn) {
  document.querySelectorAll('.content').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-btn').forEach(el => el.classList.remove('active'));
  document.getElementById('tab-' + name).classList.add('active');
  if (btn) btn.classList.add('active');
  if (name === 'files') loadFiles();
  if (name === 'devices') loadPeers();
}

function showProto(name) {
  ['ssh','ftp','tcp','http','rdp'].forEach(p => {
    document.getElementById('proto-' + p).style.display = (p === name) ? 'block' : 'none';
  });
}

function connectWS() {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(proto + '//' + location.host + '/ws');
  ws.onopen = () => {
    document.getElementById('connStatus').textContent = '● Connected';
    document.getElementById('connStatus').style.color = 'var(--green)';
    ws.send(JSON.stringify({type: 'hello', name: myName}));
  };
  ws.onclose = () => {
    document.getElementById('connStatus').textContent = '● Reconnecting...';
    document.getElementById('connStatus').style.color = 'var(--accent)';
    setTimeout(connectWS, 2000);
  };
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.type === 'init') {
      if (!localStorage.getItem('duck_nick') && msg.your_name) {
        myName = msg.your_name;
        document.getElementById('nickInput').value = myName;
      }
      document.getElementById('hostPill').textContent = `Host: ${msg.host} (${msg.ip}:${msg.port})`;
      document.getElementById('hostUrlBox').textContent = `http://duck${msg.port==80?'':':'+msg.port} | http://${msg.ip}${msg.port==80?'':':'+msg.port}`;
      document.getElementById('chatMessages').innerHTML = '';
      msg.messages.forEach(appendChat);
      document.getElementById('clipBox').value = msg.clipboard || '';
      renderPresence(msg.users || []);
      if (msg.tunnel) renderTunnel(msg.tunnel);
      if (msg.update) showUpdateBanner(msg.update);
    } else if (msg.type === 'tunnel') {
      renderTunnel(msg.tunnel);
      if (msg.tunnel?.url) notifyUser('Internet Tunnel Live', `${msg.tunnel.url} (OTP: ${msg.tunnel.otp})`);
    } else if (msg.type === 'chat') {
      appendChat(msg.message);
      if (msg.message.sender !== myName) {
        notifyUser(`💬 ${msg.message.sender}`, msg.message.text || 'Sent an attachment');
      }
    } else if (msg.type === 'chat_cleared') {
      document.getElementById('chatMessages').innerHTML = '';
      (msg.messages || []).forEach(appendChat);
    } else if (msg.type === 'presence') {
      renderPresence(msg.users || []);
    } else if (msg.type === 'device_joined') {
      notifyUser('📡 Device Connected', `${msg.ip} joined Duck Hub`);
    } else if (msg.type === 'clipboard') {
      document.getElementById('clipBox').value = msg.text;
      if (msg.sender !== myName) notifyUser('📋 Clipboard Synced', `Updated by ${msg.sender}`);
    } else if (msg.type === 'files_updated') {
      loadFiles();
      if (msg.name) notifyUser('📁 New File Shared', `${msg.name} (${fmtSize(msg.size || 0)})`);
    } else if (msg.type === 'update_available') {
      showUpdateBanner(msg.update);
      notifyUser('🆕 Update Available', `Duck v${msg.update.latest} is on GitHub!`);
    } else if (msg.type === 'call_gc_offer') {
      handleIncomingGcOffer(msg);
    } else if (msg.type === 'call_gc_answer') {
      handleGcAnswer(msg);
    } else if (msg.type === 'call_gc_ice') {
      handleGcIce(msg);
    } else if (msg.type === 'call_gc_hangup') {
      handleGcHangup(msg);
    } else if (msg.type === 'ssh_out') {
      const out = document.getElementById('sshOut');
      out.textContent += msg.data;
      out.scrollTop = out.scrollHeight;
    } else if (msg.type === 'tcp_out') {
      const out = document.getElementById('netOut');
      out.textContent += msg.data;
      out.scrollTop = out.scrollHeight;
    }
  };
}

function renderPresence(users) {
  document.getElementById('onlineCount').textContent = `${users.length} online`;
  const list = document.getElementById('presenceList');
  list.innerHTML = users.map(u => {
    const hostTag = (u.hostname && u.hostname !== u.name) ? ` <span style="color:var(--accent);font-size:11px;">[${esc(u.hostname)}]</span>` : '';
    return `<div>🟢 <b>${esc(u.name)}</b>${hostTag} <span style="color:var(--muted);font-size:11px;">(${esc(u.ip)})</span></div>`;
  }).join('') || '<div style="color:var(--muted)">No users</div>';
}

function appendChat(m) {
  const box = document.getElementById('chatMessages');
  const div = document.createElement('div');
  div.className = 'msg' + (m.sender === myName ? ' me' : '');
  let attHtml = '';
  (m.attachments || []).forEach(a => {
    const isImg = /\.(png|jpg|jpeg|gif|webp|bmp)$/i.test(a.name);
    attHtml += `<div class="msg-attach">
      <div>📄 <b>${esc(a.name)}</b> (${fmtSize(a.size)})
      ${isImg ? `<br><img src="/api/files/${encodeURIComponent(a.name)}">` : ''}</div>
      <a class="btn sm" href="/api/files/${encodeURIComponent(a.name)}?download=1" style="text-decoration:none;">⬇</a>
    </div>`;
  });
  div.innerHTML = `<div class="msg-head"><span class="msg-sender">${esc(m.sender)}</span><span class="msg-meta">${esc(m.ip || '')} • ${esc(m.ts || '')}</span></div>
    <div class="msg-body">${esc(m.text || '')}</div>${attHtml}`;
  box.appendChild(div);
  box.scrollTop = box.scrollHeight;
}

function sendChat(attachments = []) {
  const inp = document.getElementById('chatInput');
  const text = inp.value.trim();
  if (!text && !attachments.length) return;
  ws.send(JSON.stringify({type: 'chat', sender: myName, text, attachments}));
  inp.value = '';
}
async function clearChat() {
  if (!confirm('Clear all chat messages for everyone?')) return;
  await fetch('/api/chat/clear', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({sender: myName})});
}

document.getElementById('chatInput').addEventListener('paste', async (e) => {
  const items = e.clipboardData?.items || [];
  for (const it of items) {
    if (it.type.startsWith('image/')) {
      e.preventDefault();
      const file = it.getAsFile();
      const name = 'paste_' + Date.now() + '.png';
      await uploadSingleFile(file, name);
      sendChat([{name, size: file.size}]);
    }
  }
});

async function uploadChatFiles(files) {
  const atts = [];
  for (const f of files) {
    await uploadSingleFile(f, f.name);
    atts.push({name: f.name, size: f.size});
  }
  if (atts.length) sendChat(atts);
}

function syncClipboard() {
  ws.send(JSON.stringify({type: 'clipboard', text: document.getElementById('clipBox').value, sender: myName}));
}
function copyClipboard() {
  navigator.clipboard.writeText(document.getElementById('clipBox').value);
}
function copyShareUrl() {
  navigator.clipboard.writeText(location.origin);
  alert('Copied: ' + location.origin);
}

// File Vault
const dz = document.getElementById('dropzone');
dz.addEventListener('dragover', e => { e.preventDefault(); dz.classList.add('drag'); });
dz.addEventListener('dragleave', () => dz.classList.remove('drag'));
dz.addEventListener('drop', e => { e.preventDefault(); dz.classList.remove('drag'); uploadVaultFiles(e.dataTransfer.files); });

async function uploadVaultFiles(files) {
  for (const f of files) await uploadSingleFile(f, f.name);
  loadFiles();
}

function uploadSingleFile(file, filename) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    const wrap = document.getElementById('uploadProgWrap');
    const bar = document.getElementById('uploadProgBar');
    const st = document.getElementById('uploadStatus');
    wrap.style.display = 'block';
    xhr.open('POST', '/api/upload');
    xhr.setRequestHeader('X-Filename', encodeURIComponent(filename));
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) {
        const pct = Math.round((e.loaded / e.total) * 100);
        bar.style.width = pct + '%';
        st.textContent = `Uploading ${filename}: ${pct}%`;
      }
    };
    xhr.onload = () => {
      st.textContent = `Uploaded ${filename}`;
      setTimeout(() => { wrap.style.display = 'none'; bar.style.width = '0%'; }, 1200);
      resolve();
    };
    xhr.onerror = reject;
    xhr.send(file);
  });
}

async function loadFiles() {
  const res = await fetch('/api/files');
  allFiles = await res.json();
  renderFiles();
}

function renderFiles() {
  const q = document.getElementById('fileSearch').value.toLowerCase();
  const grid = document.getElementById('fileGrid');
  const filtered = allFiles.filter(f => f.name.toLowerCase().includes(q));
  grid.innerHTML = filtered.map(f => `
    <div class="file-card">
      <div class="file-name">📄 ${esc(f.name)}</div>
      <div class="file-meta">${fmtSize(f.size)} • ${esc(f.mtime)}</div>
      <div class="file-actions">
        <button class="btn secondary sm" onclick="previewFile('${escAttr(f.name)}')">👁 Preview</button>
        <a class="btn sm" href="/api/files/${encodeURIComponent(f.name)}?download=1" style="text-decoration:none;">⬇ Download</a>
        <button class="btn secondary sm" onclick="copyFileLink('${escAttr(f.name)}')">🔗</button>
        <button class="btn danger sm" onclick="deleteFile('${escAttr(f.name)}')">🗑</button>
      </div>
    </div>
  `).join('') || '<div style="color:var(--muted)">No files shared yet. Drop any file above!</div>';
}

async function deleteFile(name) {
  await fetch('/api/files/' + encodeURIComponent(name), {method: 'DELETE'});
  loadFiles();
}
function copyFileLink(name) {
  const url = location.origin + '/api/files/' + encodeURIComponent(name) + '?download=1';
  navigator.clipboard.writeText(url);
}
async function previewFile(name) {
  const url = '/api/files/' + encodeURIComponent(name);
  document.getElementById('modalTitle').textContent = name;
  const body = document.getElementById('modalBody');
  if (/\.(png|jpg|jpeg|gif|webp|bmp|svg)$/i.test(name)) {
    body.innerHTML = `<img src="${url}" style="max-width:100%; border-radius:8px;">`;
  } else if (/\.(mp4|webm|ogg)$/i.test(name)) {
    body.innerHTML = `<video src="${url}" controls autoplay style="max-width:100%; width:100%;"></video>`;
  } else if (/\.(mp3|wav|m4a|flac)$/i.test(name)) {
    body.innerHTML = `<audio src="${url}" controls autoplay style="width:100%;"></audio>`;
  } else if (/\.pdf$/i.test(name)) {
    body.innerHTML = `<iframe src="${url}" style="width:100%; height:70vh; border:none;"></iframe>`;
  } else {
    const txt = await (await fetch(url)).text();
    body.innerHTML = `<pre style="white-space:pre-wrap; font-family:Consolas,monospace; font-size:13px;">${esc(txt.slice(0, 100000))}</pre>`;
  }
  document.getElementById('previewModal').classList.add('open');
}
function closeModal() { document.getElementById('previewModal').classList.remove('open'); }

// Remote Desktop
function toggleScreenStream() {
  const btn = document.getElementById('rdToggleBtn');
  if (screenTimer) {
    clearInterval(screenTimer);
    screenTimer = null;
    btn.textContent = '▶ Start Live View';
  } else {
    btn.textContent = '⏹ Stop Live View';
    refreshScreen();
    screenTimer = setInterval(refreshScreen, 350);
  }
}
function refreshScreen() {
  const scale = document.getElementById('rdScale').value;
  document.getElementById('screenImg').src = `/api/screen.png?scale=${scale}&t=${Date.now()}`;
}
function handleScreenClick(e, kind) {
  if (!document.getElementById('rdControlChk').checked) return;
  const rect = e.target.getBoundingClientRect();
  const x = (e.clientX - rect.left) / rect.width;
  const y = (e.clientY - rect.top) / rect.height;
  fetch('/api/screen/input', {method:'POST', body: JSON.stringify({kind, x, y})});
}
function handleScreenWheel(e) {
  if (!document.getElementById('rdControlChk').checked) return;
  e.preventDefault();
  fetch('/api/screen/input', {method:'POST', body: JSON.stringify({kind:'wheel', delta: e.deltaY < 0 ? 120 : -120})});
}
function sendRemoteText() {
  const inp = document.getElementById('rdTypeInput');
  fetch('/api/screen/input', {method:'POST', body: JSON.stringify({kind:'text', text: inp.value + '\n'})});
  inp.value = '';
}
function sendSpecialKey(key) {
  fetch('/api/screen/input', {method:'POST', body: JSON.stringify({kind:'key', key})});
}

// Terminal
async function runRemoteCmd() {
  const shell = document.getElementById('termShell').value;
  const cmd = document.getElementById('termCmd').value;
  if (!cmd.trim()) return;
  const out = document.getElementById('termOut');
  out.textContent += `\n> ${cmd}\n`;
  document.getElementById('termCmd').value = '';
  const res = await fetch('/api/exec', {method:'POST', body: JSON.stringify({shell, cmd})});
  const data = await res.json();
  out.textContent += (data.output || '') + '\n';
  out.scrollTop = out.scrollHeight;
}

// Protocols
function sshConnect() {
  document.getElementById('sshOut').textContent = 'Connecting SSH...\n';
  ws.send(JSON.stringify({
    type: 'ssh_connect',
    host: document.getElementById('sshHost').value,
    port: +document.getElementById('sshPort').value,
    user: document.getElementById('sshUser').value,
    password: document.getElementById('sshPass').value
  }));
}
function sshSend() {
  const inp = document.getElementById('sshCmd');
  ws.send(JSON.stringify({type: 'ssh_send', data: inp.value + '\n'}));
  inp.value = '';
}
function sshDisconnect() { ws.send(JSON.stringify({type: 'ssh_close'})); }

async function ftpList() {
  const res = await fetch('/api/ftp/list', {
    method: 'POST',
    body: JSON.stringify({
      host: document.getElementById('ftpHost').value,
      port: +document.getElementById('ftpPort').value,
      user: document.getElementById('ftpUser').value,
      password: document.getElementById('ftpPass').value,
      path: document.getElementById('ftpPath').value
    })
  });
  const data = await res.json();
  if (data.error) { document.getElementById('ftpOut').innerHTML = `<span style="color:var(--red)">${esc(data.error)}</span>`; return; }
  document.getElementById('ftpOut').innerHTML = `<pre style="font-size:12px;">${esc((data.lines||[]).join('\n'))}</pre>`;
}

function netConnect() {
  document.getElementById('netOut').textContent = 'Connecting...\n';
  ws.send(JSON.stringify({type: 'tcp_connect', host: document.getElementById('netHost').value, port: +document.getElementById('netPort').value}));
}
function netDisconnect() { ws.send(JSON.stringify({type: 'tcp_close'})); }
async function netSendData() {
  const proto = document.getElementById('netProto').value;
  const data = document.getElementById('netSend').value;
  if (proto === 'tcp') {
    ws.send(JSON.stringify({type: 'tcp_send', data: data + '\r\n'}));
  } else {
    const res = await fetch('/api/net/udp', {method:'POST', body: JSON.stringify({
      host: document.getElementById('netHost').value,
      port: +document.getElementById('netPort').value,
      data
    })});
    const j = await res.json();
    document.getElementById('netOut').textContent += `[UDP] ${j.status || j.error}\n`;
  }
  document.getElementById('netSend').value = '';
}

async function sendHttpReq() {
  const res = await fetch('/api/http_req', {method:'POST', body: JSON.stringify({
    method: document.getElementById('httpMethod').value,
    url: document.getElementById('httpUrl').value,
    body: document.getElementById('httpBody').value
  })});
  const j = await res.json();
  document.getElementById('httpOut').textContent = j.error ? j.error : `HTTP ${j.status}\n\n${j.body}`;
}

function downloadRdp() {
  const ip = document.getElementById('rdpHost').value;
  const user = document.getElementById('rdpUser').value;
  location.href = `/api/rdp_file?ip=${encodeURIComponent(ip)}&user=${encodeURIComponent(user)}`;
}
async function launchHostTool(tool) {
  const ip = document.getElementById('rdpHost').value;
  await fetch('/api/launch_tool', {method:'POST', body: JSON.stringify({tool, ip})});
}

// LAN Scanner & Peers
async function loadPeers() {
  const peers = await (await fetch('/api/peers')).json();
  document.getElementById('peerList').innerHTML = peers.map(p =>
    `<div style="margin-bottom:6px;">🦆 <b>${esc(p.host)}</b> (${esc(p.os)}) — <a style="color:var(--accent)" href="http://${esc(p.ip)}:${p.port}" target="_blank">http://${esc(p.ip)}:${p.port}</a></div>`
  ).join('') || 'No other Duck instances detected yet.';
}

async function scanLan() {
  const btn = document.getElementById('scanBtn');
  btn.disabled = true;
  document.getElementById('scanStatus').textContent = 'Scanning ARP table & common protocol ports...';
  const res = await fetch('/api/scan');
  const devices = await res.json();
  btn.disabled = false;
  document.getElementById('scanStatus').textContent = `Found ${devices.length} devices.`;
  document.getElementById('lanTableBody').innerHTML = devices.map(d => `
    <tr>
      <td><b>${esc(d.ip)}</b></td>
      <td>${esc(d.hostname || '-')}</td>
      <td>${esc(d.mac || '-')}</td>
      <td>${d.ports.map(p => `<span class="pill" style="margin-right:4px;">${esc(p)}</span>`).join('') || '<span style="color:var(--muted)">none</span>'}</td>
      <td>
        <button class="btn secondary sm" onclick="quickConnect('${escAttr(d.ip)}','ssh')">SSH</button>
        <button class="btn secondary sm" onclick="quickConnect('${escAttr(d.ip)}','rdp')">RDP</button>
        <button class="btn secondary sm" onclick="quickConnect('${escAttr(d.ip)}','http')">HTTP</button>
      </td>
    </tr>
  `).join('');
}

function quickConnect(ip, proto) {
  showTab('protocols', document.querySelectorAll('.nav-btn')[4]);
  showProto(proto);
  if (proto === 'ssh') document.getElementById('sshHost').value = ip;
  if (proto === 'rdp') document.getElementById('rdpHost').value = ip;
  if (proto === 'http') document.getElementById('httpUrl').value = 'http://' + ip + '/';
}

function esc(s) { return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function escAttr(s) { return String(s).replace(/'/g, "\\'"); }
function fmtSize(b) {
  if (b < 1024) return b + ' B';
  if (b < 1048576) return (b / 1024).toFixed(1) + ' KB';
  if (b < 1073741824) return (b / 1048576).toFixed(1) + ' MB';
  return (b / 1073741824).toFixed(2) + ' GB';
}

function copyText(t) { navigator.clipboard.writeText(t); }
let tunnelActive = false;
function renderTunnel(t) {
  tunnelActive = !!t.active;
  const btn = document.getElementById('tunnelBtn');
  const banner = document.getElementById('tunnelBanner');
  if (t.active) {
    btn.textContent = '⏹ Stop Internet';
    btn.className = 'btn danger sm';
    banner.style.display = 'flex';
    document.getElementById('tunnelStatusPill').textContent = t.status === 'online' ? '● LIVE ON INTERNET' : `● ${t.status}...`;
    document.getElementById('tunnelUrlText').textContent = t.url || 'Generating public URL...';
    document.getElementById('tunnelOtpText').textContent = t.otp || '------';
  } else {
    btn.textContent = '🌐 Go Online (Internet)';
    btn.className = 'btn blue sm';
    banner.style.display = t.error ? 'flex' : 'none';
    if (t.error) {
      document.getElementById('tunnelStatusPill').textContent = '● Error';
      document.getElementById('tunnelUrlText').textContent = t.error;
    }
  }
}
async function toggleTunnel() {
  await fetch(tunnelActive ? '/api/tunnel/stop' : '/api/tunnel/start', {method: 'POST'});
}
async function rotateOtp() {
  await fetch('/api/tunnel/rotate_otp', {method: 'POST'});
}

// Live Notifications, Chime & GitHub Updates
let unreadCount = 0;
let alertsEnabled = true;
window.addEventListener('focus', () => { unreadCount = 0; document.title = 'Duck — Intranet Hub'; });

function enableAlerts() {
  alertsEnabled = true;
  if ('Notification' in window && Notification.permission !== 'granted') {
    Notification.requestPermission().then(p => {
      document.getElementById('notifBtn').textContent = p === 'granted' ? '🔔 Alerts ON' : '🔔 Alerts (In-App)';
    });
  } else {
    document.getElementById('notifBtn').textContent = '🔔 Alerts ON';
  }
  notifyUser('🔔 Notifications Active', 'You will be alerted for messages, files, devices & updates.');
}

function playChime() {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(660, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(880, ctx.currentTime + 0.1);
    gain.gain.setValueAtTime(0.06, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.18);
    osc.connect(gain); gain.connect(ctx.destination);
    osc.start(); osc.stop(ctx.currentTime + 0.19);
  } catch (e) {}
}

function notifyUser(title, body) {
  if (!alertsEnabled) return;
  const wrap = document.getElementById('toastContainer');
  const el = document.createElement('div');
  el.className = 'toast';
  el.innerHTML = `<div class="toast-title">${esc(title)}</div><div>${esc(body)}</div>`;
  wrap.appendChild(el);
  setTimeout(() => el.remove(), 4500);
  playChime();
  if (document.hidden) {
    unreadCount++;
    document.title = `(${unreadCount}) Duck — Intranet Hub`;
  }
  if ('Notification' in window && Notification.permission === 'granted') {
    try { new Notification(title, {body}); } catch (e) {}
  }
}

function showUpdateBanner(u) {
  if (!u || !u.available) return;
  document.getElementById('updateBanner').style.display = 'flex';
  document.getElementById('updateText').textContent = `🆕 Update available: v${u.latest} (current v${u.current}) on GitHub (${u.repo})`;
}
async function checkUpdates(manual = false) {
  // Cache-buster: browsers were serving a stale JSON response, hiding new releases.
  const res = await fetch('/api/update/check?t=' + Date.now(), {cache: 'no-store'});
  const u = await res.json();
  if (u.available) {
    showUpdateBanner(u);
    notifyUser('🆕 Update Available', `v${u.latest} ready to install!`);
  } else if (u.error) {
    if (manual) notifyUser('⚠ Update Check Failed', u.error);
  } else if (manual) {
    notifyUser('✅ Up to Date', `Running Duck v${u.current} (latest on GitHub)`);
  }
}

async function applyUpdate() {
  const res = await fetch('/api/update/apply', {method: 'POST'});
  const j = await res.json();
  notifyUser('⬇ Update Status', j.message || j.error || 'Done');
}

connectWS();
loadFiles();
setTimeout(() => checkUpdates(false), 3000);
// Re-check for updates every 5 minutes so running instances pick up new releases.
setInterval(() => checkUpdates(false), 300000);

/* ============ GROUP CALL (in chat, multi-peer mesh) ============ */
let callLocalStream = null;
let callScreenStream = null;
let callPeers = {};         // peerId -> { pc, stream, label, iceQueue }
let pendingCallOffer = null;
let callTimerInterval = null;
let callActive = false;

const callBtn = document.getElementById('callBtn');
const callBanner = document.getElementById('callBanner');
const callPeerCount = document.getElementById('callPeerCount');
const callVideoGrid = document.getElementById('callVideoGrid');
const RTC_CFG = { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] };

function callLog(msg) {
  const box = document.getElementById('callLog');
  if (box) {
    const d = document.createElement('div');
    d.textContent = new Date().toLocaleTimeString() + '  ' + msg;
    box.appendChild(d);
    box.scrollTop = box.scrollHeight;
  }
}

function addVideoTile(peerId, label, stream) {
  const old = document.getElementById('vt-' + peerId);
  if (old) old.remove();
  const tile = document.createElement('div');
  tile.id = 'vt-' + peerId;
  tile.className = 'call-tile';
  tile.style.cssText = 'position:relative; background:#020617; border:1px solid var(--border); border-radius:10px; overflow:hidden; display:flex; flex-direction:column; min-height:150px; aspect-ratio:16/9;';
  const vid = document.createElement('video');
  vid.id = 'vid-' + peerId;
  vid.autoplay = true;
  vid.playsInline = true;
  if (peerId === 'me') vid.muted = true;
  vid.srcObject = stream;
  vid.style.cssText = 'width:100%; height:100%; object-fit:cover; display:block; background:#020617;';
  const lab = document.createElement('div');
  lab.textContent = label;
  lab.style.cssText = 'position:absolute; bottom:6px; left:6px; font-size:11px; font-weight:700; color:#fff; background:rgba(2,6,23,0.7); padding:2px 7px; border-radius:6px; pointer-events:none; z-index:2;';
  tile.appendChild(vid);
  tile.appendChild(lab);
  callVideoGrid.appendChild(tile);
  callVideoGrid.style.display = 'grid';
}

function removeVideoTile(peerId) {
  const el = document.getElementById('vt-' + peerId);
  if (el) el.remove();
  const tiles = callVideoGrid.querySelectorAll('.call-tile');
  if (tiles.length === 0) callVideoGrid.style.display = 'none';
}

function startCallTimer() {
  let s = 0;
  const el = document.getElementById('callTimerBanner');
  if (!el) return;
  el.textContent = '00:00';
  el.style.display = 'inline';
  if (callTimerInterval) clearInterval(callTimerInterval);
  callTimerInterval = setInterval(() => {
    s++;
    el.textContent = ('0' + Math.floor(s / 60)).slice(-2) + ':' + ('0' + (s % 60)).slice(-2);
  }, 1000);
}
function stopCallTimer() {
  if (callTimerInterval) { clearInterval(callTimerInterval); callTimerInterval = null; }
  const el = document.getElementById('callTimerBanner');
  if (el) el.style.display = 'none';
}

function updateCallBanner() {
  const n = Object.keys(callPeers).length + 1;
  document.getElementById('callPeerCount').textContent = n;
}

function updateMediaButtons() {
  const micBtn = document.getElementById('callMicBtn');
  const vidBtn = document.getElementById('callVidBtn');
  const scrBtn = document.getElementById('callScreenBtn');
  const aTrack = callLocalStream?.getAudioTracks()[0];
  const vTrack = callLocalStream?.getVideoTracks()[0];
  if (micBtn) {
    const on = aTrack ? aTrack.enabled : false;
    micBtn.textContent = on ? '🎙️ Mic On' : '🔇 Mic Off';
    micBtn.style.background = on ? '#020617' : '#7f1d1d';
  }
  if (vidBtn) {
    const on = vTrack ? vTrack.enabled : false;
    vidBtn.textContent = on ? '📷 Cam On' : '🚫 Cam Off';
    vidBtn.style.background = on ? '#020617' : '#7f1d1d';
  }
  if (scrBtn) {
    scrBtn.textContent = callScreenStream ? '🛑 Stop Share' : '🖥️ Share';
    scrBtn.style.background = callScreenStream ? '#1d4ed8' : '#020617';
  }
}

async function requestCallPermissions() {
  try {
    let stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: true });
    } catch (_) {
      // Fallback to audio-only when no camera is attached or camera permission is blocked.
      stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
      callLog('No camera found; joined with audio only');
    }
    callLocalStream = stream;
    addVideoTile('me', myName + ' (You)', stream);
    updateMediaButtons();
    callLog('Media access granted');
    return stream;
  } catch (e) {
    callLog('Permission denied: ' + e);
    notifyUser('⚠ Permission Denied', 'Allow microphone/camera access to join the call');
    throw e;
  }
}

function createPeerConnection(peerId, label) {
  if (callPeers[peerId]?.pc) {
    try { callPeers[peerId].pc.close(); } catch (_) {}
  }
  const pc = new RTCPeerConnection(RTC_CFG);
  const entry = { pc, stream: null, label: label || 'Peer', iceQueue: [] };
  callPeers[peerId] = entry;
  if (callLocalStream) {
    callLocalStream.getTracks().forEach(t => pc.addTrack(t, callLocalStream));
  }
  pc.onicecandidate = (ev) => {
    if (ev.candidate && ws && ws.readyState === 1) {
      ws.send(JSON.stringify({ type: 'call_gc_ice', to: peerId, candidate: ev.candidate }));
    }
  };
  pc.ontrack = (ev) => {
    const stream = ev.streams[0] || new MediaStream([ev.track]);
    entry.stream = stream;
    addVideoTile(peerId, entry.label, stream);
    updateCallBanner();
  };
  pc.onconnectionstatechange = () => {
    callLog(`${entry.label}: ${pc.connectionState}`);
    if (pc.connectionState === 'failed' || pc.connectionState === 'closed') {
      removePeer(peerId);
    }
  };
  return entry;
}

function removePeer(peerId) {
  const entry = callPeers[peerId];
  if (!entry) return;
  if (entry.pc) { try { entry.pc.close(); } catch (_) {} }
  delete callPeers[peerId];
  removeVideoTile(peerId);
  updateCallBanner();
}

function enterActiveCallUI() {
  if (!callActive) {
    callActive = true;
    callBtn.textContent = '📞 End Call';
    callBtn.className = 'btn blue sm';
    callBanner.style.display = 'flex';
    callVideoGrid.style.display = 'grid';
    startCallTimer();
  }
  document.getElementById('incomingCallBanner').style.display = 'none';
  updateCallBanner();
  updateMediaButtons();
}

async function handleIncomingGcOffer(msg) {
  const peerId = msg.from || ('peer-' + Math.floor(Math.random() * 99999));
  const label = msg.from_name || 'Peer';
  if (!callActive) {
    pendingCallOffer = msg;
    document.getElementById('incomingCallText').textContent = `📞 ${label} started a group call`;
    document.getElementById('incomingCallBanner').style.display = 'flex';
    notifyUser('📞 Incoming Group Call', `${label} is calling — click Join Call`);
    return;
  }
  await answerPeerOffer(peerId, label, msg);
}

async function answerPeerOffer(peerId, label, msg) {
  const entry = createPeerConnection(peerId, label);
  try {
    await entry.pc.setRemoteDescription(new RTCSessionDescription({ sdp: msg.sdp, type: msg.sdp_type || 'offer' }));
    for (const c of entry.iceQueue) {
      await entry.pc.addIceCandidate(new RTCIceCandidate(c));
    }
    entry.iceQueue = [];
    const answer = await entry.pc.createAnswer();
    await entry.pc.setLocalDescription(answer);
    if (ws && ws.readyState === 1) {
      ws.send(JSON.stringify({ type: 'call_gc_answer', to: peerId, sdp: answer.sdp, sdp_type: answer.type }));
    }
    callLog(`Connected to ${label}`);
  } catch (e) {
    callLog('Group call join error: ' + e);
  }
}

async function acceptIncomingCall() {
  const msg = pendingCallOffer;
  pendingCallOffer = null;
  document.getElementById('incomingCallBanner').style.display = 'none';
  if (!msg) return;
  try {
    await requestCallPermissions();
  } catch (_) {
    return;
  }
  enterActiveCallUI();
  await answerPeerOffer(msg.from || 'peer', msg.from_name || 'Peer', msg);
}

function dismissIncomingCall() {
  pendingCallOffer = null;
  document.getElementById('incomingCallBanner').style.display = 'none';
}

async function handleGcAnswer(msg) {
  const peerId = msg.from;
  let entry = callPeers[peerId];
  if (!entry) {
    // Match the pending broadcast offer slot if we opened a generic 'broadcast' PC.
    entry = callPeers['broadcast'];
    if (entry) {
      delete callPeers['broadcast'];
      entry.label = msg.from_name || 'Peer';
      callPeers[peerId] = entry;
    }
  }
  if (!entry) return;
  try {
    await entry.pc.setRemoteDescription(new RTCSessionDescription({ sdp: msg.sdp, type: msg.sdp_type || 'answer' }));
    for (const c of entry.iceQueue) {
      await entry.pc.addIceCandidate(new RTCIceCandidate(c));
    }
    entry.iceQueue = [];
    callLog(`Answer received from ${entry.label}`);
  } catch (e) {
    callLog('Answer error: ' + e);
  }
}

async function handleGcIce(msg) {
  if (!msg.candidate) return;
  const entry = callPeers[msg.from] || callPeers['broadcast'];
  if (!entry || !entry.pc) return;
  if (entry.pc.remoteDescription) {
    try { await entry.pc.addIceCandidate(new RTCIceCandidate(msg.candidate)); } catch (_) {}
  } else {
    entry.iceQueue.push(msg.candidate);
  }
}

function handleGcHangup(msg) {
  if (msg.from && callPeers[msg.from]) {
    const label = callPeers[msg.from].label;
    removePeer(msg.from);
    callLog(`${label} left the call`);
  }
  if (pendingCallOffer && pendingCallOffer.from === msg.from) {
    dismissIncomingCall();
  }
}

async function toggleGroupCall() {
  if (callActive) {
    endGroupCall();
    return;
  }
  try {
    await requestCallPermissions();
  } catch (_) {
    return;
  }
  enterActiveCallUI();
  callLog('Group call started');

  const entry = createPeerConnection('broadcast', 'Peer');
  try {
    const offer = await entry.pc.createOffer({ offerToReceiveAudio: true, offerToReceiveVideo: true });
    await entry.pc.setLocalDescription(offer);
    if (ws && ws.readyState === 1) {
      ws.send(JSON.stringify({ type: 'call_gc_offer', sdp: offer.sdp, sdp_type: offer.type }));
    }
    callLog('Group call offer broadcast');
  } catch (e) {
    callLog('Group call start error: ' + e);
  }
}

async function endGroupCall() {
  callActive = false;
  pendingCallOffer = null;
  callBtn.textContent = '📞 Group Call';
  callBtn.className = 'btn blue sm';
  callBanner.style.display = 'none';
  document.getElementById('incomingCallBanner').style.display = 'none';
  callVideoGrid.style.display = 'none';
  stopCallTimer();
  for (const pid of Object.keys(callPeers)) {
    removePeer(pid);
  }
  callPeers = {};
  if (callScreenStream) {
    callScreenStream.getTracks().forEach(t => t.stop());
    callScreenStream = null;
  }
  if (callLocalStream) {
    callLocalStream.getTracks().forEach(t => t.stop());
    callLocalStream = null;
  }
  removeVideoTile('me');
  if (ws && ws.readyState === 1) {
    ws.send(JSON.stringify({ type: 'call_gc_hangup' }));
  }
  callLog('Group call ended');
}

function toggleCallMic() {
  if (!callLocalStream) return;
  const t = callLocalStream.getAudioTracks()[0];
  if (!t) return;
  t.enabled = !t.enabled;
  updateMediaButtons();
  callLog('Mic ' + (t.enabled ? 'on' : 'off'));
}
function toggleCallVideo() {
  if (!callLocalStream) return;
  const t = callLocalStream.getVideoTracks()[0];
  if (!t) return;
  t.enabled = !t.enabled;
  updateMediaButtons();
  callLog('Video ' + (t.enabled ? 'on' : 'off'));
}
async function toggleCallScreen() {
  if (!callActive) return;
  if (callScreenStream) {
    callScreenStream.getTracks().forEach(t => t.stop());
    callScreenStream = null;
    const camTrack = callLocalStream?.getVideoTracks()[0] || null;
    for (const entry of Object.values(callPeers)) {
      const sender = entry.pc?.getSenders().find(s => s.track?.kind === 'video');
      if (sender && camTrack) await sender.replaceTrack(camTrack);
    }
    if (callLocalStream) addVideoTile('me', myName + ' (You)', callLocalStream);
    updateMediaButtons();
    return;
  }
  try {
    callScreenStream = await navigator.mediaDevices.getDisplayMedia({ video: true });
    const scrTrack = callScreenStream.getVideoTracks()[0];
    scrTrack.onended = () => { if (callScreenStream) toggleCallScreen(); };
    for (const entry of Object.values(callPeers)) {
      const sender = entry.pc?.getSenders().find(s => s.track?.kind === 'video');
      if (sender) await sender.replaceTrack(scrTrack);
    }
    addVideoTile('me', myName + ' (Screen)', callScreenStream);
    updateMediaButtons();
  } catch (e) {
    callLog('Screen share cancelled: ' + e);
  }
}

// Alias for banner button
function hangupCall() { endGroupCall(); }

connectWS();
loadFiles();
setTimeout(() => checkUpdates(false), 3000);
setInterval(() => checkUpdates(false), 300000);
</script>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# HTTP & WebSocket Request Handler
# ---------------------------------------------------------------------------

class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def make_handler(state: DuckState):
    class DuckHandler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):
            pass  # Quiet standard logs; we log important events to GUI

        def _send_json(self, obj, status=200):
            body = json.dumps(obj).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            # Never let a browser cache API responses: a stale /api/update/check made
            # the dashboard keep reporting "up to date" long after a new release shipped.
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.end_headers()
            self.wfile.write(body)

        def _read_json(self):
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) if length > 0 else b"{}"
            return json.loads(raw.decode("utf-8", errors="ignore"))

        def _is_tunnel_request(self):
            host = (self.headers.get("Host") or "").lower()
            if self.headers.get("Cf-Connecting-Ip") or self.headers.get("Cf-Ray"):
                return True
            return any(s in host for s in (".trycloudflare.com", ".lhr.life", ".ngrok"))

        def _get_client_ip(self):
            cf_ip = (self.headers.get("Cf-Connecting-Ip") or "").strip()
            if cf_ip:
                return cf_ip
            xff = (self.headers.get("X-Forwarded-For") or "").split(",")[0].strip()
            if xff:
                return xff
            raw_ip = self.client_address[0]
            if raw_ip in ("127.0.0.1", "::1"):
                return get_primary_ip()
            return raw_ip

        def _is_authorized(self):
            if not self._is_tunnel_request():
                return True
            return state.tunnel.verify_cookie(self.headers.get("Cookie", ""))

        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path

            if path == "/api/health":
                self._send_json({"ok": True, "app": APP_NAME, "host": socket.gethostname(), "ip": get_primary_ip(), "port": state.port, "tunnel": state.tunnel.state_dict()})
                return

            if not self._is_authorized():
                if path == "/" or path == "/index.html":
                    body = OTP_GATE_HTML.encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                else:
                    self.send_error(401, "OTP Required")
                return

            # WebSocket Upgrade
            if path == "/ws" and self.headers.get("Upgrade", "").lower() == "websocket":
                self._handle_websocket()
                return

            if path == "/" or path == "/index.html":
                body = DASHBOARD_HTML.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return

            if path == "/api/files":
                items = []
                for p in sorted(FILES_DIR.iterdir(), key=lambda x: x.stat().st_mtime, reverse=True):
                    if p.is_file():
                        st = p.stat()
                        items.append({
                            "name": p.name,
                            "size": st.st_size,
                            "mtime": datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M"),
                        })
                self._send_json(items)
                return

            if path.startswith("/api/files/"):
                fname = urllib.parse.unquote(path[len("/api/files/"):])
                fname = os.path.basename(fname)
                fpath = FILES_DIR / fname
                if not fpath.is_file():
                    self.send_error(404, "File not found")
                    return
                self._serve_file_range(fpath, parsed.query)
                return

            if path == "/api/zip":
                import tempfile
                tmp_zip = tempfile.NamedTemporaryFile(delete=False, suffix=".zip")
                tmp_zip_path = Path(tmp_zip.name)
                tmp_zip.close()
                try:
                    with zipfile.ZipFile(tmp_zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
                        for p in FILES_DIR.iterdir():
                            if p.is_file():
                                zf.write(p, arcname=p.name)
                    zsize = tmp_zip_path.stat().st_size
                    self.send_response(200)
                    self.send_header("Content-Type", "application/zip")
                    self.send_header("Content-Disposition", 'attachment; filename="duck_files.zip"')
                    self.send_header("Content-Length", str(zsize))
                    self.end_headers()
                    with open(tmp_zip_path, "rb") as zf_in:
                        while True:
                            chunk = zf_in.read(65536)
                            if not chunk:
                                break
                            self.wfile.write(chunk)
                finally:
                    tmp_zip_path.unlink(missing_ok=True)
                return

            if path == "/api/screen.png":
                qs = urllib.parse.parse_qs(parsed.query)
                scale = float(qs.get("scale", ["0.65"])[0])
                scale = max(0.25, min(1.0, scale))
                png = capture_screen_png(scale=scale)
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(png)))
                self.end_headers()
                self.wfile.write(png)
                return

            if path == "/api/peers":
                self._send_json(state.discovery.get_peers())
                return

            if path == "/api/update/check":
                self._send_json(state.check_github_update())
                return

            if path == "/api/scan":
                self._send_json(self._scan_lan())
                return

            if path == "/api/rdp_file":
                qs = urllib.parse.parse_qs(parsed.query)
                ip = qs.get("ip", [""])[0]
                user = qs.get("user", [""])[0]
                rdp = f"full address:s:{ip}\nprompt for credentials:i:1\n"
                if user:
                    rdp += f"username:s:{user}\n"
                data = rdp.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/x-rdp")
                self.send_header("Content-Disposition", f'attachment; filename="{ip or "device"}.rdp"')
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return

            self.send_error(404)

        def do_DELETE(self):
            if not self._is_authorized():
                self.send_error(401, "OTP Required")
                return
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path.startswith("/api/files/"):
                fname = os.path.basename(urllib.parse.unquote(parsed.path[len("/api/files/"):]))
                fpath = FILES_DIR / fname
                if fpath.is_file():
                    fpath.unlink()
                    state.broadcast({"type": "files_updated"})
                    self._send_json({"deleted": fname})
                    return
            self.send_error(404)

        def do_POST(self):
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path

            if path == "/api/otp/verify":
                data = self._read_json()
                otp = str(data.get("otp", "")).strip()
                if state.tunnel.active and otp == state.tunnel.otp:
                    tok = state.tunnel.session_token()
                    body = json.dumps({"ok": True}).encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Set-Cookie", f"duck_session={tok}; Path=/; HttpOnly; SameSite=Lax")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                else:
                    self._send_json({"ok": False, "error": "Invalid OTP"}, status=401)
                return

            if not self._is_authorized():
                self.send_error(401, "OTP Required")
                return

            if path == "/api/tunnel/start":
                state.tunnel.start(state.port)
                self._send_json(state.tunnel.state_dict())
                return

            if path == "/api/tunnel/stop":
                state.tunnel.stop()
                self._send_json(state.tunnel.state_dict())
                return

            if path == "/api/tunnel/rotate_otp":
                state.tunnel.rotate_otp()
                self._send_json(state.tunnel.state_dict())
                return

            if path == "/api/update/apply":
                try:
                    self._send_json(state.apply_github_update())
                except Exception as e:
                    self._send_json({"ok": False, "error": str(e)}, status=500)
                return

            if path == "/api/chat/clear":
                data = self._read_json()
                state.clear_chat(str(data.get("sender", self.client_address[0]))[:32])
                self._send_json({"ok": True})
                return

            if path == "/api/upload":
                raw_name = urllib.parse.unquote(self.headers.get("X-Filename", f"upload_{int(time.time())}.bin"))
                fname = os.path.basename(raw_name) or f"upload_{int(time.time())}.bin"
                try:
                    length = max(0, int(self.headers.get("Content-Length", 0)))
                except ValueError:
                    self._send_json({"ok": False, "error": "Invalid Content-Length"}, status=400)
                    return
                dest = FILES_DIR / fname
                remaining = length
                with open(dest, "wb") as f:
                    while remaining > 0:
                        chunk = self.rfile.read(min(65536, remaining))
                        if not chunk:
                            break
                        f.write(chunk)
                        remaining -= len(chunk)
                state.log(f"File uploaded: {fname} ({length} bytes) from {self.client_address[0]}")
                state.broadcast({"type": "files_updated", "name": fname, "size": length, "sender": self.client_address[0]})
                self._send_json({"ok": True, "name": fname, "size": length})
                return

            if path == "/api/screen/input":
                data = self._read_json()
                send_remote_input(data)
                self._send_json({"ok": True})
                return

            if path == "/api/exec":
                data = self._read_json()
                shell = data.get("shell", "powershell")
                cmd = data.get("cmd", "")
                try:
                    if os.name == "nt":
                        args = ["powershell", "-NoProfile", "-Command", cmd] if shell == "powershell" else ["cmd", "/c", cmd]
                        res = subprocess.run(args, capture_output=True, text=True, timeout=30, creationflags=0x08000000)
                    else:
                        res = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, timeout=30)
                    out = (res.stdout or "") + (res.stderr or "")
                except Exception as e:
                    out = str(e)
                self._send_json({"output": out})
                return

            if path == "/api/ftp/list":
                data = self._read_json()
                try:
                    ftp = ftplib.FTP()
                    ftp.connect(data.get("host", ""), int(data.get("port", 21)), timeout=6)
                    ftp.login(data.get("user", "anonymous"), data.get("password", ""))
                    if data.get("path"):
                        ftp.cwd(data["path"])
                    lines = []
                    ftp.retrlines("LIST", lines.append)
                    ftp.quit()
                    self._send_json({"lines": lines})
                except Exception as e:
                    self._send_json({"error": str(e)}, status=400)
                return

            if path == "/api/net/udp":
                data = self._read_json()
                try:
                    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                    s.sendto(str(data.get("data", "")).encode("utf-8"), (data.get("host", ""), int(data.get("port", 0))))
                    s.close()
                    self._send_json({"status": "Sent UDP datagram"})
                except Exception as e:
                    self._send_json({"error": str(e)}, status=400)
                return

            if path == "/api/http_req":
                data = self._read_json()
                try:
                    req = urllib.request.Request(
                        data.get("url", ""),
                        data=data.get("body").encode("utf-8") if data.get("body") else None,
                        method=data.get("method", "GET"),
                    )
                    with urllib.request.urlopen(req, timeout=10) as resp:
                        body = resp.read(200000).decode("utf-8", errors="replace")
                        self._send_json({"status": resp.status, "body": body})
                except Exception as e:
                    self._send_json({"error": str(e)}, status=400)
                return

            if path == "/api/launch_tool":
                data = self._read_json()
                ip = data.get("ip", "")
                tool = data.get("tool", "")
                if ip:
                    if os.name == "nt":
                        if tool == "rdp":
                            subprocess.Popen(["mstsc", f"/v:{ip}"])
                        elif tool == "smb":
                            subprocess.Popen(["explorer", f"\\\\{ip}"])
                    else:
                        if tool == "rdp":
                            for cmd in (["xfreerdp", f"/v:{ip}"], ["remmina", "-c", f"rdp://{ip}"]):
                                if shutil.which(cmd[0]):
                                    subprocess.Popen(cmd)
                                    break
                        elif tool == "smb" and shutil.which("xdg-open"):
                            subprocess.Popen(["xdg-open", f"smb://{ip}/"])
                self._send_json({"ok": True})
                return

            self.send_error(404)

        def _serve_file_range(self, fpath: Path, query: str):
            qs = urllib.parse.parse_qs(query)
            force_dl = "download" in qs
            size = fpath.stat().st_size
            ctype, _ = mimetypes.guess_type(str(fpath))
            ctype = ctype or "application/octet-stream"

            rng = self.headers.get("Range")
            start, end = 0, max(0, size - 1)
            status = 200
            if rng and rng.startswith("bytes=") and size > 0:
                try:
                    parts = rng[6:].split("-")
                    if parts[0]:
                        start = max(0, min(size - 1, int(parts[0])))
                    if len(parts) > 1 and parts[1]:
                        end = max(start, min(size - 1, int(parts[1])))
                    status = 206
                except ValueError:
                    start, end, status = 0, size - 1, 200

            length = 0 if size == 0 else max(0, end - start + 1)
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(length))
            if status == 206:
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            if force_dl:
                self.send_header("Content-Disposition", f'attachment; filename="{fpath.name}"')
            self.end_headers()

            with open(fpath, "rb") as f:
                f.seek(start)
                rem = length
                while rem > 0:
                    chunk = f.read(min(65536, rem))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    rem -= len(chunk)

        def _scan_lan(self):
            devices = {}
            try:
                if os.name == "nt":
                    out = subprocess.check_output(["arp", "-a"], text=True, creationflags=0x08000000)
                    for line in out.splitlines():
                        m = re.search(r"(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F:-]{11,17})\s+(\w+)", line)
                        if m:
                            ip, mac, _ = m.groups()
                            if not ip.endswith(".255") and not ip.startswith("224.") and not ip.startswith("239."):
                                devices[ip] = {"ip": ip, "mac": mac, "ports": []}
                else:
                    if Path("/proc/net/arp").exists():
                        for line in Path("/proc/net/arp").read_text(errors="ignore").splitlines()[1:]:
                            parts = line.split()
                            if len(parts) >= 4 and parts[3] != "00:00:00:00:00:00":
                                devices[parts[0]] = {"ip": parts[0], "mac": parts[3], "ports": []}
                    if not devices and shutil.which("ip"):
                        out = subprocess.check_output(["ip", "neigh", "show"], text=True)
                        for line in out.splitlines():
                            m = re.search(r"^(\d+\.\d+\.\d+\.\d+).*lladdr\s+([0-9a-fA-F:]+)", line)
                            if m:
                                devices[m.group(1)] = {"ip": m.group(1), "mac": m.group(2), "ports": []}
            except Exception:
                pass

            my_ip = get_primary_ip()
            if my_ip not in devices:
                devices[my_ip] = {"ip": my_ip, "mac": "This Device", "ports": []}

            probe_ports = [(21, "FTP"), (22, "SSH"), (23, "Telnet"), (80, "HTTP"), (443, "HTTPS"), (445, "SMB"), (3389, "RDP"), (5900, "VNC"), (8080, "HTTP-Alt")]
            lock = threading.Lock()

            def check_ip(ip):
                found = []
                for port, label in probe_ports:
                    try:
                        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                        s.settimeout(0.25)
                        if s.connect_ex((ip, port)) == 0:
                            found.append(f"{port}/{label}")
                        s.close()
                    except Exception:
                        pass
                hname = resolve_hostname(ip)
                with lock:
                    devices[ip]["ports"] = found
                    devices[ip]["hostname"] = hname

            threads = [threading.Thread(target=check_ip, args=(ip,)) for ip in list(devices.keys())[:40]]
            for t in threads:
                t.start()
            for t in threads:
                t.join(timeout=3.0)
            return list(devices.values())

        def _handle_websocket(self):
            key = self.headers.get("Sec-WebSocket-Key", "")
            accept = base64.b64encode(hashlib.sha1((key + WS_MAGIC).encode("utf-8")).digest()).decode("ascii")
            self.send_response(101, "Switching Protocols")
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", accept)
            self.end_headers()

            cid = str(uuid.uuid4())[:8]
            ip = self._get_client_ip()
            # Real device name: reverse DNS / NetBIOS / mDNS PTR.
            host = ""
            try:
                host = resolve_hostname(ip)
            except Exception:
                host = ""
            client = WebSocketClient(self.connection, self.client_address, cid, host or f"Device-{cid[:4]}", ip)
            client.hostname = host
            with state.clients_lock:
                state.clients[cid] = client
                users = [{"id": c.id, "name": c.name, "ip": c.ip, "hostname": getattr(c, "hostname", "") or c.name} for c in state.clients.values() if not c.closed]

            client.send_json({
                "type": "init",
                "host": socket.gethostname(),
                "ip": get_primary_ip(),
                "port": state.port,
                "your_name": client.name,
                "your_ip": ip,
                "messages": state.messages[-100:],
                "clipboard": state.clipboard,
                "users": users,
                "tunnel": state.tunnel.state_dict(),
                "update": state.latest_update,
            })
            state.broadcast_presence()
            state.broadcast({"type": "device_joined", "ip": ip, "name": client.name})
            state.log(f"Device connected: {client.name} ({ip})")

            try:
                while not client.closed:
                    opcode, data = client.recv_frame()
                    if opcode == 0x8:
                        break
                    if opcode == 0x9:
                        client.send_frame(data, opcode=0xA)
                        continue
                    if opcode != 0x1:
                        continue
                    msg = json.loads(data.decode("utf-8", errors="ignore"))
                    mtype = msg.get("type")

                    if mtype == "hello":
                        req_name = str(msg.get("name", "")).strip()[:32]
                        # Keep the server-resolved real hostname when the browser only sends
                        # its auto-generated Device-XXX placeholder.
                        if req_name and not (req_name.startswith("Device-") and getattr(client, "hostname", "")):
                            client.name = req_name
                        h = str(msg.get("hostname", ""))[:48]
                        if h:
                            client.hostname = h
                        state.broadcast_presence()
                    elif mtype == "chat":
                        state.add_message({
                            "id": str(uuid.uuid4())[:8],
                            "sender": str(msg.get("sender", client.name))[:32],
                            "ip": ip,
                            "text": str(msg.get("text", "")),
                            "attachments": msg.get("attachments", []),
                            "ts": datetime.now().strftime("%H:%M:%S"),
                        })
                    elif mtype == "clipboard":
                        state.set_clipboard(str(msg.get("text", "")), str(msg.get("sender", client.name)))
                    elif mtype == "tcp_connect":
                        self._ws_tcp_connect(client, msg.get("host", ""), int(msg.get("port", 23)))
                    elif mtype == "tcp_send":
                        if client.tcp_bridge:
                            client.tcp_bridge.sendall(str(msg.get("data", "")).encode("utf-8"))
                    elif mtype == "tcp_close":
                        if client.tcp_bridge:
                            client.tcp_bridge.close()
                            client.tcp_bridge = None
                    elif mtype == "ssh_connect":
                        self._ws_ssh_connect(client, msg)
                    elif mtype == "ssh_send":
                        if client.ssh_chan:
                            client.ssh_chan.send(str(msg.get("data", "")))
                    elif mtype == "ssh_close":
                        if client.ssh_client:
                            client.ssh_client.close()
                            client.ssh_client = None
                            client.ssh_chan = None
                    elif mtype in ("call_offer", "call_answer", "call_ice", "call_hangup",
                                   "call_gc_offer", "call_gc_answer", "call_gc_ice", "call_gc_hangup"):
                        self._ws_call_signal(client, msg)
            except Exception:
                pass
            finally:
                client.cleanup()
                with state.clients_lock:
                    state.clients.pop(cid, None)
                state.broadcast_presence()

        def _ws_tcp_connect(self, client: WebSocketClient, host: str, port: int):
            try:
                if client.tcp_bridge:
                    client.tcp_bridge.close()
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(5)
                s.connect((host, port))
                s.settimeout(None)
                client.tcp_bridge = s
                client.send_json({"type": "tcp_out", "data": f"Connected to {host}:{port}\n"})

                def reader():
                    try:
                        while not client.closed and client.tcp_bridge:
                            chunk = s.recv(4096)
                            if not chunk:
                                break
                            client.send_json({"type": "tcp_out", "data": chunk.decode("utf-8", errors="replace")})
                    except Exception:
                        pass
                    client.send_json({"type": "tcp_out", "data": "\n[TCP Disconnected]\n"})

                threading.Thread(target=reader, daemon=True).start()
            except Exception as e:
                client.send_json({"type": "tcp_out", "data": f"Connection failed: {e}\n"})

        def _ws_ssh_connect(self, client: WebSocketClient, msg: dict):
            if not HAS_PARAMIKO:
                client.send_json({"type": "ssh_out", "data": "Paramiko is not installed on host.\n"})
                return
            try:
                ssh = paramiko.SSHClient()
                ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                ssh.connect(
                    hostname=msg.get("host", ""),
                    port=int(msg.get("port", 22)),
                    username=msg.get("user", ""),
                    password=msg.get("password", ""),
                    timeout=8,
                )
                chan = ssh.invoke_shell()
                client.ssh_client = ssh
                client.ssh_chan = chan
                client.send_json({"type": "ssh_out", "data": f"SSH Connected to {msg.get('host')}\n"})

                def reader():
                    try:
                        while not client.closed and client.ssh_chan:
                            if chan.recv_ready():
                                data = chan.recv(4096).decode("utf-8", errors="replace")
                                client.send_json({"type": "ssh_out", "data": data})
                            else:
                                time.sleep(0.05)
                    except Exception:
                        pass

                threading.Thread(target=reader, daemon=True).start()
            except Exception as e:
                client.send_json({"type": "ssh_out", "data": f"SSH Error: {e}\n"})

        def _ws_call_signal(self, client: WebSocketClient, msg: dict):
            """Relay WebRTC call signaling (offer/answer/ICE/hangup) to all other peers."""
            relay = {
                "type": msg.get("type", "call_signal"),
                "from": client.id,
                "from_name": client.name,
                "to": msg.get("to", ""),
                "sdp": msg.get("sdp", ""),
                "sdp_type": msg.get("sdp_type", ""),
                "candidate": msg.get("candidate", None),
                "ts": datetime.now().strftime("%H:%M:%S"),
            }
            with state.clients_lock:
                targets = [c for c in state.clients.values() if not c.closed]
            for c in targets:
                if c.id == client.id:
                    continue
                if relay["to"] and c.id != relay["to"]:
                    continue
                try:
                    c.send_json(relay)
                except Exception:
                    pass
            state.log(f"Call signal {relay['type']} from {client.name} -> {relay['to'] or 'broadcast'}")

    return DuckHandler

# ---------------------------------------------------------------------------
# Server Lifecycle & Tkinter GUI Control Center
# ---------------------------------------------------------------------------

def start_http_server(state: DuckState):
    handler = make_handler(state)
    for port in (80, 8080, 8888):
        try:
            srv = ThreadingHTTPServer(("0.0.0.0", port), handler)
            state.port = port
            state.log(f"HTTP + WebSocket server listening on 0.0.0.0:{port}")
            t = threading.Thread(target=srv.serve_forever, daemon=True)
            t.start()
            return srv
        except OSError as e:
            state.log(f"Port {port} unavailable ({e}), trying next...")
    raise RuntimeError("No available HTTP port found")


def run_gui_app():
    log_queue = queue.Queue()

    def log_fn(msg):
        ts = datetime.now().strftime("%H:%M:%S")
        log_queue.put(f"[{ts}] {msg}")

    state = DuckState(log_fn)
    srv = start_http_server(state)
    state.discovery.start()

    lan_ip = get_primary_ip()
    port_suffix = "" if state.port == 80 else f":{state.port}"
    duck_url = f"http://duck{port_suffix}"
    ip_url = f"http://{lan_ip}{port_suffix}"

    hosts_ok = check_duck_hosts_configured()
    if not hosts_ok and is_admin():
        ok, msg = register_hosts_and_firewall()
        log_fn(msg)
        hosts_ok = ok

    open_target = duck_url if hosts_ok else f"http://127.0.0.1{port_suffix}"

    # Open browser automatically on launch (unless --no-browser passed)
    if "--no-browser" not in sys.argv:
        threading.Timer(0.6, lambda: webbrowser.open(open_target)).start()

    if not HAS_TK or "--headless" in sys.argv or (os.name != "nt" and not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY") and sys.platform != "darwin"):
        log_fn(f"Running headless. Open {duck_url} or {ip_url}")
        try:
            while True:
                while not log_queue.empty():
                    print(log_queue.get_nowait())
                time.sleep(0.5)
        except KeyboardInterrupt:
            srv.shutdown()
        return

    root = tk.Tk()
    root.title(f"Duck Intranet Hub v{APP_VERSION}")
    root.geometry("620x460")
    root.configure(bg="#020617")

    style = ttk.Style()
    style.theme_use("clam")

    header = tk.Frame(root, bg="#0f172a", pady=12, padx=16)
    header.pack(fill="x")
    tk.Label(header, text="🦆 DUCK INTRANET HUB", font=("Consolas", 15, "bold"), fg="#00f6ff", bg="#0f172a").pack(side="left")
    tk.Label(header, text=f"● ONLINE (Port {state.port})", font=("Consolas", 10, "bold"), fg="#10b981", bg="#0f172a").pack(side="right")

    info = tk.Frame(root, bg="#020617", padx=16, pady=10)
    info.pack(fill="x")
    tk.Label(info, text=f"Browser URL:  {duck_url}   (or {ip_url})", font=("Consolas", 11), fg="#e6edf7", bg="#020617").pack(anchor="w")
    hosts_lbl = tk.Label(
        info,
        text=("✓ Hostname 'duck' is registered in Windows hosts" if hosts_ok else "⚠ Click 'Register duck Hostname' once so http://duck always resolves locally"),
        font=("Consolas", 9),
        fg=("#10b981" if hosts_ok else "#00f6ff"),
        bg="#020617",
    )
    hosts_lbl.pack(anchor="w", pady=(4, 0))

    btns = tk.Frame(root, bg="#020617", padx=16, pady=6)
    btns.pack(fill="x")

    def open_dash():
        webbrowser.open(duck_url if check_duck_hosts_configured() else ip_url)

    def do_register():
        if is_admin():
            ok, msg = register_hosts_and_firewall()
            log_fn(msg)
        else:
            elevate_register_hosts()
            root.after(1500, lambda: hosts_lbl.config(
                text=("✓ Hostname 'duck' is registered in Windows hosts" if check_duck_hosts_configured() else "⚠ Elevation cancelled or pending"),
                fg=("#10b981" if check_duck_hosts_configured() else "#00f6ff")
            ))

    def copy_url():
        root.clipboard_clear()
        root.clipboard_append(ip_url)
        log_fn(f"Copied {ip_url} to clipboard")

    def open_folder():
        if os.name == "nt":
            os.startfile(str(FILES_DIR))
        elif sys.platform == "darwin":
            subprocess.Popen(["open", str(FILES_DIR)])
        elif shutil.which("xdg-open"):
            subprocess.Popen(["xdg-open", str(FILES_DIR)])

    tunnel_lbl = tk.Label(info, text="Internet Tunnel: Offline", font=("Consolas", 9), fg="#8b9bb4", bg="#020617")
    tunnel_lbl.pack(anchor="w", pady=(2, 0))

    def toggle_gui_tunnel():
        if state.tunnel.active:
            state.tunnel.stop()
        else:
            state.tunnel.start(state.port)

    tk.Button(btns, text="🌐 Open Dashboard", command=open_dash, bg="#00f6ff", fg="#020617", font=("Consolas", 10, "bold"), relief="flat", padx=12, pady=6).pack(side="left", padx=(0, 8))
    tk.Button(btns, text="☁️ Internet Tunnel", command=toggle_gui_tunnel, bg="#10b981", fg="#020617", font=("Consolas", 10, "bold"), relief="flat", padx=10, pady=6).pack(side="left", padx=(0, 8))
    tk.Button(btns, text="🔧 Register 'duck'", command=do_register, bg="#3b82f6", fg="#ffffff", font=("Consolas", 10), relief="flat", padx=10, pady=6).pack(side="left", padx=(0, 8))
    tk.Button(btns, text="📋 Copy LAN", command=copy_url, bg="#1e293b", fg="#e6edf7", font=("Consolas", 10), relief="flat", padx=8, pady=6).pack(side="left", padx=(0, 8))
    tk.Button(btns, text="📁 Files", command=open_folder, bg="#1e293b", fg="#e6edf7", font=("Consolas", 10), relief="flat", padx=8, pady=6).pack(side="left")

    log_box = scrolledtext.ScrolledText(root, bg="#060911", fg="#d1fae5", font=("Consolas", 9), relief="flat", padx=10, pady=10)
    log_box.pack(fill="both", expand=True, padx=16, pady=(6, 14))

    def poll_logs():
        while not log_queue.empty():
            line = log_queue.get_nowait()
            log_box.insert("end", line + "\n")
            log_box.see("end")
        if state.tunnel.active:
            t_txt = f"Internet LIVE: {state.tunnel.url}  |  OTP: {state.tunnel.otp}" if state.tunnel.url else f"Internet Tunnel: {state.tunnel.status}..."
            tunnel_lbl.config(text=t_txt, fg="#10b981")
        else:
            tunnel_lbl.config(text="Internet Tunnel: Offline", fg="#8b9bb4")
        root.after(250, poll_logs)

    def on_close():
        state.tunnel.stop()
        state.discovery.stop()
        srv.shutdown()
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", on_close)
    poll_logs()
    root.mainloop()


if __name__ == "__main__":
    if "--register-hosts" in sys.argv:
        ok, msg = register_hosts_and_firewall()
        sys.exit(0 if ok else 1)
    run_gui_app()
