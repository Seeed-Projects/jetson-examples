#!/usr/bin/env python3
"""
run_web_ui.py — device-aware launcher for the LocateAnything 4-bit Web UI.

Unified entry point: detects the Jetson (memory / model / L4T / GPU), picks a
memory-safe `MAX_SIDE` (shorter-side cap fed to the model — controls VRAM), and
launches `web_ui.py`. Backend is always 4-bit NF4 (this is the low-memory path;
the full-precision bf16 Thor variant lives in jetson-examples/reComputer/scripts/locateanything).

Run on any Jetson:
    source .venv/bin/activate    # carries LD_LIBRARY_PATH + HF-offline env
    python run_web_ui.py
    # override: python run_web_ui.py --port 7860 --max-side 448
"""
import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP = HERE / "web_ui.py"


def _mem_total_gb() -> float:
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    kb = int(line.split()[1])
                    return kb / 1024 / 1024  # KiB -> GiB
    except Exception:
        pass
    return 0.0


def _device_model() -> str:
    try:
        with open("/proc/device-tree/model", "rb") as f:
            return f.read().decode("utf-8", "replace").strip().lower()
    except Exception:
        return ""


def _l4t_version() -> str:
    try:
        with open("/etc/nv_tegra_release") as f:
            txt = f.read()
        m = re.search(r"#\s*R(\d+)\s.*?REVISION:\s*([0-9.]+)", txt)
        if m:
            return f"R{m.group(1)}.{m.group(2).rstrip(',')}"
    except Exception:
        pass
    return "unknown"


def _gpu_name() -> str:
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
            capture_output=True, text=True, timeout=10,
        ).stdout.strip()
        return out or ""
    except Exception:
        return ""


def _sm_hint(model: str) -> str:
    # Orin family -> 8.7 ; Thor -> 11.0 ; else unknown
    if "thor" in model:
        return "11.0"
    if "orin" in model:
        return "8.7"
    return "?"


def pick_max_side(mem_gb: float) -> int:
    """Memory-safe shorter-side cap for the image fed to the 4-bit model.

    Verified: MAX_SIDE=448 -> 2.91 GB VRAM on Orin NX 8GB (23 boxes, ~29s).
    """
    if mem_gb < 8:
        return 384   # Orin Nano 8G / NX 8G — extra VRAM headroom (logits.float() alloc)
    if mem_gb < 12:
        return 448
    return 672  # AGX 16/32/64GB, Thor — more headroom for accuracy


def main() -> int:
    ap = argparse.ArgumentParser(description="LocateAnything 4-bit Web UI launcher")
    ap.add_argument("--host", default=os.environ.get("LA_HOST", "0.0.0.0"))
    ap.add_argument("--port", type=int, default=int(os.environ.get("LA_PORT", "7860")))
    ap.add_argument("--max-side", type=int, default=int(os.environ.get("LA_MAX_SIDE", "0")),
                    help="override auto MAX_SIDE (0 = auto-detect from device memory)")
    ap.add_argument("--model", default=os.environ.get("LA_MODEL", "nvidia/LocateAnything-3B"))
    args = ap.parse_args()

    gpu = _gpu_name()
    if not gpu:
        print("[run_web_ui] ERROR: nvidia-smi did not return a GPU. "
              "A CUDA-capable Jetson is required. Aborting.", file=sys.stderr)
        return 1

    mem_gb = _mem_total_gb()
    model = _device_model()
    l4t = _l4t_version()
    sm = _sm_hint(model)
    max_side = args.max_side if args.max_side > 0 else pick_max_side(mem_gb)

    short = model or "Jetson"
    print("[run_web_ui] device: "
          f"{short} | {mem_gb:.0f}GB | SM{sm} | L4T {l4t} "
          f"-> 4-bit NF4 backend, MAX_SIDE={max_side}, port={args.port}", flush=True)

    # Hand config to web_ui.py via env (so it works even if launched standalone).
    env = os.environ.copy()
    env["LA_MAX_SIDE"] = str(max_side)
    env["LA_MODEL"] = args.model
    env["LA_PORT"] = str(args.port)
    env["LA_HOST"] = args.host
    # Mitigate PyTorch CUDACachingAllocator NVML assert on Jetson integrated GPU.
    env.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")

    if not APP.exists():
        print(f"[run_web_ui] ERROR: {APP} not found next to this launcher.", file=sys.stderr)
        return 1

    # exec web_ui.py in this interpreter (inherits venv + LD_LIBRARY_PATH + HF offline).
    cmd = [sys.executable, str(APP),
           "--host", args.host, "--port", str(args.port),
           "--max-side", str(max_side), "--model", args.model]
    print("[run_web_ui] launching (auto-restart on crash):", " ".join(cmd), flush=True)
    # Auto-restart loop: if web_ui.py hard-crashes (CUDA segfault on repeated
    # inference on 8GB), respawn it after 2s instead of leaving the service down.
    while True:
        try:
            rc = subprocess.call(cmd, env=env, cwd=str(HERE))
        except KeyboardInterrupt:
            print("\n[run_web_ui] stopped by user.", flush=True)
            return 130
        if rc == 0:
            print("[run_web_ui] web_ui.py exited cleanly.", flush=True)
            return 0
        print(f"[run_web_ui] web_ui.py crashed (rc={rc}, likely CUDA segfault). "
              f"restarting in 2s (Ctrl+C to stop)...", flush=True)
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            return 130


if __name__ == "__main__":
    raise SystemExit(main())
