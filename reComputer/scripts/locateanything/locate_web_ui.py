"""locate_web_ui — Web-based video detection UI for LocateAnything-3B.

Run on Jetson, open from any PC browser. Upload a video or use the Jetson
camera, type a prompt, and see real-time bounding-box detection overlaid
on the looping video.

Usage:
    python examples/locate_web_ui.py                        # default port 7860
    python examples/locate_web_ui.py --port 8080            # custom port
    python examples/locate_web_ui.py --camera 0             # enable camera source
    python examples/locate_web_ui.py --camera /dev/video0   # specific device

Open in browser: http://<jetson-ip>:7860
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import io
import json
import os
import sys
import threading
import time
import tempfile

import cv2
import numpy as np
from PIL import Image as PILImage

# ── Web framework (fastapi + uvicorn for async, lightweight) ──────────────────
from fastapi import FastAPI, UploadFile, File, Form, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
import uvicorn

from locateanything_batch import load, generate_batch


# ── Knobs ─────────────────────────────────────────────────────────────────────
MAX_MODEL_DIM = int(os.environ.get("LA3B_VIDEO_DIM", "512"))
MAX_NEW_TOKENS = int(os.environ.get("LA3B_VIDEO_TOK", "16"))
DETECT_EVERY_N = int(os.environ.get("LA3B_DETECT_SKIP", "5"))

_PALETTE = [
    (0, 200, 0), (0, 140, 255), (255, 80, 0),
    (200, 0, 200), (0, 215, 255), (180, 180, 0),
]


def _resize_for_model(im: PILImage.Image, max_dim: int = MAX_MODEL_DIM) -> PILImage.Image:
    w, h = im.size
    if max(w, h) > max_dim:
        s = max_dim / max(w, h)
        im = im.resize((max(1, round(w * s)), max(1, round(h * s))), PILImage.LANCZOS)
    return im


def _iou(a, b) -> float:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1, iy1 = max(ax1, bx1), max(ay1, by1)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)
    inter = iw * ih
    union = (ax2 - ax1) * (ay2 - ay1) + (bx2 - bx1) * (by2 - by1) - inter
    return inter / union if union > 0 else 0.0


def _box_area(box) -> float:
    x1, y1, x2, y2 = box
    return max(0.0, x2 - x1) * max(0.0, y2 - y1)


def _box_ar(box) -> float:
    """Aspect ratio: max(w,h)/min(w,h). A normal square-ish box is ~1.0-2.0."""
    w = max(0.0, box[2] - box[0])
    h = max(0.0, box[3] - box[1])
    if w <= 0 or h <= 0:
        return 999.0
    return max(w, h) / min(w, h)


def _contains(outer, inner) -> bool:
    """True if `inner` is fully inside `outer`."""
    ox1, oy1, ox2, oy2 = outer
    ix1, iy1, ix2, iy2 = inner
    return ix1 >= ox1 and iy1 >= oy1 and ix2 <= ox2 and iy2 <= oy2


def filter_boxes(boxes: list, max_area: float = 0.12, max_ar: float = 2.5,
                 iou_thresh: float = 0.3, image_mode: bool = False) -> list:
    """Post-process model boxes: remove oversized/elongated, contained, NMS.

    max_area=0.12 — drop boxes covering >12% of the frame.
    max_ar=2.5   — drop stripe boxes whose longest side is >2.5x the short side.
    image_mode   — when True, skip NMS (IoU suppression) to keep all valid boxes
                   in crowded scenes like dozens of cats in a single image.
    """
    if len(boxes) <= 1:
        return boxes

    # 1. Remove oversized + elongated (stripe / "long drifting" box)
    filtered = [(b, l) for b, l in boxes
                if _box_area(b) < max_area and _box_ar(b) < max_ar]

    if not filtered:
        smallest = min(boxes, key=lambda x: _box_area(x[0]))
        return [smallest]

    # 2. Containment: drop a box if a *smaller* box is fully inside it
    keep_set = set(range(len(filtered)))
    areas = [_box_area(b) for b, _ in filtered]
    for i in range(len(filtered)):
        if i not in keep_set:
            continue
        for j in range(len(filtered)):
            if j == i or j not in keep_set:
                continue
            if areas[j] < areas[i] and _contains(filtered[i][0], filtered[j][0]):
                keep_set.discard(i)
                break
    filtered = [filtered[k] for k in sorted(keep_set)]

    if len(filtered) <= 1 or image_mode:
        return filtered

    # 3. NMS: keep the smaller box when two boxes overlap (video mode only)
    keep = []
    used = set()
    indexed = sorted(range(len(filtered)), key=lambda i: _box_area(filtered[i][0]))

    for i in indexed:
        if i in used:
            continue
        bi, li = filtered[i]
        keep.append((bi, li))
        for j in indexed:
            if j in used or j <= i:
                continue
            bj, lj = filtered[j]
            if _iou(bi, bj) > iou_thresh:
                used.add(j)

    return keep


def _draw_box(canvas: np.ndarray, box, color, label, alpha=0.15) -> None:
    h, w = canvas.shape[:2]
    x1, y1, x2, y2 = (int(b * v) for b, v in zip(box, [w, h, w, h]))
    overlay = canvas.copy()
    cv2.rectangle(overlay, (x1, y1), (x2, y2), color, -1)
    canvas[:] = cv2.addWeighted(canvas, 1 - alpha, overlay, alpha, 0)
    cv2.rectangle(canvas, (x1, y1), (x2, y2), color, 2)
    if label:
        cv2.rectangle(canvas, (x1, max(0, y1 - 18)), (x1 + len(label) * 8, y1), color, -1)
        cv2.putText(canvas, label, (x1 + 2, y1 - 3),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)


def _frame_to_jpeg(frame_bgr: np.ndarray, quality: int = 80) -> bytes:
    _, buf = cv2.imencode(".jpg", frame_bgr, [cv2.IMWRITE_JPEG_QUALITY, quality])
    return buf.tobytes()


# ── Detection session state ───────────────────────────────────────────────────

class DetectionSession:
    """Manages video, detection loop, and current state for one browser client."""

    def __init__(self, video_path: str, prompt: str = ""):
        self.video_path = video_path
        self.prompt = prompt
        self.cap = cv2.VideoCapture(video_path)
        if not self.cap.isOpened():
            raise ValueError(f"Cannot open video: {video_path}")

        self.fps = self.cap.get(cv2.CAP_PROP_FPS) or 25.0
        self.total_frames = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
        self.width = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        self.height = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        self.frame_interval = 1.0 / self.fps if self.fps > 0 else 1.0 / 30.0

        # Detection state
        self.boxes = []          # current frame boxes: [(box, label), ...]
        self.all_boxes = []      # per-frame history
        self.total_boxes = 0
        self.inference_ms = 0.0
        self.frame_idx = 0
        self.running = False
        self.lock = threading.Lock()

    def read_frame(self, drop_if_behind: bool = False,
                   next_frame_time: float | None = None) -> tuple[bool, np.ndarray | None]:
        """Read one frame. If drop_if_behind and we are behind schedule, skip frames to catch up."""
        if not self.cap or not self.cap.isOpened():
            return False, None

        # If behind schedule, advance past stale frames
        if drop_if_behind and next_frame_time is not None:
            now = time.perf_counter()
            while now > next_frame_time + self.frame_interval:
                # Skip one frame without decoding
                self.cap.grab()
                next_frame_time += self.frame_interval

        ret, frame = self.cap.read()
        if not ret:
            self.cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            ret, frame = self.cap.read()
        return ret, frame

    def _run_detect(self, frame_bgr: np.ndarray, prompt: str) -> list:
        """Blocking GPU detection — called from a thread to avoid freezing the WS loop."""
        frame_rgb = np.ascontiguousarray(frame_bgr[:, :, ::-1])
        pil_img = PILImage.fromarray(frame_rgb)
        detect_img = _resize_for_model(pil_img.copy())

        t0 = time.perf_counter()
        detected = []

        def on_box(row_idx, normalized_box, elapsed_ms):
            detected.append((list(normalized_box), prompt))

        generate_batch([(detect_img, prompt)], on_box=on_box, max_new_tokens=MAX_NEW_TOKENS)
        self.inference_ms = (time.perf_counter() - t0) * 1000
        return detected

    async def detect_frame(self, frame_bgr: np.ndarray, prompt: str) -> list:
        """Non-blocking detection: runs GPU inference in a thread."""
        return await asyncio.to_thread(self._run_detect, frame_bgr, prompt)

    async def detect_frame_cached(self, frame_bgr: np.ndarray, prompt: str,
                                  cache_hit: bool = False,
                                  cached_boxes: list | None = None) -> tuple[list, bool]:
        if not prompt.strip():
            return [], False
        if cache_hit and cached_boxes is not None:
            self.inference_ms = 0.0
            return cached_boxes, True
        boxes = await self.detect_frame(frame_bgr, prompt)
        return boxes, False

    def draw_boxes(self, frame_bgr: np.ndarray, boxes: list) -> np.ndarray:
        canvas = frame_bgr.copy()
        for i, (box, label) in enumerate(boxes):
            color = _PALETTE[i % len(_PALETTE)]
            _draw_box(canvas, box, color, f"{label} {i+1}")
        return canvas

    def close(self):
        self.running = False
        if self.cap and self.cap.isOpened():
            self.cap.release()


# ── Camera session ────────────────────────────────────────────────────────────

class ImageSession:
    """Holds a single static image; detection runs N passes and streams back progressive boxes."""

    def __init__(self, image_path: str):
        self.image_bgr = cv2.imread(image_path)
        if self.image_bgr is None:
            raise ValueError(f"Cannot load image: {image_path}")
        self.height, self.width = self.image_bgr.shape[:2]
        self.image_path = image_path

        self.prompt = ""
        self.boxes = []
        self.total_boxes = 0
        self.inference_ms = 0.0
        self.frame_idx = 0
        self.running = False
        self.total_frames = 1
        self.fps = 0.0

    def read_frame(self) -> tuple[bool, np.ndarray | None]:
        return True, self.image_bgr.copy()

    async def detect_frame(self, frame_bgr, prompt: str) -> list:
        """Run inference on a single image with progressive on_box streaming.

        Each on_box call appends to `self._live_boxes`; we snapshot that list
        every time the WS handler wants to render progressive results.
        """
        self._live_boxes: list = []

        def _run():
            frame_rgb = np.ascontiguousarray(frame_bgr[:, :, ::-1])
            pil_img = PILImage.fromarray(frame_rgb)
            detect_img = _resize_for_model(pil_img.copy())
            t0 = time.perf_counter()
            self._live_boxes = []

            def on_box(row_idx, normalized_box, elapsed_ms):
                self._live_boxes.append((list(normalized_box), prompt))

            generate_batch([(detect_img, prompt)], on_box=on_box, max_new_tokens=MAX_NEW_TOKENS)
            self.inference_ms = (time.perf_counter() - t0) * 1000
            return list(self._live_boxes)

        return await asyncio.to_thread(_run)

    async def detect_frame_cached(self, frame_bgr, prompt: str, cache_hit=False, cached_boxes=None):
        if not prompt.strip():
            return [], False
        if cache_hit and cached_boxes is not None:
            self.inference_ms = 0.0
            return cached_boxes, True
        boxes = await self.detect_frame(frame_bgr, prompt)
        return boxes, False

    def draw_boxes(self, frame_bgr: np.ndarray, boxes: list) -> np.ndarray:
        canvas = frame_bgr.copy()
        for i, (box, label) in enumerate(boxes):
            color = _PALETTE[i % len(_PALETTE)]
            _draw_box(canvas, box, color, f"{label} {i+1}")
        return canvas

    def close(self):
        self.running = False


# ── Camera session ────────────────────────────────────────────────────────────

class CameraSession:
    """Manages camera capture and detection for one client."""

    def __init__(self, camera_source: str | int = 0):
        if isinstance(camera_source, str) and camera_source.isdigit():
            camera_source = int(camera_source)
        self.cap = cv2.VideoCapture(camera_source)
        if not self.cap.isOpened():
            raise ValueError(f"Cannot open camera: {camera_source}")

        self.width = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        self.height = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        self.fps = self.cap.get(cv2.CAP_PROP_FPS) or 30.0
        self.total_frames = -1  # infinite for camera

        self.prompt = ""
        self.boxes = []
        self.total_boxes = 0
        self.inference_ms = 0.0
        self.frame_idx = 0
        self.running = False
        self.lock = threading.Lock()

    def read_frame(self) -> tuple[bool, np.ndarray | None]:
        if not self.cap or not self.cap.isOpened():
            return False, None
        ret, frame = self.cap.read()
        return ret, frame

    async def detect_frame(self, frame_bgr: np.ndarray, prompt: str) -> list:
        if not prompt.strip():
            return []

        def _run():
            frame_rgb = np.ascontiguousarray(frame_bgr[:, :, ::-1])
            pil_img = PILImage.fromarray(frame_rgb)
            detect_img = _resize_for_model(pil_img.copy())
            t0 = time.perf_counter()
            detected = []
            def on_box(row_idx, normalized_box, elapsed_ms):
                detected.append((list(normalized_box), prompt))
            generate_batch([(detect_img, prompt)], on_box=on_box, max_new_tokens=MAX_NEW_TOKENS)
            self.inference_ms = (time.perf_counter() - t0) * 1000
            return detected
        return await asyncio.to_thread(_run)

    async def detect_frame_cached(self, frame_bgr: np.ndarray, prompt: str,
                                  cache_hit: bool = False,
                                  cached_boxes: list | None = None) -> tuple[list, bool]:
        if not prompt.strip():
            return [], False
        if cache_hit and cached_boxes is not None:
            self.inference_ms = 0.0
            return cached_boxes, True
        boxes = await self.detect_frame(frame_bgr, prompt)
        return boxes, False

    def draw_boxes(self, frame_bgr: np.ndarray, boxes: list) -> np.ndarray:
        canvas = frame_bgr.copy()
        for i, (box, label) in enumerate(boxes):
            color = _PALETTE[i % len(_PALETTE)]
            _draw_box(canvas, box, color, f"{label} {i+1}")
        return canvas

    def close(self):
        self.running = False
        if self.cap and self.cap.isOpened():
            self.cap.release()


# ── FastAPI app ───────────────────────────────────────────────────────────────

app = FastAPI(title="LocateAnything Web UI")

# Store active sessions per client
sessions: dict[str, DetectionSession] = {}
upload_dir = tempfile.mkdtemp(prefix="locate_web_ui_")

HTML_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>LocateAnything - Video Detection</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
         background: #0f0f0f; color: #e0e0e0; display: flex; flex-direction: column;
         align-items: center; min-height: 100vh; padding: 20px; }
  h1 { font-size: 1.5rem; margin-bottom: 16px; color: #fff; }
  .container { display: flex; flex-direction: column; align-items: center; gap: 16px; width: 100%; max-width: 900px; }

  /* Upload area */
  .upload-area {
    border: 2px dashed #444; border-radius: 12px; padding: 40px 20px;
    text-align: center; cursor: pointer; width: 100%; transition: border-color 0.2s;
  }
  .upload-area:hover { border-color: #00c853; }
  .upload-area.dragover { border-color: #00c853; background: rgba(0,200,83,0.05); }
  .upload-area input { display: none; }
  .upload-area p { font-size: 0.95rem; color: #aaa; }
  .upload-area .browse { color: #00c853; text-decoration: underline; cursor: pointer; }
  .upload-area .cam-btn {
    display: inline-block; margin-top: 12px; padding: 10px 24px;
    background: #42a5f5; color: #000; border-radius: 8px; font-weight: 600;
    cursor: pointer; font-size: 0.95rem; transition: background 0.2s;
  }
  .upload-area .cam-btn:hover { background: #64b5f6; }

  /* Video display */
  #video-display {
    width: 100%; border-radius: 8px; background: #1a1a1a;
    display: none; cursor: crosshair;
  }

  /* Controls */
  .controls {
    display: flex; gap: 10px; width: 100%; align-items: center; flex-wrap: wrap;
  }
  #prompt-input {
    flex: 1; padding: 10px 14px; border-radius: 8px; border: 1px solid #444;
    background: #1a1a1a; color: #fff; font-size: 1rem; outline: none;
  }
  #prompt-input:focus { border-color: #00c853; }
  #prompt-input::placeholder { color: #666; }
  button {
    padding: 10px 20px; border-radius: 8px; border: none; font-size: 0.95rem;
    cursor: pointer; font-weight: 600; transition: background 0.2s;
  }
  #btn-run { background: #00c853; color: #000; }
  #btn-run:hover { background: #00e676; }
  #btn-stop { background: #ff5252; color: #fff; }
  #btn-stop:hover { background: #ff6e6e; }
  #btn-new { background: #444; color: #fff; }
  #btn-new:hover { background: #555; }

  /* Stats bar */
  .stats {
    display: flex; gap: 20px; font-size: 0.85rem; color: #aaa;
    padding: 8px 0; width: 100%;
  }
  .stats span { display: inline-flex; align-items: center; gap: 4px; }
  .stats .val { color: #00c853; font-weight: 600; font-size: 1rem; }
  .stats .warn { color: #ff9800; }
  .stats .good { color: #00c853; }

  /* Status message */
  #status {
    font-size: 0.9rem; color: #aaa; min-height: 1.2em; text-align: center;
  }
  #status.error { color: #ff5252; }
  #status.info { color: #42a5f5; }
  #status.ok { color: #00c853; }
</style>
</head>
<body>

<h1>LocateAnything-3B Web UI</h1>

<div class="container">
  <!-- Source selection (upload or camera) -->
  <div class="upload-area" id="source-area">
    <p>Drag & drop a <span class="browse" id="kind-video-tab" onclick="setSourceKind('video')">video</span> or <span class="browse" id="kind-image-tab" onclick="setSourceKind('image')">image</span> here, or <span class="browse" onclick="document.getElementById('file-input').click()">browse</span></p>
    <p style="margin-top: 12px;">— or use a camera —</p>
    <div style="margin-top: 8px;">
      <select id="camera-select" style="padding: 8px; border-radius: 6px; background: #1a1a1a; color: #fff; border: 1px solid #444; font-size: 0.9rem; margin-right: 8px;">
        <option value="">Loading cameras…</option>
      </select>
      <span class="cam-btn" onclick="startCamera()">Open Camera</span>
    </div>
    <input type="file" id="file-input" accept="video/*,image/*">
  </div>

  <!-- Video -->
  <img id="video-display" alt="detection feed">

  <!-- Prompt input -->
  <div class="controls" style="display:none;" id="control-bar">
    <input type="text" id="prompt-input" placeholder='Type detection prompt, e.g. "a person" or "cat"'>
    <button id="btn-run" onclick="startDetection()">Run</button>
    <button id="btn-stop" onclick="stopDetection()" style="display:none;">Stop</button>
    <button id="btn-new" onclick="resetUI()">New Source</button>
  </div>

  <!-- Stats -->
  <div class="stats" id="stats-bar" style="display:none;">
    <span>FPS <span class="val" id="stat-fps">--</span></span>
    <span>Inference <span class="val" id="stat-inf">--</span></span>
    <span>Boxes <span class="val" id="stat-boxes">0</span></span>
    <span>Frame <span class="val" id="stat-frame">0/0</span></span>
    <span id="stat-quality"></span>
    <span>Detect 1 / <input type="number" id="skip-input" min="1" max="20" value="3" style="width:50px; padding:2px 4px; border-radius:4px; background:#1a1a1a; color:#fff; border:1px solid #444; font-size:0.9rem;"> frames</span>
    <span>Quality <input type="number" id="quality-input" min="20" max="95" value="50" style="width:50px; padding:2px 4px; border-radius:4px; background:#1a1a1a; color:#fff; border:1px solid #444; font-size:0.9rem;"> %</span>
  </div>

  <p id="status"></p>
  <div id="loading-overlay" style="display:none; position:fixed; inset:0; background:rgba(0,0,0,0.55); z-index:999; align-items:center; justify-content:center;">
    <div style="background:#1a1a1a; padding:32px 40px; border-radius:14px; text-align:center;">
      <div class="spinner" style="width:40px; height:40px; border:4px solid #444; border-top:4px solid #00c853; border-radius:50%; animation:spin 1s linear infinite; margin:0 auto 14px;"></div>
      <p style="color:#fff; font-size:1rem;">Loading model...</p>
    </div>
  </div>
  <style>@keyframes spin { 100% { transform:rotate(360deg); } }</style>
</div>

<script>
const uploadArea = document.getElementById('upload-area');
const fileInput  = document.getElementById('file-input');
const videoImg   = document.getElementById('video-display');
const promptIn   = document.getElementById('prompt-input');
const btnRun     = document.getElementById('btn-run');
const btnStop    = document.getElementById('btn-stop');
const btnNew     = document.getElementById('btn-new');
const controlBar = document.getElementById('control-bar');
const statsBar   = document.getElementById('stats-bar');
const status     = document.getElementById('status');
const loadingOverlay = document.getElementById('loading-overlay');

let ws = null;
let uploading = false;
let sourceKind = 'video'; // 'video' or 'image'
let sourceSessionId = null;

function setSourceKind(kind) {
  sourceKind = kind;
  document.getElementById('kind-video-tab').style.color = kind === 'video' ? '#00c853' : '#aaa';
  document.getElementById('kind-image-tab').style.color = kind === 'image' ? '#00c853' : '#aaa';
}
setSourceKind('video');

// Drag & drop
const sourceArea = document.getElementById('source-area');
sourceArea.addEventListener('dragover', e => { e.preventDefault(); sourceArea.classList.add('dragover'); });
sourceArea.addEventListener('dragleave', () => sourceArea.classList.remove('dragover'));
sourceArea.addEventListener('drop', e => {
  e.preventDefault(); sourceArea.classList.remove('dragover');
  if (e.dataTransfer.files.length > 0) uploadFile(e.dataTransfer.files[0]);
});
fileInput.addEventListener('change', () => { if (fileInput.files.length > 0) uploadFile(fileInput.files[0]); });

// Load cameras on startup
loadCameras();

async function uploadFile(file) {
  if (uploading) return;
  uploading = true;

  // Auto-detect source kind from file extension
  const ext = file.name.split('.').pop().toLowerCase();
  const imgExts = ['jpg','jpeg','png','bmp','webp','tiff','tif'];
  if (imgExts.includes(ext)) sourceKind = 'image';
  else sourceKind = 'video';
  setSourceKind(sourceKind);

  setStatus('info', `Uploading ${file.name}...`);

  const form = new FormData();
  form.append('file', file);

  try {
    const endpoint = sourceKind === 'image' ? '/upload-image' : '/upload';
    const resp = await fetch(endpoint, { method: 'POST', body: form });
    const data = await resp.json();
    if (data.error) { setStatus('error', data.error); return; }

    sourceSessionId = data.session_id;
    showDetectionUI();
    const label = sourceKind === 'image' ? 'Image' : 'Video';
    setStatus('ok', `${label} loaded: ${data.width}x${data.height}${data.frames > 1 ? ', ' + data.frames + ' frames' : ''}`);

    // Start WebSocket for live frames
    connectWebSocket(data.session_id);
  } catch(e) {
    setStatus('error', `Upload failed: ${e.message}`);
  } finally {
    uploading = false;
  }
}

async function startCamera() {
  if (uploading) return;
  uploading = true;
  const sel = document.getElementById('camera-select');
  const source = sel.value;
  setStatus('info', 'Opening camera...');

  try {
    const resp = await fetch('/camera', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ source: source })
    });
    const data = await resp.json();
    if (data.error) { setStatus('error', data.error); return; }

    showDetectionUI();
    setStatus('ok', `Camera live: ${data.width}x${data.height}, ${data.fps.toFixed(1)} FPS`);
    connectWebSocket(data.session_id);
  } catch(e) {
    setStatus('error', `Camera failed: ${e.message}`);
  } finally {
    uploading = false;
  }
}

async function loadCameras() {
  try {
    const resp = await fetch('/cameras');
    const data = await resp.json();
    const sel = document.getElementById('camera-select');
    if (!data.cameras || data.cameras.length === 0) {
      sel.innerHTML = '<option value="">No cameras found</option>';
      return;
    }
    sel.innerHTML = '';
    for (const cam of data.cameras) {
      const opt = document.createElement('option');
      opt.value = cam.source;
      opt.textContent = cam.label;
      sel.appendChild(opt);
    }
  } catch(e) {
    const sel = document.getElementById('camera-select');
    sel.innerHTML = '<option value="0">Default Camera (0)</option>';
  }
}

function showDetectionUI() {
  document.getElementById('source-area').style.display = 'none';
  document.getElementById('control-bar').style.display = 'flex';
  document.getElementById('stats-bar').style.display = 'flex';
  document.getElementById('video-display').style.display = 'block';
  // Force-clear stale src so previous video frame doesn't show during WS handshake
  videoImg.src = '';
  document.getElementById('prompt-input').focus();
}

function connectWebSocket(sessionId) {
  if (ws) { ws.close(); ws = null; }
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(`${proto}//${location.host}/ws/${sessionId}`);

  ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    if (msg.type === 'frame') {
      // Update image
      videoImg.src = 'data:image/jpeg;base64,' + msg.jpeg;
      // Hide loading overlay once first frame with boxes arrives
      if (msg.boxes > 0 || msg.inf_ms > 0) loadingOverlay.style.display = 'none';
      // Update stats
      document.getElementById('stat-fps').textContent = msg.fps.toFixed(1);
      document.getElementById('stat-inf').textContent = Math.round(msg.inf_ms) + 'ms';
      document.getElementById('stat-boxes').textContent = msg.boxes;
      document.getElementById('stat-frame').textContent = `${msg.frame}/${msg.total}`;
      const q = document.getElementById('stat-quality');
      if (msg.fps >= 10) { q.className = 'good'; q.textContent = 'Real-time+'; }
      else if (msg.fps >= 5) { q.className = 'good'; q.textContent = 'Real-time'; }
      else if (msg.fps >= 2.5) { q.className = 'warn'; q.textContent = 'Near real-time'; }
      else { q.className = 'warn'; q.textContent = 'Slow'; }
    } else if (msg.type === 'status') {
      setStatus(msg.level, msg.message);
    }
  };

  ws.onclose = () => {
    if (controlBar.style.display !== 'none') {
      setStatus('info', 'Connection closed. Click Run to reconnect.');
    }
  };

  ws.onerror = () => setStatus('error', 'WebSocket error');
}

function startDetection() {
  const prompt = promptIn.value.trim();
  if (!prompt) { setStatus('error', 'Please enter a detection prompt'); return; }
  btnRun.style.display = 'none';
  btnStop.style.display = 'inline-block';
  setStatus('ok', `Detecting "${prompt}"...`);
  loadingOverlay.style.display = 'flex';
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ action: 'start', prompt: prompt }));
  }
}

function stopDetection() {
  btnRun.style.display = 'inline-block';
  btnStop.style.display = 'none';
  setStatus('info', 'Detection stopped');
  loadingOverlay.style.display = 'none';
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ action: 'stop' }));
  }
}

function resetUI() {
  stopDetection();
  if (ws) { ws.close(); ws = null; }
  videoImg.style.display = 'none';
  controlBar.style.display = 'none';
  statsBar.style.display = 'none';
  document.getElementById('source-area').style.display = '';
  fileInput.value = '';
  promptIn.value = '';
  setStatus('info', '');
}

// Enter key in prompt triggers Run
promptIn.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') { e.preventDefault(); startDetection(); }
});

function setStatus(level, msg) {
  status.className = level;
  status.textContent = msg;
}

// Live controls for skip and quality
const skipInput = document.getElementById('skip-input');
const qualityInput = document.getElementById('quality-input');
skipInput.addEventListener('change', () => {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ action: 'set_skip', value: parseInt(skipInput.value) || 3 }));
  }
});
qualityInput.addEventListener('change', () => {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ action: 'set_quality', value: parseInt(qualityInput.value) || 60 }));
  }
});

// Keep-alive ping for WebSocket
setInterval(() => {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ action: 'ping' }));
  }
}, 15000);
</script>
</body>
</html>"""


