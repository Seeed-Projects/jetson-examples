import sys
import numpy as np
import torch
from PIL import Image
from enum import Enum


class InterpolationMode(Enum):
    NEAREST = 0
    NEAREST_EXACT = 1
    BILINEAR = 2
    BICUBIC = 3
    BOX = 4
    HAMMING = 5
    LANCZOS = 6


_PIL = {0: Image.NEAREST, 1: Image.NEAREST, 2: Image.BILINEAR, 3: Image.BICUBIC,
        4: Image.BOX, 5: Image.HAMMING, 6: Image.LANCZOS}


def to_tensor(pic):
    if isinstance(pic, Image.Image):
        if pic.mode == "I;16":
            a = np.array(pic, dtype=np.int32)
        elif pic.mode == "I":
            a = np.array(pic, dtype=np.int32)
        elif pic.mode == "F":
            a = np.array(pic, dtype=np.float32)
        else:
            a = np.array(pic, dtype=np.uint8)
        t = torch.from_numpy(a)
        if t.ndim == 2:
            t = t.unsqueeze(-1)
        t = t.permute(2, 0, 1).contiguous()
        return t.float().div(255.0) if t.dtype == torch.uint8 else t
    if isinstance(pic, np.ndarray):
        t = torch.from_numpy(pic.copy())
        if t.ndim == 2:
            t = t.unsqueeze(-1)
        if t.ndim == 3:
            t = t.permute(2, 0, 1).contiguous()
        return t.float().div(255.0) if t.dtype == torch.uint8 else t
    if torch.is_tensor(pic):
        return pic
    raise TypeError(f"to_tensor: unsupported {type(pic)}")


def pil_to_tensor(pic):
    """PIL Image -> tensor (C x H x W), NO normalization (uint8/int/float as-is)."""
    if not isinstance(pic, Image.Image):
        raise TypeError(f"pil_to_tensor: expected PIL Image, got {type(pic)}")
    if pic.mode == "P":
        pic = pic.convert("RGB")
    if pic.mode == "I;16":
        a = np.array(pic, dtype=np.int16)
    elif pic.mode == "I":
        a = np.array(pic, dtype=np.int32)
    elif pic.mode == "F":
        a = np.array(pic, dtype=np.float32)
    else:
        a = np.array(pic, dtype=np.uint8)
    t = torch.from_numpy(a)
    if t.ndim == 2:
        t = t.unsqueeze(-1)
    return t.permute(2, 0, 1).contiguous()


def to_pil_image(pic, mode=None):
    """tensor/ndarray (C x H x W or H x W) -> PIL Image."""
    if isinstance(pic, torch.Tensor):
        pic = pic.cpu().numpy()
    if not isinstance(pic, np.ndarray):
        raise TypeError(f"to_pil_image: expected Tensor/ndarray, got {type(pic)}")
    if pic.ndim not in (2, 3):
        raise ValueError(f"to_pil_image: bad ndim {pic.ndim}")
    if pic.ndim == 3:
        pic = np.transpose(pic, (1, 2, 0))  # C H W -> H W C
    if pic.ndim == 2:
        pic = pic[..., None]
    if np.issubdtype(pic.dtype, np.floating):
        pic = np.clip(pic, 0, 1) if pic.max() <= 1.0 else pic
        pic = (pic * 255).round().astype(np.uint8)
    elif pic.dtype != np.uint8:
        pic = pic.astype(np.uint8)
    c = pic.shape[-1]
    if mode is None:
        mode = {1: "L", 2: "LA", 3: "RGB", 4: "RGBA"}.get(c, "RGB")
    if c == 1:
        pic = pic[..., 0]
    return Image.fromarray(pic, mode=mode)


def normalize(tensor, mean, std):
    d = tensor.dtype
    mean = torch.as_tensor(mean, dtype=d, device=tensor.device).view(-1, 1, 1)
    std = torch.as_tensor(std, dtype=d, device=tensor.device).view(-1, 1, 1)
    return tensor.sub(mean).div(std)


def resize(img, size, interpolation=InterpolationMode.BILINEAR, max_size=None, antialias=True):
    if isinstance(img, Image.Image):
        if isinstance(size, int):
            size = (size, size)
        m = interpolation.value if isinstance(interpolation, InterpolationMode) else interpolation
        return img.resize(size[::-1], _PIL.get(m, Image.BILINEAR))
    raise TypeError(f"resize: unsupported {type(img)}")


class _Stub:
    __slots__ = ("_name",)
    def __init__(self, name): self._name = name
    def __call__(self, *a, **k):
        raise NotImplementedError(f"torchvision.transforms.functional stub: {self._name}() not available on aarch64 Jetson")
    def __getattr__(self, attr):
        return _Stub(f"{self._name}.{attr}")
    def __repr__(self):
        return f"<tvf stub {self._name}>"


def __getattr__(name):
    # PEP 562: any other name imported from torchvision.transforms.functional
    # (e.g. by the real v2/functional/_augment.py) returns a callable stub so
    # the import succeeds; calling it raises NotImplementedError.
    return _Stub(name)
