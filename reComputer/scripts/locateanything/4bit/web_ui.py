#!/usr/bin/env python3
"""
web_ui.py — LocateAnything-3B 4-bit Web UI (image-only) for low-memory Jetson
(Orin Nano 8G / NX / AGX). Single-file FastAPI app; UI aligned with
jetson-examples/reComputer/scripts/locateanything (dark theme, drag-drop, <img>
result feed, control bar, stats, loading overlay) but image-only and 4-bit NF4.

Backend copies the VERIFIED run_4bit.py inference path verbatim (greedy,
generation_mode="slow", fp16 compute, MAX_SIDE downscale -> 2.91 GB VRAM, ~23
boxes / ~29s on Orin). Model loads once at startup in the main thread.

Launch via run_web_ui.py (device-aware) or directly:
    source .venv/bin/activate   # LD_LIBRARY_PATH + HF offline
    python web_ui.py --port 7860 --max-side 448
"""
import argparse
import base64
import gc
import io
import os
import re
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
import threading
import time
from typing import Any, Dict, List

import cv2
import numpy as np
import torch
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import HTMLResponse, JSONResponse
from PIL import Image
from transformers import AutoModel, AutoProcessor, AutoTokenizer, BitsAndBytesConfig
import uvicorn

# ── config (env overridable; run_web_ui.py sets these from device detection) ──
MODEL_ID = os.environ.get("LA_MODEL", "nvidia/LocateAnything-3B")
DEVICE = "cuda"
MAX_SIDE = int(os.environ.get("LA_MAX_SIDE", "448"))

# ── runtime model handles (loaded once) ──
_tok = None
_proc = None
_model = None
_lock = threading.Lock()  # serialize GPU inference (single-device)

# BGR palette, cycled per box (matches reference locate_web_ui.py _PALETTE)
_PALETTE = [(0, 200, 0), (0, 140, 255), (255, 80, 0),
            (200, 0, 200), (0, 215, 255), (180, 180, 0)]


# ═══════════════════════════════════════════════════════════════════════════
# Model loading (copy of run_4bit.py loading)
# ═══════════════════════════════════════════════════════════════════════════
def _load_model() -> None:
    global _tok, _proc, _model
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.float16,   # fp16 compute (Turing/Jetson)
        bnb_4bit_use_double_quant=True,
    )
    print(f"[web_ui] Loading 4-bit model: {MODEL_ID} (MAX_SIDE={MAX_SIDE})", flush=True)
    _tok = AutoTokenizer.from_pretrained(MODEL_ID, trust_remote_code=True)
    _proc = AutoProcessor.from_pretrained(MODEL_ID, trust_remote_code=True)
    _model = AutoModel.from_pretrained(
        MODEL_ID,
        quantization_config=bnb_config,
        trust_remote_code=True,
        device_map={"": "cuda"},
        low_cpu_mem_usage=True,
    )
    _model.eval()
    torch.cuda.empty_cache()
    print(f"[web_ui] Model loaded. VRAM after load: "
          f"{torch.cuda.memory_allocated(0)/1e9:.2f} GB", flush=True)


# ═══════════════════════════════════════════════════════════════════════════
# Output parsing (copy of visualize_4bit.py parse_output)
# ═══════════════════════════════════════════════════════════════════════════
def parse_output(answer: str, img_w: int, img_h: int) -> List[Dict[str, Any]]:
    """Parse `<ref>label</ref><box><x1><y1><x2><y2></box>` (coords 0..1000) -> pixel boxes."""
    results: List[Dict[str, Any]] = []
    for block in re.finditer(r"<ref>(.*?)</ref>((?:<box>.*?</box>)+)", answer, re.S):
        label = block.group(1).strip()
        for m in re.finditer(r"<box><(\d+)><(\d+)><(\d+)><(\d+)></box>", block.group(2)):
            x1, y1, x2, y2 = (int(g) / 1000 for g in m.groups())
            results.append({
                "label": label,
                "x1": round(x1 * img_w), "y1": round(y1 * img_h),
                "x2": round(x2 * img_w), "y2": round(y2 * img_h),
            })
    return results