@app.get("/", response_class=HTMLResponse)
async def index():
    return HTML_PAGE


@app.post("/upload")
async def upload_video(file: UploadFile = File(...)):
    """Save uploaded video and return session info."""
    ext = os.path.splitext(file.filename or "video.mp4")[1] or ".mp4"
    vid_path = os.path.join(upload_dir, f"{int(time.time())}{ext}")

    contents = await file.read()
    with open(vid_path, "wb") as f:
        f.write(contents)

    try:
        session = DetectionSession(vid_path)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=400)

    sid = str(int(time.time() * 1000))
    sessions[sid] = session

    return {
        "session_id": sid,
        "kind": "video",
        "width": session.width,
        "height": session.height,
        "fps": session.fps,
        "frames": session.total_frames,
    }


@app.post("/upload-image")
async def upload_image(file: UploadFile = File(...)):
    """Save uploaded image and return session info."""
    ext = os.path.splitext(file.filename or "image.jpg")[1] or ".jpg"
    img_path = os.path.join(upload_dir, f"{int(time.time())}{ext}")

    contents = await file.read()
    with open(img_path, "wb") as f:
        f.write(contents)

    try:
        session = ImageSession(img_path)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=400)

    sid = str(int(time.time() * 1000))
    sessions[sid] = session

    return {
        "session_id": sid,
        "kind": "image",
        "width": session.width,
        "height": session.height,
        "fps": 0.0,
        "frames": 1,
    }


