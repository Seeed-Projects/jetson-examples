"""locateanything-batch — batched + KV-cached fast-MTP inference for NVIDIA LocateAnything-3B.

The stock model's custom ``generate`` hard-asserts ``batch == 1``. This package is a faithful
batched fork of its fast-mode MTP decode loop (with vision / shared-prefix / KV reuse) that is
numerically equivalent to running each pair at ``batch == 1`` under greedy decoding.

Quickstart::

    from locateanything_batch import load, generate_batch, load_pil
    load()                                          # lazily downloads / loads the model
    img = load_pil("photo.jpg")
    [answer] = generate_batch([(img, "a dog")])     # one (image, query) pair -> one string

See ``generate_batch_grouped`` for same-image multi-prompt prefix/vision reuse, and the module
docstring of ``locateanything_batch.engine`` for the ``MTP_*`` / ``LA3B_MODEL`` env knobs.
"""
from .engine import load, generate_batch, generate_batch_grouped, load_pil

__all__ = ["load", "generate_batch", "generate_batch_grouped", "load_pil"]
__version__ = "0.1.0"