# ═══════════════════════════════════════════════════════════════════════════
# Box drawing (OpenCV, matches reference locate_web_ui.py _draw_box style)
# ═══════════════════════════════════════════════════════════════════════════
def _draw_boxes(canvas: np.ndarray, boxes: List[Dict[str, Any]]) -> np.ndarray:
    for i, box in enumerate(boxes):
        color = _PALETTE[i % len(_PALETTE)]
        x1, y1, x2, y2 = (int(box[k]) for k in ("x1", "y1", "x2", "y2"))
        label = f"{box['label']} {i+1}"
        overlay = canvas.copy()
        cv2.rectangle(overlay, (x1, y1), (x2, y2), color, -1)          # filled
        canvas = cv2.addWeighted(overlay, 0.15, canvas, 0.85, 0)        # translucent blend
        cv2.rectangle(canvas, (x1, y1), (x2, y2), color, 2)             # 2px outline
        (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
        cv2.rectangle(canvas, (x1, max(0, y1 - th - 8)),
                       (x1 + tw + 6, y1), color, -1)                   # label bg
        cv2.putText(canvas, label, (x1 + 3, y1 - 3),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
    return canvas


# ═══════════════════════════════════════════════════════════════════════════
# Inference (copy of run_4bit.py flow)
# ═══════════════════════════════════════════════════════════════════════════
def _detect(pil_img: Image.Image, prompt: str) -> Dict[str, Any]:
    # 1) downscale shorter side to MAX_SIDE (VRAM control) — run_4bit.py
    w, h = pil_img.size
    scale = MAX_SIDE / min(w, h)
    if scale < 1.0:
        nw, nh = int(w * scale), int(h * scale)
        img = pil_img.resize((nw, nh), Image.LANCZOS)
    else:
        img, nw, nh = pil_img, w, h

    question = f"Locate all the instances that matches the following description: {prompt}."

    # 2) build inputs — run_4bit.py
    messages = [{"role": "user", "content": [
        {"type": "image", "image": img},
        {"type": "text", "text": question},
    ]}]
    text = _proc.py_apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    images, videos = _proc.process_vision_info(messages)
    inputs = _proc(text=[text], images=images, videos=videos, return_tensors="pt").to(DEVICE)
    inputs["pixel_values"] = inputs["pixel_values"].to(torch.float16)

    # 3) greedy slow generate (memory-efficient) — run_4bit.py
    t0 = time.perf_counter()
    with torch.no_grad():
        response = _model.generate(
            pixel_values=inputs["pixel_values"],
            input_ids=inputs["input_ids"],
            attention_mask=inputs["attention_mask"],
            image_grid_hws=inputs.get("image_grid_hws", None),
            tokenizer=_tok,
            max_new_tokens=512,
            use_cache=True,
            generation_mode="slow",
            temperature=0.0,
            do_sample=False,
            repetition_penalty=1.1,
            verbose=True,
        )
    inf_ms = (time.perf_counter() - t0) * 1000
    # Aggressive cleanup to prevent CUDA fragmentation/crash on repeated requests
    # (the 2nd request was hard-segfaulting the process on 8GB without this).
    torch.cuda.synchronize()
    gc.collect()
    torch.cuda.empty_cache()

    answer = response[0] if isinstance(response, tuple) else response
    boxes = parse_output(answer, nw, nh)

    # 4) draw on the resized image (RGB -> BGR for cv2)
    canvas = np.array(img)[:, :, ::-1]
    canvas = _draw_boxes(canvas, boxes)
    ok, buf = cv2.imencode(".jpg", canvas, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
    jpeg_b64 = base64.b64encode(buf.tobytes() if hasattr(buf, "tobytes") else bytes(buf)).decode()

    return {
        "image": jpeg_b64,
        "boxes": boxes,
        "count": len(boxes),
        "inf_ms": round(inf_ms, 1),
        "width": nw,
        "height": nh,
        "answer": answer,
        "vram_gb": round(torch.cuda.memory_allocated(0) / 1e9, 2),
    }


def _detect_locked(pil_img: Image.Image, prompt: str) -> Dict[str, Any]:
    with _lock:  # one GPU job at a time
        return _detect(pil_img, prompt)


# ═══════════════════════════════════════════════════════════════════════════
# FastAPI app
# ═══════════════════════════════════════════════════════════════════════════
app = FastAPI(title="LocateAnything 4-bit Web UI")


@app.get("/")
async def index() -> HTMLResponse:
    return HTMLResponse(HTML_PAGE)


@app.get("/healthz")
async def healthz() -> JSONResponse:
    return JSONResponse({"ok": _model is not None,
                         "model": MODEL_ID, "max_side": MAX_SIDE})


@app.post("/detect")
async def detect(image: UploadFile = File(...), prompt: str = Form(...)) -> JSONResponse:
    prompt = (prompt or "").strip()
    if not prompt:
        raise HTTPException(status_code=400, detail="prompt is empty")
    if _model is None:
        raise HTTPException(status_code=503, detail="model not loaded yet")
    data = await image.read()
    try:
        pil = Image.open(io.BytesIO(data)).convert("RGB")
    except Exception:
        raise HTTPException(status_code=400, detail="invalid image file")
    try:
        result = await run_in_threadpool(_detect_locked, pil, prompt)
    except RuntimeError as e:
        msg = str(e)
        if "out of memory" in msg.lower() or "INTERNAL ASSERT" in msg or "NVML" in msg:
            raise HTTPException(
                status_code=503,
                detail="GPU out of memory for this image. Try a smaller image or simpler prompt.")
        raise HTTPException(status_code=500, detail=f"inference error: {msg[:300]}")
    return JSONResponse(result)


# ═══════════════════════════════════════════════════════════════════════════
# Inlined UI (dark theme aligned with reference locate_web_ui.py HTML_PAGE)
# ═══════════════════════════════════════════════════════════════════════════
HTML_PAGE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LocateAnything-3B Web UI (4-bit)</title>
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 24px;
    background: #0f0f0f; color: #e0e0e0;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  }
  .wrap { max-width: 900px; margin: 0 auto; }
  h1 { font-size: 22px; font-weight: 600; margin: 0 0 18px; color: #e0e0e0; }
  .sub { color: #888; font-size: 13px; margin-bottom: 22px; }
  .upload-area {
    border: 2px dashed #444; border-radius: 12px;
    padding: 36px; text-align: center; color: #aaa;
    background: #1a1a1a; cursor: pointer; transition: border .15s, background .15s;
  }
  .upload-area:hover, .upload-area.dragover {
    border-color: #00c853; background: #16201a; color: #e0e0e0;
  }
  .upload-area b { color: #00e676; }
  #result-display {
    display: block; max-width: 100%; margin: 16px auto; border-radius: 8px;
    background: #000; cursor: crosshair;
  }
  #control-bar { display: flex; gap: 10px; margin: 18px 0; flex-wrap: wrap; }
  #prompt-input {
    flex: 1; min-width: 220px; padding: 12px 14px; font-size: 15px;
    background: #1a1a1a; color: #e0e0e0; border: 1px solid #444;
    border-radius: 8px; outline: none;
  }
  #prompt-input:focus { border-color: #00c853; }
  button {
    padding: 12px 22px; font-size: 15px; font-weight: 600; border: none;
    border-radius: 8px; cursor: pointer; color: #fff; transition: background .15s;
  }
  #btn-run { background: #00c853; }
  #btn-run:hover { background: #00e676; }
  #btn-run:disabled { background: #333; color: #777; cursor: not-allowed; }
  #btn-new { background: #333; }
  #btn-new:hover { background: #444; }
  #stats-bar {
    display: flex; gap: 22px; flex-wrap: wrap; font-size: 13px; color: #aaa;
    background: #1a1a1a; border: 1px solid #2a2a2a; border-radius: 8px;
    padding: 12px 16px; margin-bottom: 12px;
  }
  .stat b { color: #00e676; font-weight: 600; }
  #status { font-size: 13px; min-height: 18px; margin-top: 8px; }
  #status.ok { color: #00e676; } #status.err { color: #ff5252; } #status.info { color: #42a5f5; }
  #loading-overlay {
    position: fixed; inset: 0; background: rgba(0,0,0,0.55); display: none;
    align-items: center; justify-content: center; z-index: 50;
  }
  .card {
    background: #1a1a1a; border-radius: 12px; padding: 28px 36px;
    text-align: center; color: #e0e0e0;
  }
  .spinner {
    width: 40px; height: 40px; margin: 0 auto 16px; border-radius: 50%;
    border: 4px solid #333; border-top-color: #00c853;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  .hide { display: none !important; }
</style>
</head>
<body>
<div class="wrap">
  <h1>LocateAnything-3B Web UI <span style="color:#00c853">(4-bit)</span></h1>
  <div class="sub">Image-only grounding on low-memory Jetson (Orin Nano 8G / NX). Backend: 4-bit NF4 quantized model.</div>

  <div id="source-area">
    <div class="upload-area" id="drop">
      Drag &amp; drop an <b>image</b> here, or <b>browse</b>
      <input type="file" id="file-input" accept="image/*" style="display:none">
    </div>
  </div>

  <img id="result-display" class="hide">

  <div id="control-bar">
    <input id="prompt-input" type="text" placeholder='Type detection prompt, e.g. "person" or "the person in the red shirt"'>
    <button id="btn-run">Run</button>
    <button id="btn-new" class="hide">New</button>
  </div>

  <div id="stats-bar">
    <span class="stat">Inference: <b id="stat-ms">—</b></span>
    <span class="stat">Boxes: <b id="stat-boxes">—</b></span>
    <span class="stat">VRAM: <b id="stat-vram">—</b></span>
    <span class="stat">Size: <b id="stat-size">—</b></span>
  </div>

  <div id="status" class="info">Load an image, type a prompt, then Run.</div>
</div>

<div id="loading-overlay">
  <div class="card">
    <div class="spinner"></div>
    <div id="overlay-text">Running inference…</div>
  </div>
</div>

<script>
const drop = document.getElementById('drop');
const fileInput = document.getElementById('file-input');
const display = document.getElementById('result-display');
const promptInput = document.getElementById('prompt-input');
const btnRun = document.getElementById('btn-run');
const btnNew = document.getElementById('btn-new');
const statMs = document.getElementById('stat-ms');
const statBoxes = document.getElementById('stat-boxes');
const statVram = document.getElementById('stat-vram');
const statSize = document.getElementById('stat-size');
const status = document.getElementById('status');
const overlay = document.getElementById('loading-overlay');
const overlayText = document.getElementById('overlay-text');

let selectedFile = null;

function setStatus(msg, kind) { status.textContent = msg; status.className = kind || 'info'; }
function showOverlay(text) { overlayText.textContent = text || 'Running inference…'; overlay.style.display = 'flex'; }
function hideOverlay() { overlay.style.display = 'none'; }

function pickFile(file) {
  if (!file || !file.type.startsWith('image/')) { setStatus('Please select an image file.', 'err'); return; }
  selectedFile = file;
  const url = URL.createObjectURL(file);
  display.src = url; display.classList.remove('hide');
  btnNew.classList.remove('hide');
  setStatus('Image loaded. Type a prompt and click Run.', 'ok');
}

drop.addEventListener('click', () => fileInput.click());
fileInput.addEventListener('change', e => { if (e.target.files[0]) pickFile(e.target.files[0]); });
['dragenter','dragover'].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.add('dragover'); }));
['dragleave','drop'].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.remove('dragover'); }));
drop.addEventListener('drop', e => { if (e.dataTransfer.files[0]) pickFile(e.dataTransfer.files[0]); });

