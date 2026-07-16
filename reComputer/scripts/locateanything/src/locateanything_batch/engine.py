"""locateanything_batch.engine — batched + KV-cached **fast-mode MTP** generation for LocateAnything-3B.

The stock custom generate (modeling_locateanything.py) hard-asserts batch=1.
The underlying Qwen2 LM + vision scatter are batch-safe; the lock lives only in that
hand-rolled MTP loop. This module is a faithful BATCHED fork of that loop, restricted
to generation_mode='fast' (pure MTP, no AR fallback), so every row is always in MTP
and the result is numerically identical to running each pair at batch=1 (greedy).

Design:
  - General API: a batch is an arbitrary list of (PIL image, query) pairs. Different
    prompt lengths -> LEFT-PAD so all rows are right-aligned (the MTP window is always
    the rightmost block, matching the mask code's [-block_size:] tail indexing).
  - Prefill is logit-free (base model model.language_model.model -> no lm_head, avoids
    the [B,S,V] fp32 logit OOM). It scatters the image embeds and returns the KV cache.
  - Decode replicates stock exactly: each step forwards [prev-accepted tokens + a 6-wide
    speculative window], reads the window logits, decodes a whole box via the model's own
    sample_tokens/handle_pattern, accepts k in {1,3,4,6} tokens, then TRUNCATES the
    window KV (its bidirectional self-attention contaminates it) and keeps the accepted
    block's clean causal KV. Ragged per-row accept counts are kept rectangular by
    right-padding the accepted block + masking the pad slots via a persistent 2D mask.
  - position_ids are tracked per-row (NOT by KV column, since left-pad desyncs them).
  - The box decode itself stays the model's OWN sample_tokens/handle_pattern, called
    PER ROW (it is exact; do not vectorize it — decode_bbox_avg is a top-k validated
    frame decode, NOT a probability-weighted average).

Numerically equivalent to batch=1 fast mode on sdpa: split prefill (plain causal) +
windowed decode is exact (the standard split-prefill / prefix-KV equivalence argument),
the window mask is tail-relative/offset-agnostic (the model's own
update_causal_mask_for_one_gen_window_2d), and attention is per-row independent so
finished/padded rows can't leak.

PERF: generate_batch_grouped(temps=...) takes per-row temperatures so ONE batch can
cover N prompts x M temps; the box decode is untouched.

API:
  load() -> (tok, proc, model)
  generate_batch(pairs, temperature=0.0, top_p=None, top_k=None,
                 repetition_penalty=1.0, max_new_tokens=384) -> list[str]
  generate_batch_grouped(groups, ..., temps=None) -> list[list[str]]

Env knobs (all optional; defaults are sensible):
  LA3B_MODEL          HF repo id / local path of the model (default nvidia/LocateAnything-3B)
  HF_HUB_OFFLINE=1    read the local HF cache only (no network); unset -> download on first use
  MTP_FLASH_PREFILL   0 -> sdpa prefill (default 1: flash prefill when flash-attn present, faster on sm_120; decode stays sdpa)
  MTP_COMPILE         1 -> torch.compile the shared Qwen2 core (needs triton)
  MTP_BATCH_VISION    0 -> per-image vision encode (default 1: batched when flash is present)
  MTP_BATCH_PREFILL   0 -> per-image shared-prefix prefill (default 1: one batched prefill)
  MTP_BATCH_SAN       0 -> per-row logits/sample pipeline (default 1: batched over [B,6,V])
  MTP_BATCH_BOXDECODE 0 -> per-row box decode (default 1: fully-GPU batched box decode)
"""
import os, time, warnings, importlib, torch
import numpy as np
from transformers import AutoModel, AutoTokenizer, AutoProcessor

# By default let transformers fetch the model on first use; set HF_HUB_OFFLINE=1 yourself
# to read the local HF cache only (e.g. air-gapped / already-downloaded runs).
MODEL = os.environ.get("LA3B_MODEL", "nvidia/LocateAnything-3B")
MAX_DIM, MNT = 1024, 384
DEV, DT = "cuda", torch.bfloat16
N_FUTURE = 6                                            # = config.block_size (MTP window)
_PROMPT = os.environ.get("LA_MTP_PROMPT",
                         "Locate all the instances that matches the following description: ")

# LLM prefill on flash is DEFAULT ON: measured FASTER than sdpa on sm_120 now that prefill is
# batched (the earlier batch=1 measurement had flash slower -- short prefills didn't amortize
# flash's fixed overhead; the batched prefill does). Decode still can't use flash at all since the
# MTP window is bidirectional. Set MTP_FLASH_PREFILL=0 to force sdpa prefill (or to A/B it).
# Gated on the flash-attn wheel: without it the Qwen2FlashAttention2 prefill path can't run, so we
# auto-fall back to sdpa prefill (mirrors the vision auto-fallback -- "works without flash" holds).
_flash_prefill_req = os.environ.get("MTP_FLASH_PREFILL", "1") == "1"
if _flash_prefill_req:
    try:
        import flash_attn  # noqa: F401  -- presence check; the prefill path needs the wheel
        USE_FLASH_PREFILL = True
    except Exception:
        USE_FLASH_PREFILL = False
        if "MTP_FLASH_PREFILL" in os.environ:        # explicit request -> say why it's off
            warnings.warn("MTP_FLASH_PREFILL=1 but flash-attn is not importable; using sdpa prefill.")
else:
    USE_FLASH_PREFILL = False

# torch.compile the shared Qwen2 core (base.forward, dynamic shapes; vision left EAGER since
# compiling it is a net loss -- 11 graph breaks, opaque attention). MEASURED ~1.14x end-to-end on
# the two-prompt workload (modest: the per-row python box decode -- the real bottleneck -- is
# untouched), and it costs ~42s warm / ~187s cold to compile. Opt-in; needs triton (pip install triton).
# Set MTP_FLASH_PREFILL=0 when compiling (flash prefill is on by default, and the per-call
# attn-class swap would force recompiles).
MTP_COMPILE = os.environ.get("MTP_COMPILE", "0") == "1"

