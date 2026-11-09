#!/usr/bin/env python3
"""Servidor local do Monitor — CPU, RAM e GPU em tempo real.

Uso:
    python3 server.py            # http://localhost:8787
    PORT=9000 python3 server.py

Dependência única: psutil. GPU AMD é lida por sysfs; NVIDIA por nvidia-smi.
"""

from __future__ import annotations

import json
import mimetypes
import os
import re
import shutil
import socket
import subprocess
import threading
import time
from glob import glob
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import psutil

ROOT = Path(__file__).resolve().parent
PORT = int(os.environ.get("PORT", "8787"))
HOST = os.environ.get("HOST", "0.0.0.0")
LOCK = threading.Lock()
STATE: dict = {}


def read_text(path: Path | str | None) -> str | None:
    if not path:
        return None
    try:
        return Path(path).read_text().strip()
    except OSError:
        return None


def read_int(path: Path | str | None, scale: float = 1.0) -> float | None:
    raw = read_text(path)
    if raw is None:
        return None
    try:
        return int(raw) / scale
    except ValueError:
        return None


class GpuReader:
    """GPU AMD (amdgpu/sysfs), NVIDIA (nvidia-smi) ou ausente."""

    def __init__(self) -> None:
        self.kind: str | None = None
        self.name = "GPU"
        self._files: dict[str, Path] = {}
        self._nvidia = shutil.which("nvidia-smi")

        cards = sorted(glob("/sys/class/drm/card[0-9]*/device/gpu_busy_percent"))
        if cards:
            device = Path(cards[0]).parent
            self.kind = "sysfs"
            self.name = self._amd_name(device)
            self._files = {
                "busy": device / "gpu_busy_percent",
                "vram_used": device / "mem_info_vram_used",
                "vram_total": device / "mem_info_vram_total",
                "sclk": device / "pp_dpm_sclk",
            }
            hwmons = sorted(glob(str(device / "hwmon" / "hwmon*")))
            if hwmons:
                hw = Path(hwmons[0])
                self._files["temp"] = hw / "temp1_input"
                self._files["power"] = hw / "power1_average"
        elif self._nvidia:
            self.kind = "nvidia"
            self.name = self._nvidia_name() or "NVIDIA GPU"

    @staticmethod
    def _amd_name(device: Path) -> str:
        try:
            pci = device.resolve().name  # 0000:06:00.0
            out = subprocess.run(
                ["lspci", "-s", pci, "-mm"],
                capture_output=True, text=True, timeout=2,
            ).stdout
            fields = re.findall(r'"([^"]*)"', out)
            # lspci -mm: slot "classe" "fabricante" "dispositivo" ...
            if len(fields) >= 3:
                name = fields[2]
                name = re.sub(r"^Navi \d+ \[(.+)\]$", r"\1", name)
                return name.replace("Advanced Micro Devices, Inc. [AMD/ATI]", "AMD").strip()
        except (OSError, subprocess.SubprocessError):
            pass
        return "AMD Radeon"

    def _nvidia_name(self) -> str | None:
        try:
            out = subprocess.run(
                [self._nvidia, "--query-gpu=name", "--format=csv,noheader"],
                capture_output=True, text=True, timeout=2,
            ).stdout.strip()
            return out.splitlines()[0] if out else None
        except (OSError, subprocess.SubprocessError):
            return None

    def _nvidia_read(self) -> dict | None:
        try:
            out = subprocess.run(
                [self._nvidia,
                 "--query-gpu=utilization.gpu,memory.used,memory.total,"
                 "temperature.gpu,power.draw,clocks.gr",
                 "--format=csv,noheader,nounits"],
                capture_output=True, text=True, timeout=2,
            ).stdout.strip()
            if not out:
                return None
            busy, used, total, temp, power, clock = [
                float(v.strip()) for v in out.splitlines()[0].split(",")
            ]
            return {
                "usage": busy,
                "vram_used": used * 1024 * 1024,
                "vram_total": total * 1024 * 1024,
                "temp": temp,
                "power": power,
                "clock": clock,
            }
        except (OSError, subprocess.SubprocessError, ValueError):
            return None

    def read(self) -> dict | None:
        if self.kind == "nvidia":
            data = self._nvidia_read()
            if data:
                data["name"] = self.name
            return data

        if self.kind != "sysfs":
            return None

        data = {
            "name": self.name,
            "usage": read_int(self._files.get("busy")),
            "vram_used": read_int(self._files.get("vram_used")),
            "vram_total": read_int(self._files.get("vram_total")),
            "temp": read_int(self._files.get("temp"), 1000),
            "power": read_int(self._files.get("power"), 1_000_000),
            "clock": None,
        }
        sclk = read_text(self._files.get("sclk"))
        if sclk:
            for line in sclk.splitlines():
                if "*" in line:
                    match = re.search(r"(\d+)\s*Mhz", line, re.I)
                    if match:
                        data["clock"] = float(match.group(1))
        return data


GPU = GpuReader()

CPU_MODEL = "CPU"
try:
    for line in Path("/proc/cpuinfo").read_text().splitlines():
        if line.lower().startswith("model name"):
            CPU_MODEL = line.split(":", 1)[1].strip()
            break
except OSError:
    pass

