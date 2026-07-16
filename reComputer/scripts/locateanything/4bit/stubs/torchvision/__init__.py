"""torchvision stub for image-only inference on aarch64 Jetson (no working wheel
vs the Jetson torch build). Provides InterpolationMode (incl. NEAREST_EXACT),
transforms.functional.to_tensor/normalize/resize, and transforms.v2.functional
delegate (transformers 4.57 imports v2). Video (io.read_video) raises."""
__version__ = "0.20.1"
from . import transforms  # noqa