# Batch the MoonViT vision encode across a micro-batch's images: pack N images into ONE
# extract_feature. With flash present, MoonViT's varlen cu_seqlens path is block-diagonal per
# image -> bit-identical to per-image AND 2.6-3x (benchmarked, flat VRAM).
# Without flash, sdpa builds a dense [1,S,S] mask -> O(S^2) N^2 -> per-image fallback (auto, see
# _vision_is_flash). Default ON; set MTP_BATCH_VISION=0 to force per-image.
BATCH_VISION = os.environ.get("MTP_BATCH_VISION", "1") == "1"

# Batch the per-image shared-prefix prefill into ONE base() call (left-pad to Lpmax, scatter all
# images' visual_features). The 66-token tile prefix is badly GPU-starved at batch=1 -> ~3.6x at
# gper=16 (benchmarked). Plain-causal prefix -> split-prefill equivalence (bf16 GEMM
# ~1e-3 drift only). Default ON; MTP_BATCH_PREFILL=0 forces per-image. NOTE: the win is conditional
# on small uniform frames -- on large images prefill is already compute-bound (re-bench if changed).
BATCH_PREFILL = os.environ.get("MTP_BATCH_PREFILL", "1") == "1"

# Batch the per-row box-decode (sample_tokens): run the row-independent logits pipeline
# (rep-penalty / per-row temperature / top_p / top_k / softmax / sample) ONCE over the whole
# [B,6,V] step instead of B times on [1,6,V]; only the variable-length box assembly stays per-row.
# Greedy is BIT-IDENTICAL to the per-row san (argmax, no RNG). Default ON; MTP_BATCH_SAN=0 -> per-row.
BATCH_SAN = os.environ.get("MTP_BATCH_SAN", "1") == "1"

# Fully-GPU box-decode (requires BATCH_SAN): compute the per-row 6-token result of is_valid_box_frame
# + decode_bbox_avg + decode_ref (+ x0 fallback) as ONE batched [B,6] tensor, so the decode step needs
# ONE host transfer (nt.cpu()) instead of ~6 GPU->CPU syncs PER ROW (the scalar .item() reads inside
# is_valid_box_frame / has_valid.all / the per-row .tolist). handle_pattern then runs per-row on CPU
# data. Kills the launch/sync gaps that idle the GPU (~30% of wall time). Greedy bit-exact. Default ON;
# MTP_BATCH_BOXDECODE=0 -> per-row decode_bbox_avg/decode_ref (the BATCH_SAN path).
BATCH_BOXDECODE = os.environ.get("MTP_BATCH_BOXDECODE", "1") == "1"

_tok = _proc = _model = None
def load():
    """Lazy model load. attn_implementation='sdpa' is requested, but when a flash_attn wheel
    is present the custom magi->flash fallback (modeling_qwen2.py:932-947) overrides it to
    flash_attention_2 -- and that LLM path crashes the MTP mask code. So after load we PIN
    the LLM's per-layer attention via _set_llm_mode (default 'sdpa', decode-safe + crash-proof);
    generate_* flip prefill to flash when USE_FLASH_PREFILL. MoonViT uses flash automatically
    (modeling_vit binds flash_attn_varlen_func at import) -- nothing to do here for vision."""
    global _tok, _proc, _model
    if _model is None:
        _tok = AutoTokenizer.from_pretrained(MODEL, trust_remote_code=True)
        _proc = AutoProcessor.from_pretrained(MODEL, trust_remote_code=True)
        _model = AutoModel.from_pretrained(MODEL, dtype=DT, trust_remote_code=True,
                                           attn_implementation="sdpa").to(DEV).eval()
        _set_llm_mode(_model, "sdpa")          # crash-proof, decode-safe default
        if MTP_COMPILE:
            _maybe_compile(_model)
    return _tok, _proc, _model


def _maybe_compile(model):
    """Compile the shared Qwen2Model core (base.forward). It backs BOTH prefill (called directly)
    and decode (language_model.forward -> self.model). lm_head + MoonViT left eager. dynamic=True
    so the varying decode S/kvlen don't trigger a recompile storm. No-op + warning if triton is
    missing (inductor needs it on GPU). First call pays the compile cost (~42s warm / ~187s cold)."""
    try:
        import triton  # noqa: F401
    except Exception:
        warnings.warn("MTP_COMPILE set but triton is unavailable "
                      "(pip install triton-windows on Windows); running eager.")
        return
    import torch._dynamo as _dyn
    _dyn.config.cache_size_limit = max(_dyn.config.cache_size_limit, 64)
    base = model.language_model.model
    if not getattr(base, "_mtp_compiled", False):
        base.forward = torch.compile(base.forward, dynamic=True)
        base._mtp_compiled = True


# ---- flash-on-prefill plumbing (vision flash is automatic via the install) -----------------
# Decode MUST stay sdpa: the MTP generation window is BIDIRECTIONAL (mask_sdpa_utils
# update_causal_mask_for_one_gen_window_2d sets mask[-block:,-block:]=0 and masks -block-1),
# which the causal-only flash kernel cannot express -- the model was designed to run that
# window on magi's flex_flash_attn (arbitrary q/k ranges), which is unavailable on sm_120.
# Prefill, by contrast, is plain causal (no mask tokens) -> flash is exact and cheaper.
_SdpaCls = _PrefillFlashCls = None
def _attn_classes():
    """(Qwen2SdpaAttention, prefill-only flash subclass) from the model's dynamic module."""
    global _SdpaCls, _PrefillFlashCls
    if _SdpaCls is None:
        mod = importlib.import_module(type(_model.language_model.model).__module__)
        # flash_attn 2.8.3's unpad_input returns 5 values (added used_seqlens); the vendored
        # _upad_input (modeling_qwen2.py:634) unpacks 4. Shim it back to 4 so the HF flash path
        # works against the newer wheel.
        if not getattr(mod, "_mtp_unpad_shimmed", False) and getattr(mod, "unpad_input", None) is not None:
            _real_unpad = mod.unpad_input
            mod.unpad_input = lambda *a, **k: _real_unpad(*a, **k)[:4]
            mod._mtp_unpad_shimmed = True
        _SdpaCls = mod.Qwen2SdpaAttention
        Base = mod.Qwen2FlashAttention2
        class _PrefillFlash(Base):
            """Flash attention for PREFILL only. Qwen2Model's dispatch (pinned to 'sdpa')
            hands us a 4D mask; we ignore it and use the stashed 2D padding mask so flash's
            own _upad_input/varlen causal path runs -- exact for the no-mask-token prefill,
            and it already assumes left-padding (matching mtp_batch's left-pad)."""
            def forward(self, hidden_states, attention_mask=None, position_ids=None,
                        past_key_value=None, output_attentions=False, use_cache=False, **kw):
                return Base.forward(self, hidden_states,
                                    attention_mask=getattr(self, "_mtp_pad2d", None),
                                    position_ids=position_ids, past_key_value=past_key_value,
                                    output_attentions=output_attentions,
                                    use_cache=use_cache, **kw)
        _PrefillFlashCls = _PrefillFlash
    return _SdpaCls, _PrefillFlashCls

