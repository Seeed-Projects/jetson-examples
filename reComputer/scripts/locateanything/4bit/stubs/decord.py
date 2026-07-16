"""decord stub: no aarch64 wheel (x86_64 only). The LocateAnything processor
imports decord at module top-level but only USES it for video (VideoReader).
Image-only inference never calls VideoReader, so this stub lets the import
succeed. Build real decord from source if you need video."""


class VideoReader:
    def __init__(self, *args, **kwargs):
        raise NotImplementedError("decord stub: no aarch64 wheel; video unavailable")


class cpu:
    pass


class gpu:
    pass


def ndarray(*args, **kwargs):
    raise NotImplementedError("decord stub: no aarch64 wheel")