@app.get("/cameras")
async def list_cameras():
    """Probe /dev/video* to list available cameras."""
    cameras = []
    # Probe indices 0-9 and /dev/video* paths
    seen_sources = set()

    # First check /dev/video* paths
    for i in range(10):
        dev_path = f"/dev/video{i}"
        if os.path.exists(dev_path):
            seen_sources.add(dev_path)
            cameras.append({"source": dev_path, "label": f"Camera {i} ({dev_path})"})

    # Then check numeric indices
    for i in range(5):
        if i not in seen_sources:
            test = cv2.VideoCapture(i)
            if test.isOpened():
                ret, _ = test.read()
                test.release()
                if ret:
                    cameras.append({"source": str(i), "label": f"Camera {i} (index)"})

    if not cameras:
        # Default fallback
        cameras.append({"source": "0", "label": "Default Camera (0)"})

    return {"cameras": cameras}


@app.post("/camera")
async def open_camera(request: dict):
    """Open a camera source and create a session."""
    source = request.get("source", "0")
    try:
        session = CameraSession(source)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=400)

    sid = str(int(time.time() * 1000))
    sessions[sid] = session

    return {
        "session_id": sid,
        "width": session.width,
        "height": session.height,
        "fps": session.fps,
        "frames": session.total_frames,
    }