def _set_llm_mode(model, mode):
    """Swap every Qwen2 decoder layer's attention class. mode='sdpa' (decode-safe default)
    or 'flash' (prefill). Qwen2Model._attn_implementation stays 'sdpa' either way so the
    correct 4D mask is always built (cheap; the flash subclass ignores it)."""
    sdpa, flash = _attn_classes()
    cls = sdpa if mode == "sdpa" else flash
    llm = model.language_model.model
    for lyr in llm.layers:
        lyr.self_attn.__class__ = cls
    llm._attn_implementation = "sdpa"

def _stash_pad2d(model, mask):
    """Set the 2D padding mask the prefill-flash subclass uses for the NEXT base() call."""
    for lyr in model.language_model.model.layers:
        lyr.self_attn._mtp_pad2d = mask

_st = _hp = None
def _helpers():
    """The model's own sample_tokens / handle_pattern (the exact box decoders)."""
    global _st, _hp
    if _st is None:
        m = importlib.import_module(type(load()[2]).__module__)
        _st, _hp = m.sample_tokens, m.handle_pattern
    return _st, _hp


_gu = None
def _gen_utils():
    """The model's generate_utils module (apply_repetition_penalty / top_p_logits / top_k_logits /
    decode_bbox_avg / decode_ref / dists) -- the pieces sample_tokens_batched reuses verbatim."""
    global _gu
    if _gu is None:
        m = importlib.import_module(type(load()[2]).__module__)
        _gu = importlib.import_module(m.sample_tokens.__module__)
    return _gu


@torch.no_grad()
def sample_tokens_batched(logits, generated, token_ids, per_row_temp,
                          repetition_penalty=1.0, top_p=None, top_k=None,
                          keep_k_avg=4, generation_mode='fast', fused=False):
    """Batched fork of generate_utils.sample_tokens for the MTP window [B,6,V]. The logits pipeline
    (rep-penalty / per-row temperature / top_p / top_k / softmax / sample) is ROW-INDEPENDENT, so run
    it ONCE over the whole batch instead of B times on [1,6,V] (the per-row san defeats batching by
    slicing wlogits[b:b+1]). Only the variable-length box ASSEMBLY (decode_bbox_avg -> ragged shapes,
    where sample_tokens' final torch.stack throws) stays per-row, returned as a LIST.

    Equivalence to per-row san: every pipeline op reduces on dim=-1 only (never crosses the row dim),
    so row b's processed logits/probs are bit-identical to slicing first -> greedy (per_row_temp==0,
    argmax branch, no RNG) is BIT-EXACT. Under sampling, one batched Categorical changes the global
    RNG consumption order vs B per-row draws -> box-size jitter (blessed; greedy is the exact gate).
    apply_repetition_penalty already loops per-row internally, so passing the full [B,M] `generated`
    is row-correct. keep_k_avg/generation_mode mirror sample_tokens' decode_bbox_avg call EXACTLY
    (note: the per-row san passes keep_k=5 but decode_bbox_avg reads keep_k_avg, default 4 -- so 5 is
    a no-op there; we replicate keep_k_avg=4). Returns (x0[B,6], boxes: list of B 1-D LongTensors)."""
    gu = _gen_utils()
    B, S, V = logits.shape                                        # S = N_FUTURE = 6
    if repetition_penalty != 1.0:
        logits = gu.apply_repetition_penalty(logits, generated, repetition_penalty)
    t = per_row_temp.view(B, 1, 1)
    logits = torch.where(t > 0, logits / t.clamp(min=1e-8), logits)   # per-row temperature (t==0 -> greedy passthrough)
    if top_p is not None and top_p < 1:
        logits = gu.top_p_logits(logits, top_p)
    if top_k is not None:
        logits = gu.top_k_logits(logits, top_k)
    probs = torch.softmax(logits, dim=-1)
    x0 = probs.argmax(dim=-1)                                     # [B,6]; greedy rows are final here
    samp = per_row_temp > 0
    if bool(samp.any()):                                         # sampling rows: ONE batched Categorical draw
        idx = samp.nonzero(as_tuple=True)[0]
        try:
            x0[idx] = gu.dists.Categorical(probs=probs[idx]).sample()
        except Exception:
            pass                                                # keep argmax (matches san's except: probs.max)
    if fused:                                                   # fully-GPU box-decode -> nt[B,6] (caller does ONE .cpu())
        return _resolve_nt_batched(probs, x0, token_ids, keep_k_avg)
    boxes = []
    fallback = torch.zeros(1, dtype=x0.dtype, device=x0.device)
    for b in range(B):                                          # variable-length box assembly (per-row, exact)
        db = gu.decode_bbox_avg(logits[b], probs[b], token_ids,
                                keep_k=keep_k_avg, generation_mode=generation_mode)
        if db is not None:
            boxes.append(db)
        else:
            ref = gu.decode_ref(logits[b], probs[b], token_ids)
            boxes.append(torch.tensor(ref, dtype=x0.dtype, device=x0.device) if ref is not None else fallback)
    return x0, boxes