async function runDetect() {
  if (!selectedFile) { setStatus('Load an image first.', 'err'); return; }
  const prompt = promptInput.value.trim();
  if (!prompt) { setStatus('Type a detection prompt.', 'err'); return; }
  btnRun.disabled = true;
  showOverlay('Running inference… (~25-30s)');
  setStatus('Running inference…', 'info');
  const fd = new FormData();
  fd.append('image', selectedFile);
  fd.append('prompt', prompt);
  try {
    const res = await fetch('/detect', { method: 'POST', body: fd });
    const data = await res.json();
    if (!res.ok) { setStatus('Error: ' + (data.detail || res.status), 'err'); return; }
    display.src = 'data:image/jpeg;base64,' + data.image;
    statMs.textContent = data.inf_ms.toFixed(0) + ' ms';
    statBoxes.textContent = data.count;
    statVram.textContent = data.vram_gb + ' GB';
    statSize.textContent = data.width + '×' + data.height;
    setStatus('Detected ' + data.count + ' box(es) in ' + (data.inf_ms/1000).toFixed(1) + 's.', 'ok');
  } catch (err) {
    setStatus('Request failed: ' + err.message, 'err');
  } finally {
    hideOverlay();
    btnRun.disabled = false;
  }
}

btnRun.addEventListener('click', runDetect);
promptInput.addEventListener('keydown', e => { if (e.key === 'Enter') runDetect(); });
btnNew.addEventListener('click', () => {
  selectedFile = null; fileInput.value = '';
  display.src = ''; display.classList.add('hide');
  btnNew.classList.add('hide');
  statMs.textContent = statBoxes.textContent = statVram.textContent = statSize.textContent = '—';
  setStatus('Load an image, type a prompt, then Run.', 'info');
});

