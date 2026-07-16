# torchvision.io stub for aarch64 Jetson — no usable aarch64 torchvision wheel
# matches the Jetson (v61) torch, so we ship a stub. LocateAnything's image-only
# grounding decodes JPEGs via PIL (Pillow), never the torchvision.io C ops. But
# transformers >=4.5x imports their *names* (decode_jpeg, encode_jpeg, ImageReadMode,
# ...) at module load. Module-level __getattr__ returns a callable stub for any
# name so those imports succeed; actually *calling* one raises NotImplementedError.
class _Stub:
    __slots__ = ("_name",)
    def __init__(self, name): self._name = name
    def __call__(self, *a, **k):
        raise NotImplementedError(f"torchvision.io stub: {self._name}() not available on aarch64 Jetson")
    def __getattr__(self, attr):  # e.g. ImageReadMode.RGB -> nested stub (no crash on attribute access)
        return _Stub(f"{self._name}.{attr}")
    def __repr__(self): return f"<torchvision.io stub {self._name}>"


def __getattr__(name):  # PEP 562: called for names not defined in this module
    return _Stub(name)


def read_video(*args, **kwargs):
    raise NotImplementedError("torchvision stub: video decoding unavailable on aarch64 Jetson")


def read_video_timestamps(*args, **kwargs):
    raise NotImplementedError("torchvision stub: video decoding unavailable on aarch64 Jetson")


def write_video(*args, **kwargs):
    raise NotImplementedError("torchvision stub: video encoding unavailable on aarch64 Jetson")