def _resolve_nt_batched(probs, x0, token_ids, keep_k_avg=4):
    """Fully-GPU batched fork of (decode_bbox_avg -> decode_ref -> x0 fallback): for ALL B rows at once,
    compute the same 6-token `nt` that the per-row path feeds to handle_pattern, as one [B,6] tensor.
    Bit-exact to per-row (same probs slices, thresholds, topk, argmax -- just batched), 'fast' mode only.
    Each row is exactly one of (mutually exclusive):
      empty_box  : start>=.7 & inner            -> [box_start, none, box_end, null, null, null]
      legal-coord: end_score>=.2 & all 4 coords -> [box_start, c1, c2, c3, c4, box_end]   (keep_k=keep_k_avg)
      ref        : (illegal | legal-no-coord) & ref_start>=.6 & all-5-text -> [ref_start, r1..r5] (keep_k=5)
      fallback   : else                         -> raw x0[b]
    decode_bbox_avg uses keep_k=keep_k_avg(=4); decode_ref uses keep_k=5 & start_thresh=.6 -- replicated."""
    B = probs.shape[0]; dev = probs.device; T = token_ids
    box_start, box_end = T['box_start_token_id'], T['box_end_token_id']
    none_id, null_id, im_end = T['none_token_id'], T['null_token_id'], T['im_end_token_id']
    ref_start = T['ref_start_token_id']
    clo, chi = T['coord_start_token_id'], T['coord_end_token_id']

    # ---- is_valid_box_frame (start_thresh=.7, end_thresh=.2) ----
    start_ok = probs[:, 0, box_start] >= 0.7
    empty_inner = ((probs[:, 1, none_id] > 0.2) & (probs[:, 2, box_end] > 0.2)
                   & (probs[:, 3, null_id] > 0.1) & (probs[:, 4, null_id] > 0.1))
    is_empty = start_ok & empty_inner
    end_ids = torch.tensor([box_end, null_id, im_end], device=dev)
    end_score = probs[:, 5, end_ids].sum(-1)
    is_legal = (~is_empty) & (end_score >= 0.2)

    # ---- decode_bbox_avg coord topk over positions 1..4 (keep_k_avg) ----
    _, pos_ids = torch.topk(probs[:, 1:5], k=keep_k_avg, dim=-1)          # [B,4,k]
    coord_mask = (pos_ids >= clo) & (pos_ids <= chi)
    coord_all = coord_mask.any(-1).all(-1)                               # [B]
    coord_ids = pos_ids.gather(-1, coord_mask.long().argmax(-1, keepdim=True)).squeeze(-1)  # [B,4]
    legal_box_ok = is_legal & coord_all

    # ---- decode_ref over positions 1..5 (keep_k=5, start_thresh=.6) for rows that fell through ----
    to_ref = (~is_empty) & (~legal_box_ok)                              # = decode_bbox_avg returned None
    _, rpos_ids = torch.topk(probs[:, 1:], k=5, dim=-1)                  # [B,5,5]
    ref_valid = ~((rpos_ids >= clo) & (rpos_ids <= chi))                 # non-coord text tokens
    ref_all = ref_valid.any(-1).all(-1)                                 # [B]
    ref_ids = rpos_ids.gather(-1, ref_valid.long().argmax(-1, keepdim=True)).squeeze(-1)  # [B,5]
    ref_ok = to_ref & (probs[:, 0, ref_start] >= 0.6) & ref_all

    # ---- assemble nt[B,6] (mutually-exclusive masks; default = x0 fallback) ----
    fl = lambda v: torch.full((B, 1), v, dtype=torch.long, device=dev)
    legal_row = torch.cat([fl(box_start), coord_ids, fl(box_end)], dim=1)             # [B,6]
    ref_row = torch.cat([fl(ref_start), ref_ids], dim=1)                              # [B,6]
    empty_row = torch.tensor([box_start, none_id, box_end, null_id, null_id, null_id],
                             dtype=torch.long, device=dev).unsqueeze(0).expand(B, -1)
    nt = x0.clone()
    nt = torch.where(ref_ok.unsqueeze(1), ref_row, nt)
    nt = torch.where(legal_box_ok.unsqueeze(1), legal_row, nt)
    nt = torch.where(is_empty.unsqueeze(1), empty_row, nt)
    return nt

def load_pil(p):
    from PIL import Image
    im = Image.open(p).convert("RGB"); w, h = im.size
    if max(w, h) > MAX_DIM:
        s = MAX_DIM / max(w, h); im = im.resize((max(1, round(w*s)), max(1, round(h*s))), Image.LANCZOS)
    return im

def _preproc_one(im):
    """CPU-side processor for one image -> (pixel_values[bf16], grid[int32]). Split out of
    _encode_image so _encode_images can batch the GPU encode while preprocessing stays per-image."""
    tok, proc, model = load()
    msg = [{"role": "user", "content": [{"type": "image", "image": im}, {"type": "text", "text": "x"}]}]
    text = proc.py_apply_chat_template(msg, tokenize=False, add_generation_prompt=True)
    imgs, vids = proc.process_vision_info(msg)
    inp = proc(text=[text], images=imgs, videos=vids, return_tensors="pt").to(DEV)
    grid = inp.get("image_grid_hws")
    if isinstance(grid, np.ndarray): grid = torch.from_numpy(grid).to(DEV, dtype=torch.int32)
    return inp["pixel_values"].to(DT), grid


def _vision_is_flash():
    """True iff MoonViT will actually run flash_attn_varlen (so cross-image packing is
    block-diagonal = exact AND a win). If the vision blocks are on sdpa/eager, OR the flash
    wheel is absent (multihead_attention falls back to the dense-mask sdpa path), packing is
    O(S^2) N^2 -> caller must stay per-image."""
    vm = load()[2].vision_model
    mod = importlib.import_module(type(vm).__module__)
    if getattr(mod, "flash_attn_varlen_func", None) is None:
        return False
    try:
        return vm.encoder.blocks[0].attn_implementation == "flash_attention_2"
    except Exception:
        return False