@app.websocket("/ws/{session_id}")
async def ws_detection(ws: WebSocket, session_id: str):
    """WebSocket: stream JPEG frames at source-video rate with adaptive detection skip."""
    await ws.accept()
    session = sessions.get(session_id)
    if not session:
        await ws.close(code=1008, reason="Unknown session")
        return

    # ── State ──────────────────────────────────────────────────────────────
    session.running = True
    current_prompt = ""
    detecting = False

    # Timing
    fps_t0 = time.perf_counter()
    fps_count = 0
    render_fps = 0.0
    fps_recent: list[float] = []  # last 30 inter-frame deltas for smooth FPS

    # Frame-skip cache
    detect_skip = DETECT_EVERY_N
    detect_counter = 0
    cached_boxes: list = []

    # Adaptive skip tracking
    low_fps_streak = 0
    high_fps_streak = 0

    # JPEG quality (client-adjustable)
    jpeg_quality = 60

    is_video = hasattr(session, "frame_interval")
    is_image = isinstance(session, ImageSession)
    run_detect = True

    # Image mode: send original image immediately so it shows right away
    image_initial_frame_sent = False

    try:
        while True:
            # ── Handle client messages (non-blocking) ──────────────────────
            try:
                raw = await asyncio.wait_for(ws.receive_text(), timeout=0.001)
                msg = json.loads(raw)
                action = msg.get("action", "")
                if action == "start":
                    current_prompt = msg.get("prompt", "").strip()
                    detecting = bool(current_prompt)
                    fps_t0 = time.perf_counter()
                    fps_count = 0
                    fps_recent.clear()
                    detect_counter = 0
                    cached_boxes = []
                    low_fps_streak = 0
                    high_fps_streak = 0
                elif action == "stop":
                    detecting = False
                elif action == "set_skip":
                    detect_skip = max(1, min(20, int(msg.get("value", 3))))
                elif action == "set_quality":
                    jpeg_quality = max(20, min(95, int(msg.get("value", 60))))
                elif action == "ping":
                    continue
            except asyncio.TimeoutError:
                pass

            if not session.running:
                break

            t_frame_start = time.perf_counter()

            # ── Image mode: run ONE detection pass per "start" command, then idle
            if is_image:
                # Send original image once on connect so the user sees their upload
                if not image_initial_frame_sent:
                    ret0, frame0 = session.read_frame()
                    if ret0 and frame0 is not None:
                        h_orig, w_orig = frame0.shape[:2]
                        if w_orig > 1280:
                            scale = 1280 / w_orig
                            frame0 = cv2.resize(frame0, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
                        h, w = frame0.shape[:2]
                        q = jpeg_quality if w * h <= 600_000 else max(30, jpeg_quality - 10)
                        jpeg = _frame_to_jpeg(frame0, quality=q)
                        b64 = base64.b64encode(jpeg).decode("ascii")
                        await ws.send_json({
                            "type": "frame",
                            "jpeg": b64,
                            "fps": 0.0,
                            "inf_ms": 0.0,
                            "boxes": 0,
                            "frame": 0,
                            "total": 0,
                            "cached": False,
                            "skip": 1,
                        })
                        image_initial_frame_sent = True

                if not (detecting and current_prompt):
                    await asyncio.sleep(0.05)
                    continue
                ret, frame_bgr = session.read_frame()
                if not ret or frame_bgr is None:
                    await asyncio.sleep(0.05)
                    continue

                # Resize large images to fit browser display (max 1280px wide)
                max_disp = 1280
                h_orig, w_orig = frame_bgr.shape[:2]
                if w_orig > max_disp:
                    scale = max_disp / w_orig
                    frame_bgr = cv2.resize(frame_bgr, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)

                # Immediately show the image (no boxes yet) so user sees their upload
                h, w = frame_bgr.shape[:2]
                q = jpeg_quality if w * h <= 600_000 else max(30, jpeg_quality - 10)
                jpeg = _frame_to_jpeg(frame_bgr, quality=q)
                b64 = base64.b64encode(jpeg).decode("ascii")
                await ws.send_json({
                    "type": "frame",
                    "jpeg": b64,
                    "fps": 0.0,
                    "inf_ms": 0.0,
                    "boxes": 0,
                    "frame": 0,
                    "total": 0,
                    "cached": False,
                    "skip": 1,
                })

                # Now run detection with progressive box streaming
                detect_task = asyncio.create_task(
                    session.detect_frame(frame_bgr, current_prompt)
                )
                last_sent_count = 0
                while not detect_task.done():
                    await asyncio.sleep(0.06)
                    live = list(getattr(session, "_live_boxes", []))
                    if len(live) > last_sent_count:
                        last_sent_count = len(live)
                        display = session.draw_boxes(frame_bgr, live)
                        h, w = display.shape[:2]
                        q = jpeg_quality if w * h <= 600_000 else max(30, jpeg_quality - 10)
                        jpeg = _frame_to_jpeg(display, quality=q)
                        b64 = base64.b64encode(jpeg).decode("ascii")
                        await ws.send_json({
                            "type": "frame",
                            "jpeg": b64,
                            "fps": 0.0,
                            "inf_ms": (time.perf_counter() - t_frame_start) * 1000,
                            "boxes": len(live),
                            "frame": len(live),
                            "total": 0,
                            "cached": False,
                            "skip": 1,
                        })

                final_boxes = await detect_task
                display = session.draw_boxes(frame_bgr, final_boxes)
                h, w = display.shape[:2]
                q = jpeg_quality if w * h <= 600_000 else max(30, jpeg_quality - 10)
                jpeg = _frame_to_jpeg(display, quality=q)
                b64 = base64.b64encode(jpeg).decode("ascii")
                await ws.send_json({
                    "type": "frame",
                    "jpeg": b64,
                    "fps": 0.0,
                    "inf_ms": session.inference_ms,
                    "boxes": len(final_boxes),
                    "frame": len(final_boxes),
                    "total": 0,
                    "cached": False,
                    "skip": 1,
                })
                detecting = False  # one-shot; wait for next "start"
                continue
            # ── End image mode ────────────────────────────────────────────

            # ── Read frame (video / camera) ────────────────────────────────
            if is_video:
                ret, frame_bgr = session.read_frame(drop_if_behind=True,
                                                     next_frame_time=t_frame_start)
            else:
                ret, frame_bgr = session.read_frame()

            if not ret or frame_bgr is None:
                continue

            # ── Detection with adaptive skip ───────────────────────────────
            boxes = []
            if detecting and current_prompt:
                run_detect = (detect_counter % detect_skip == 0)
                boxes, _ = await session.detect_frame_cached(
                    frame_bgr, current_prompt,
                    cache_hit=not run_detect,
                    cached_boxes=cached_boxes,
                )
                if run_detect:
                    # Post-process: remove oversized boxes and duplicates
                    boxes = filter_boxes(boxes)
                    cached_boxes = boxes
                detect_counter += 1
            else:
                detect_counter = 0
                cached_boxes = []

            # ── Draw boxes ─────────────────────────────────────────────────
            display_frame = session.draw_boxes(frame_bgr, boxes) if boxes else frame_bgr

            # ── Encode JPEG (auto-lower quality for large frames) ──────────
            h, w = display_frame.shape[:2]
            q = jpeg_quality
            if w * h > 600_000:
                q = max(30, q - 10)
            jpeg = _frame_to_jpeg(display_frame, quality=q)
            b64 = base64.b64encode(jpeg).decode("ascii")

            # ── Smooth FPS (sliding window of 30 frames) ──────────────────
            t_now = time.perf_counter()
            dt = t_now - t_frame_start
            fps_recent.append(dt)
            if len(fps_recent) > 30:
                fps_recent.pop(0)
            avg_dt = sum(fps_recent) / len(fps_recent)
            render_fps = 1.0 / avg_dt if avg_dt > 0 else 0

            # ── Adaptive skip (only adjust after enough data) ──────────────
            if len(fps_recent) >= 10 and detecting:
                # Target: maintain at least 15 FPS display
                if render_fps < 12:
                    low_fps_streak += 1
                    high_fps_streak = 0
                    if low_fps_streak >= 2:
                        detect_skip = min(20, detect_skip + 1)
                        low_fps_streak = 0
                elif render_fps > 25:
                    high_fps_streak += 1
                    low_fps_streak = 0
                    if high_fps_streak >= 5:
                        detect_skip = max(1, detect_skip - 1)
                        high_fps_streak = 0

            # ── Send frame ─────────────────────────────────────────────────
            await ws.send_json({
                "type": "frame",
                "jpeg": b64,
                "fps": render_fps,
                "inf_ms": getattr(session, "inference_ms", 0.0),
                "boxes": len(boxes),
                "frame": detect_counter,
                "total": getattr(session, "total_frames", 0),
                "cached": (not run_detect) if detecting else False,
                "skip": detect_skip,
            })

            # No fixed sleep — the loop runs as fast as possible
            # Detection takes ~300ms, so natural cadence = 18-20 FPS with detect_every=1
            # With detect_every=5, skipped frames are instant → much higher display FPS

    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"[ws] error: {e}", flush=True)
    finally:
        session.running = False


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="LocateAnything Web UI Server")
    parser.add_argument("--host", default="0.0.0.0", help="Bind host (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=7860, help="Bind port (default: 7860)")
    args = parser.parse_args()

    print(f"[web-ui] Loading model...", flush=True)
    load()
    print(f"[web-ui] Model loaded! (dim={MAX_MODEL_DIM}, tokens={MAX_NEW_TOKENS}, detect_every={DETECT_EVERY_N})", flush=True)
    print(f"[web-ui] Starting server at http://{args.host}:{args.port}", flush=True)
    print(f"[web-ui] Open in browser: http://<jetson-ip>:{args.port}", flush=True)

    uvicorn.run(app, host=args.host, port=args.port, log_level="info",
                ws_max_size=16777216)


if __name__ == "__main__":
    main()