OS_NAME = "Linux"
try:
    pretty = Path("/etc/os-release").read_text()
    match = re.search(r'^PRETTY_NAME="?([^"\n]+)"?', pretty, re.M)
    if match:
        OS_NAME = match.group(1)
except OSError:
    pass


def cpu_temperature() -> float | None:
    try:
        groups = psutil.sensors_temperatures()
    except (AttributeError, OSError):
        return None
    if not groups:
        return None
    for key in ("coretemp", "k10temp", "zenpower", "cpu_thermal", "acpitz"):
        entries = groups.get(key) or []
        if not entries:
            continue
        for entry in entries:
            if entry.label and "package" in entry.label.lower():
                return round(entry.current, 1)
        values = [e.current for e in entries if e.current is not None]
        if values:
            return round(max(values), 1)
    return None


def top_processes(limit: int = 8) -> list[dict]:
    rows = []
    for proc in psutil.process_iter(
        ["pid", "name", "cpu_percent", "memory_info", "username"]
    ):
        try:
            info = proc.info
            meminfo = info.get("memory_info")
            rows.append({
                "pid": info["pid"],
                "name": (info.get("name") or "?").removesuffix(".exe"),
                "cpu": round(info.get("cpu_percent") or 0.0, 1),
                "mem": meminfo.rss if meminfo else 0,
                "user": (info.get("username") or "").split("\\")[-1],
            })
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    rows.sort(key=lambda r: (r["cpu"], r["mem"]), reverse=True)
    return rows[:limit]


def take_snapshot() -> dict:
    vm = psutil.virtual_memory()
    swap = psutil.swap_memory()
    freq = psutil.cpu_freq()
    try:
        load = list(os.getloadavg())
    except OSError:
        load = [0.0, 0.0, 0.0]

    return {
        "ts": time.time(),
        "host": socket.gethostname(),
        "os": OS_NAME,
        "kernel": os.uname().release,
        "uptime": max(0.0, time.time() - psutil.boot_time()),
        "cpu": {
            "usage": round(psutil.cpu_percent(interval=None), 1),
            "cores": [round(v, 1) for v in psutil.cpu_percent(percpu=True, interval=None)],
            "count": psutil.cpu_count(logical=True) or 1,
            "physical": psutil.cpu_count(logical=False) or 1,
            "freq": round(freq.current, 0) if freq else None,
            "freq_max": round(freq.max, 0) if freq and freq.max else None,
            "temp": cpu_temperature(),
            "load": [round(v, 2) for v in load],
            "model": CPU_MODEL,
        },
        "ram": {
            "total": vm.total,
            "used": vm.total - vm.available,
            "available": vm.available,
            "free": vm.free,
            "percent": round(vm.percent, 1),
            "swap_total": swap.total,
            "swap_used": swap.used,
        },
        "gpu": GPU.read(),
        "procs": top_processes(),
        "proc_count": len(psutil.pids()),
    }


def sampler() -> None:
    # Primeiro passo "aquece" as médias do psutil (a primeira leitura é 0).
    psutil.cpu_percent(interval=None)
    psutil.cpu_percent(percpu=True, interval=None)
    for proc in psutil.process_iter(["cpu_percent"]):
        pass

    while True:
        started = time.time()
        try:
            snap = take_snapshot()
            with LOCK:
                STATE.clear()
                STATE.update(snap)
        except Exception as exc:  # mantém o servidor vivo
            print(f"[monitor] erro na amostra: {exc}")
        elapsed = time.time() - started
        time.sleep(max(0.05, 1.0 - elapsed))


class Handler(BaseHTTPRequestHandler):
    server_version = "Monitor/1.0"

    def log_message(self, *args) -> None:  # sem spam de polling
        pass

    def send_body(self, body: bytes, ctype: str, cache: str = "no-store") -> None:
        try:
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", cache)
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]

        if path in ("/", "/index.html"):
            self.serve_file(ROOT / "index.html")
            return

        if path == "/api/stats":
            with LOCK:
                body = json.dumps(STATE, separators=(",", ":")).encode()
            self.send_body(body, "application/json; charset=utf-8")
            return

        target = (ROOT / path.lstrip("/")).resolve()
        if ROOT in target.parents and target.is_file():
            self.serve_file(target)
        else:
            self.send_body(b"nao encontrado", "text/plain; charset=utf-8")

    def serve_file(self, target: Path) -> None:
        try:
            body = target.read_bytes()
        except OSError:
            self.send_body(b"nao encontrado", "text/plain; charset=utf-8")
            return
        ctype = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        if ctype.startswith("text/") or ctype == "application/javascript":
            ctype += "; charset=utf-8"
        self.send_body(body, ctype)


def main() -> None:
    threading.Thread(target=sampler, daemon=True).start()
    time.sleep(0.35)

    server = ThreadingHTTPServer((HOST, PORT), Handler)
    gpu = f"{GPU.name} ({GPU.kind})" if GPU.kind else "nenhuma detectada"
    shown_host = "localhost" if HOST in ("0.0.0.0", "::") else HOST
    print(f"  Monitor  →  http://{shown_host}:{PORT}")
    print(f"  CPU      →  {CPU_MODEL}")
    print(f"  GPU      →  {gpu}")
    print("  Ctrl+C para encerrar.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nEncerrado.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