@torch.no_grad()
def _encode_images(ims):
    """N images -> list of [n_img_tokens, C] mlp1-projected visual_features, one per image
    (row-order). Drop-in for [_encode_image(im) for im in ims].

    With flash present (_vision_is_flash) and N>1, packs all images into ONE extract_feature:
    MoonViT's varlen cu_seqlens path attends BLOCK-DIAGONALLY per image -> numerically
    bit-identical to per-image, ~2.6-3x faster, flat VRAM (benchmarked:
    max|per-image - batched| = 0.00e+00, VRAM 7.87->8.20GB across gper 1->32). Without flash,
    sdpa packs into a dense [1,S,S] mask -> O(S^2) N^2 -> per-image fallback. MTP_BATCH_VISION=0
    forces per-image. Preprocessing (_preproc_one) stays per-image -- the proven win is the GPU
    encode only. Flash also helps the LLM prefill now (default on; see USE_FLASH_PREFILL), though
    decode's bidirectional MTP window still can't use it -- see _set_llm_mode."""
    tok, proc, model = load()
    pvs, grids = [], []
    for im in ims:
        pv, g = _preproc_one(im)
        pvs.append(pv); grids.append(g)
    if BATCH_VISION and len(ims) > 1 and _vision_is_flash():
        vit_list = model.extract_feature(torch.cat(pvs, dim=0), torch.cat(grids, dim=0))
        return [model.mlp1(v) for v in vit_list]        # one [P_i, C] per image (patch_merger split)
    return [model.mlp1(torch.cat(model.extract_feature(pv, g), dim=0))
            for pv, g in zip(pvs, grids)]                # per-image (flash absent / N==1 / forced off)


@torch.no_grad()
def _encode_image(im):
    """Single-image convenience wrapper (single-image callers); = _encode_images([im])[0]
    (takes the per-image path inside _encode_images, so bit-identical to the original)."""
    return _encode_images([im])[0]

@torch.no_grad()
def _tokenize(im, query):
    """1-D prompt token ids for (image, query). Uses the model's own chat template."""
    tok, proc, model = load()
    msg = [{"role": "user", "content": [{"type": "image", "image": im},
                                        {"type": "text", "text": _PROMPT + query + "."}]}]
    text = proc.py_apply_chat_template(msg, tokenize=False, add_generation_prompt=True)
    imgs, vids = proc.process_vision_info(msg)
    return proc(text=[text], images=imgs, videos=vids, return_tensors="pt").to(DEV)["input_ids"][0]

def _proc_full(im, query):
    """Full processor dict (input_ids, attention_mask, pixel_values, image_grid_hws) —
    used by the bench to drive the STOCK generate for the equivalence check."""
    tok, proc, model = load()
    msg = [{"role": "user", "content": [{"type": "image", "image": im},
                                        {"type": "text", "text": _PROMPT + query + "."}]}]
    text = proc.py_apply_chat_template(msg, tokenize=False, add_generation_prompt=True)
    imgs, vids = proc.process_vision_info(msg)
    inp = proc(text=[text], images=imgs, videos=vids, return_tensors="pt").to(DEV)
    grid = inp.get("image_grid_hws")
    if isinstance(grid, np.ndarray): grid = torch.from_numpy(grid).to(DEV, dtype=torch.int32)
    inp["image_grid_hws"] = grid
    return inp

def _trunc_kv(past, keep):
    """Slice every layer's (k,v) seq dim to `keep` (drops the speculative window)."""
    return tuple((k[:, :, :keep, :], v[:, :, :keep, :]) for (k, v) in past)


@torch.no_grad()
def generate_batch(pairs, temperature=0.0, top_p=None, top_k=None,
                   repetition_penalty=1.0, max_new_tokens=MNT, *, on_box=None, on_diag=None):
    """Batched fast-MTP generation. `pairs` = [(PIL image, query str), ...].
    Returns a list of decoded strings (one per pair), same format as the stock path.
    `on_diag` (optional) receives one dict per decoded op: {'op_type', 'is_empty_box', 'b'}."""
    tok, proc, model = load()
    san, hpat = _helpers()
    tids = model.token_ids
    IMG = model.config.image_token_index
    MASK = tids['default_mask_token_id']
    IM_END = tids['im_end_token_id']
    PAD = tok.pad_token_id if tok.pad_token_id is not None else IM_END
    B = len(pairs)
    dev = DEV

    # ---- per-row tokenize + image encode ----
    prompt_ids = [_tokenize(im, q) for (im, q) in pairs]          # list of 1-D LongTensor
    vit_list = _encode_images([im for (im, q) in pairs])          # list of [n_img, C] (batched encode)
    L = [int(t.numel()) for t in prompt_ids]
    Pmax = max(L)

    # ---- left-pad prefill tensors ----
    input_ids = torch.full((B, Pmax), PAD, dtype=torch.long, device=dev)
    amask = torch.zeros((B, Pmax), dtype=torch.long, device=dev)
    for b in range(B):
        input_ids[b, Pmax - L[b]:] = prompt_ids[b]
        amask[b, Pmax - L[b]:] = 1
    pos = amask.long().cumsum(-1) - 1                              # real tokens -> 0..L_b-1
    pos.masked_fill_(amask == 0, 1)                               # left-pad dummy (masked)
    visual_features = torch.cat(vit_list, dim=0)                  # row-order for the scatter
    assert int((input_ids == IMG).sum().item()) == visual_features.shape[0], \
        "image-token count != supplied visual_features rows"

    # ---- logit-free prefill (base Qwen2Model -> no lm_head) ----
    base = model.language_model.model
    if USE_FLASH_PREFILL:
        _set_llm_mode(model, "flash"); _stash_pad2d(model, amask)   # prefill is plain causal
    out = base(input_ids=input_ids, visual_features=visual_features, image_token_index=IMG,
               attention_mask=amask, position_ids=pos, past_key_values=None, use_cache=True)
    if USE_FLASH_PREFILL:
        _set_llm_mode(model, "sdpa")
    kv = out.past_key_values                                      # legacy tuple, [B,2,Pmax,128]x36
    kvlen = Pmax
    kvalid = amask.clone()                                        # persistent 2D key-validity

    return _decode(prompt_ids, L, kv, kvlen, kvalid,
                   temperature, top_p, top_k, repetition_penalty, max_new_tokens,
                   on_box=on_box, on_diag=on_diag)