fetch('/healthz').then(r => r.json()).then(h => {
  if (!h.ok) setStatus('Model is still loading — wait for "ready" then Run.', 'info');
  else setStatus('Model ready. Load an image, type a prompt, then Run.', 'ok');
}).catch(() => {});
</script>
</body>
</html>"""


# ═══════════════════════════════════════════════════════════════════════════
# Entrypoint
# ═══════════════════════════════════════════════════════════════════════════
def main() -> None:
    global MAX_SIDE, MODEL_ID
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default=os.environ.get("LA_HOST", "0.0.0.0"))
    ap.add_argument("--port", type=int, default=int(os.environ.get("LA_PORT", "7860")))
    ap.add_argument("--max-side", type=int, default=int(os.environ.get("LA_MAX_SIDE", "448")))
    ap.add_argument("--model", default=os.environ.get("LA_MODEL", "nvidia/LocateAnything-3B"))
    args = ap.parse_args()
    MAX_SIDE = args.max_side
    MODEL_ID = args.model
    print(f"[web_ui] config: model={MODEL_ID} MAX_SIDE={MAX_SIDE} device={DEVICE}", flush=True)
    _load_model()
    print(f"[web_ui] starting uvicorn on {args.host}:{args.port}", flush=True)
    uvicorn.run(app, host=args.host, port=args.port, log_level="info", ws_max_size=16777216)


if __name__ == "__main__":
    main()