@torch.no_grad()
def _decode(prompt_ids, L, kv, kvlen, kvalid,
            temperature, top_p, top_k, repetition_penalty, max_new_tokens,
            row_temps=None, on_box=None, on_diag=None):
    """Shared batched fast-MTP decode. ... `on_box` (optional, batch-level) is called
    once each time a box operation completes during decoding, with signature
    `on_box(row_index, normalized_box, elapsed_ms)` where normalized_box is a
    4-element list [x1,y1,x2,y2] in 0..1 and elapsed_ms is the wall-clock time
    elapsed since the first decode step started. `on_diag` (optional) is called
    once per decoded op with `{'b', 'op_type', 'is_empty_box', 'finished'}`."""
    tok, proc, model = load()
    _set_llm_mode(model, "sdpa")          # MTP window is bidirectional -> decode is sdpa-only
    san, hpat = _helpers()
    tids = model.token_ids
    IMG = model.config.image_token_index
    MASK = tids['default_mask_token_id']
    IM_END = tids['im_end_token_id']
    PAD = tok.pad_token_id if tok.pad_token_id is not None else IM_END
    B = len(prompt_ids)
    dev = DEV

    npos = [int(L[b]) for b in range(B)]                          # next REAL position per row
    last_real = [int(prompt_ids[b][-1]) for b in range(B)]        # row's last real token id
    gen_ids = [[] for _ in range(B)]                              # accepted real tokens per row
    finished = [False] * B
    prev = None                                                   # (acc_ids[B][k], acc_pos[B][k])

    def _mk_gk(t):
        gk = {'repetition_penalty': repetition_penalty, 'generation_mode': 'fast'}
        if t and t > 0: gk['temperature'] = t
        if top_p is not None: gk['top_p'] = top_p
        if top_k is not None: gk['top_k'] = top_k
        return gk
    # per-row sampling kwargs: row_temps lets one batch-15 cover 5 prompts x 3 temps.
    row_gks = [_mk_gk(row_temps[b] if row_temps is not None else temperature) for b in range(B)]
    # per-row temperature vector for the batched san (BATCH_SAN); 0 -> greedy/argmax row.
    per_row_temp = torch.tensor(
        [float(row_temps[b]) if row_temps is not None else float(temperature or 0.0) for b in range(B)],
        dtype=torch.float32, device=dev)

    steps = 0
    _t0 = time.perf_counter()
    _total_decode_ms = 0.0
    while not all(finished) and steps <= max_new_tokens:
        steps += 1
        _step_start = time.perf_counter()
        if prev is None:                                          # step 1: window only
            acc_ids = [[] for _ in range(B)]; acc_pos = [[] for _ in range(B)]
        else:
            acc_ids, acc_pos = prev
        max_k = max((len(a) for a in acc_ids), default=0)
        S = max_k + N_FUTURE

        # ---- build the suffix [accepted-block (max_k) | window (6)] ----
        suf_ids = torch.full((B, S), PAD, dtype=torch.long, device=dev)
        suf_pos = torch.ones((B, S), dtype=torch.long, device=dev)        # default dummy=1
        new_valid = torch.zeros((B, max_k), dtype=torch.long, device=dev) if max_k else None
        for b in range(B):
            k = len(acc_ids[b])
            for j in range(k):                                    # accepted real tokens
                suf_ids[b, j] = acc_ids[b][j]; suf_pos[b, j] = acc_pos[b][j]
                new_valid[b, j] = 1
            # window: [repeat(last real), MASK x (N_FUTURE-1)]
            rep = acc_ids[b][-1] if k else last_real[b]
            rep_pos = acc_pos[b][-1] if k else (npos[b] - 1)      # stock -1 offset trick
            suf_ids[b, max_k] = rep; suf_pos[b, max_k] = rep_pos
            for j in range(1, N_FUTURE):
                suf_ids[b, max_k + j] = MASK
                suf_pos[b, max_k + j] = npos[b] + (j - 1)         # masks at npos..npos+4

        # ---- full 2D attention mask over [kvlen + S] ----
        win_valid = torch.ones((B, N_FUTURE), dtype=torch.long, device=dev)
        right = torch.cat([new_valid, win_valid], dim=1) if max_k else win_valid
        full_mask = torch.cat([kvalid, right], dim=1)             # [B, kvlen+S]

        # ---- forward (CausalLM: logits only over the short suffix) ----
        out = model.language_model(input_ids=suf_ids, attention_mask=full_mask,
                                   position_ids=suf_pos, past_key_values=kv, use_cache=True)
        keep = kvlen + max_k                                      # drop the 6-wide window KV
        kv = _trunc_kv(out.past_key_values, keep)
        if max_k:
            kvalid = torch.cat([kvalid, new_valid], dim=1); kvlen = keep

        # ---- decode the window per row (the model's OWN exact decoders) ----
        # The box ASSEMBLY (decode_bbox_avg -> ragged shapes) must stay per row (sample_tokens'
        # final torch.stack throws on mixed shapes). BATCH_SAN runs the row-independent logits
        # pipeline ONCE over [B,6,V] (sample_tokens_batched) and keeps only that assembly per row;
        # greedy is bit-identical to the per-row san. BATCH_SAN=0 -> the original per-row san.
        wlogits = out.logits[:, -N_FUTURE:, :]                    # [B, 6, V]
        gen_pad = _pad_generated(prompt_ids, gen_ids, IMG, dev)   # [B, M] for repetition penalty
        nt_cpu = None
        if BATCH_SAN and BATCH_BOXDECODE:                        # fully-GPU box-decode: ONE host xfer/step
            nt_all = sample_tokens_batched(
                wlogits, gen_pad, tids, per_row_temp,
                repetition_penalty=repetition_penalty, top_p=top_p, top_k=top_k,
                keep_k_avg=4, generation_mode='fast', fused=True)
            nt_cpu = nt_all.cpu()                                 # the only GPU->CPU sync in the row loop
        elif BATCH_SAN:
            x0_all, boxes_all = sample_tokens_batched(
                wlogits, gen_pad, tids, per_row_temp,
                repetition_penalty=repetition_penalty, top_p=top_p, top_k=top_k,
                keep_k_avg=4, generation_mode='fast')
        nai = [[] for _ in range(B)]; nap = [[] for _ in range(B)]
        for b in range(B):
            if finished[b]:
                continue
            if nt_cpu is not None:
                nt = nt_cpu[b]                                    # CPU tensor -> hpat's .tolist() is sync-free
                is_empty = False                                   # BATCH_BOXDECODE path: full-decode already produced 6 tokens
            else:
                if BATCH_SAN:
                    x0b, boxb = x0_all[b], boxes_all[b]
                else:
                    _, _, x0, box_avg = san(wlogits[b:b + 1], gen_pad[b:b + 1], tids, keep_k=5, **row_gks[b])
                    x0b, boxb = x0[0], box_avg[0]
                is_empty = bool((boxb == 0).all())
                nt = x0b if is_empty else boxb
            op = hpat(nt, tids, 'fast')                           # fast: never error_box/AR
            if on_diag is not None:
                on_diag({'b': b, 'op_type': op['type'],
                         'is_empty_box': is_empty, 'finished': finished[b]})
            if op['type'] == 'im_end':
                gen_ids[b].append(IM_END)                          # stock appends it before break
                finished[b] = True; continue
            if op['type'] in ('coord_box', 'point_box') and on_box is not None:
                elapsed_ms = (time.perf_counter() - _t0) * 1000 - _total_decode_ms
                # op['tokens'] contains VOCAB IDs. The tokenizer maps coord tokens to <N> strings
                # (each digit = one token). Decode + strip <> to get digit strings, then parse.
                tok = _tok
                coord_ids = op['tokens'][1:-1]
                digit_strs = [tok.decode(tid).strip().lstrip('<').rstrip('>') for tid in coord_ids]
                coords = [float(s) for s in digit_strs]
                normalized_box = [c / 1000 for c in coords]
                on_box(b, normalized_box, elapsed_ms)
            toks = [int(t) for t in op['tokens']]
            start = npos[b]
            for j, t in enumerate(toks):
                nai[b].append(t); nap[b].append(start + j); gen_ids[b].append(t)
            npos[b] = start + len(toks); last_real[b] = toks[-1]
            if npos[b] - L[b] >= max_new_tokens:                  # per-row length cap
                finished[b] = True
        _total_decode_ms += (time.perf_counter() - _step_start) * 1000
        prev = (nai, nap)

    return [tok.decode(torch.tensor(gen_ids[b], dtype=torch.long, device=dev),
                       skip_special_tokens=False) if gen_ids[b] else "" for b in range(B)]


def _lcp_len(id_lists):
    """Longest common token prefix length across several id lists."""
    m = min(len(a) for a in id_lists)
    for i in range(m):
        if any(a[i] != id_lists[0][i] for a in id_lists):
            return i
    return m


def _stack_prefix_kv(group_kvs, group_nq, Lpmax, dev):
    """Build [B,2,Lpmax,128]x36 from per-group prefix KV: left-pad each group's KV to Lpmax
    (pad slots masked later) and expand to that group's row count. .clone() so rows don't
    alias shared storage (they diverge during decode)."""
    nlayers = len(group_kvs[0])
    out = []
    for l in range(nlayers):
        ks, vs = [], []
        for kv_g, nq in zip(group_kvs, group_nq):
            k, v = kv_g[l]                                        # [1,2,Lp,128]
            Lp = k.shape[2]
            if Lp < Lpmax:                                       # left-pad (different image sizes)
                pk = k.new_zeros((1, k.shape[1], Lpmax - Lp, k.shape[3]))
                pv = v.new_zeros((1, v.shape[1], Lpmax - Lp, v.shape[3]))
                k = torch.cat([pk, k], dim=2); v = torch.cat([pv, v], dim=2)
            ks.append(k.expand(nq, -1, -1, -1).clone())
            vs.append(v.expand(nq, -1, -1, -1).clone())
        out.append((torch.cat(ks, dim=0), torch.cat(vs, dim=0)))
    return tuple(out)


@torch.no_grad()
def generate_batch_grouped(groups, temperature=0.0, top_p=None, top_k=None,
                           repetition_penalty=1.0, max_new_tokens=MNT, temps=None):
    """Prefix-KV / vision reuse. groups = [(PIL image, [query, ...]), ...]. For each image
    the [image tokens + instruction] prefix is vision-encoded + LLM-prefilled ONCE and forked
    to that image's queries; only the differing query TAILS + decode are batched across ALL
    rows of ALL groups. Returns list[list[str]] aligned with groups (one str per query).
    temps (optional) = per-row temperatures in row order (concat of each group's queries).

    On sdpa, split (shared-prefix prefill | tail prefill | decode) is numerically equivalent
    to one-shot prefill (the standard split-prefill argument), modulo bf16 batched-GEMM nondeterminism.
    """
    tok, proc, model = load()
    tids = model.token_ids
    IMG = model.config.image_token_index
    PAD = tok.pad_token_id if tok.pad_token_id is not None else tids['im_end_token_id']
    base = model.language_model.model
    dev = DEV
    if USE_FLASH_PREFILL:
        _set_llm_mode(model, "flash")           # whole prefill phase is plain causal

    group_nq = [len(q) for _, q in groups]
    row_full, row_tail, row_Lp = [], [], []
    prefixes, Lps = [], []
    for im, queries in groups:
        pids = [_tokenize(im, q) for q in queries]
        Lp = _lcp_len([p.tolist() for p in pids])                # = image tokens + instruction stem
        prefixes.append(pids[0][:Lp]); Lps.append(Lp)
        for p in pids:
            row_full.append(p); row_tail.append(p[Lp:]); row_Lp.append(Lp)
    vits = _encode_images([im for im, _ in groups])              # MoonViT batched (flash) or per-image
    for vit, prefix in zip(vits, prefixes):
        assert int((prefix == IMG).sum().item()) == vit.shape[0], \
            "image tokens not fully inside the shared prefix"

    G, Lpmax = len(groups), max(Lps)
    if BATCH_PREFILL and G > 1:
        # ONE batched shared-prefix prefill: left-pad the G prefixes to Lpmax, scatter all images'
        # visual_features row-order (same contract as generate_batch's one-shot prefill), one base()
        # -> [G,H,Lpmax,D]x36 KV, then slice per group for the fork. ~3.6x vs per-image batch=1 (the
        # 66-token prefix is GPU-starved -- benchmarked). Plain causal (prefix ends on the
        # instruction stem, not a mask token -> modeling_qwen2 _prepare_block_mask guard returns the
        # standard 4d causal mask), so split-prefill equivalence holds; only new noise is bf16
        # batched-GEMM reduction order (~1e-3, same as the tail prefill). Masked left-pad columns
        # (kvalid_pre=0) contribute nothing, so the PAD-token KV there is harmless.
        pin = torch.full((G, Lpmax), PAD, dtype=torch.long, device=dev)
        pam = torch.zeros((G, Lpmax), dtype=torch.long, device=dev)
        ppos = torch.ones((G, Lpmax), dtype=torch.long, device=dev)             # left-pad dummy=1
        for g in range(G):
            pin[g, Lpmax - Lps[g]:] = prefixes[g]
            pam[g, Lpmax - Lps[g]:] = 1
            ppos[g, Lpmax - Lps[g]:] = torch.arange(0, Lps[g], device=dev)
        if USE_FLASH_PREFILL: _stash_pad2d(model, pam)
        po = base(input_ids=pin, visual_features=torch.cat(vits, dim=0), image_token_index=IMG,
                  attention_mask=pam, position_ids=ppos, past_key_values=None, use_cache=True)
        kvfull = po.past_key_values                              # [G,H,Lpmax,D]x36
        group_kvs = [tuple((k[g:g + 1], v[g:g + 1]) for (k, v) in kvfull) for g in range(G)]
    else:
        group_kvs = []                                          # per-image (MTP_BATCH_PREFILL=0 / G==1)
        for vit, prefix, Lp in zip(vits, prefixes, Lps):
            ppos = torch.arange(0, Lp, device=dev).unsqueeze(0)
            pam = torch.ones((1, Lp), dtype=torch.long, device=dev)
            if USE_FLASH_PREFILL: _stash_pad2d(model, pam)
            po = base(input_ids=prefix.unsqueeze(0), visual_features=vit, image_token_index=IMG,
                      attention_mask=pam, position_ids=ppos, past_key_values=None, use_cache=True)
            group_kvs.append(po.past_key_values)

    B = len(row_full)
    Lpmax = max(row_Lp)
    kv = _stack_prefix_kv(group_kvs, group_nq, Lpmax, dev)       # [B,2,Lpmax,128]x36
    kvalid_pre = torch.zeros((B, Lpmax), dtype=torch.long, device=dev)
    for b in range(B):
        kvalid_pre[b, Lpmax - row_Lp[b]:] = 1

    # ---- batched tail prefill (left-pad tails), seeded with the forked prefix KV ----
    Tmax = max(int(t.numel()) for t in row_tail)
    assert Tmax > 0, "every query must have a non-empty tail after the shared prefix"
    tin = torch.full((B, Tmax), PAD, dtype=torch.long, device=dev)
    tam = torch.zeros((B, Tmax), dtype=torch.long, device=dev)
    tpos = torch.ones((B, Tmax), dtype=torch.long, device=dev)
    for b in range(B):
        tl = int(row_tail[b].numel())
        tin[b, Tmax - tl:] = row_tail[b]
        tam[b, Tmax - tl:] = 1
        tpos[b, Tmax - tl:] = torch.arange(row_Lp[b], row_Lp[b] + tl, device=dev)  # continue real pos
    full_mask = torch.cat([kvalid_pre, tam], dim=1)              # [B, Lpmax+Tmax]
    if USE_FLASH_PREFILL: _stash_pad2d(model, full_mask)
    out = base(input_ids=tin, attention_mask=full_mask, position_ids=tpos,
               past_key_values=kv, use_cache=True)               # no visual_features (image in prefix KV)
    if USE_FLASH_PREFILL: _set_llm_mode(model, "sdpa")           # decode must be sdpa (bidir window)
    kv = out.past_key_values
    kvlen = Lpmax + Tmax
    kvalid = torch.cat([kvalid_pre, tam], dim=1)
    L = [row_Lp[b] + int(row_tail[b].numel()) for b in range(B)]

    texts = _decode(row_full, L, kv, kvlen, kvalid,
                    temperature, top_p, top_k, repetition_penalty, max_new_tokens, row_temps=temps)
    res, i = [], 0
    for nq in group_nq:
        res.append(texts[i:i + nq]); i += nq
    return res


def _pad_generated(prompt_ids, gen_ids, img_tok, dev):
    """Per-row [prompt + accepted] left-padded with the image token (already in every
    prompt -> .unique() unchanged -> repetition penalty identical to single-run)."""
    rows = [list(prompt_ids[b].tolist()) + gen_ids[b] for b in range(len(prompt_ids))]
    M = max(len(r) for r in rows)
    out = torch.full((len(rows), M), img_tok, dtype=torch.long, device=dev)
    for b, r in enumerate(rows):
        out[b, M - len(r):] = torch.tensor(r, dtype=torch.long, device=dev)
    return out
