import os
import shutil
import warnings


def _build_help_message(exc=None):
    details = ""
    if exc is not None:
        details = f" (pycuda import error: {exc.__class__.__name__}: {exc})"

    nvcc_hint = ""
    if shutil.which("nvcc") is None:
        nvcc_hint = (
            " nvcc not found on PATH; install the CUDA Toolkit and export "
            "CUDA_HOME and PATH."
        )

    cuda_inc_hint = ""
    if os.environ.get("CUDA_INC_DIR") is None:
        cuda_inc_hint = (
            " If CUDA headers are not in a standard location, set CUDA_INC_DIR."
        )

    return (
        "GPU support is unavailable." + details +
        " Install PyCUDA prerequisites: CUDA Toolkit (nvcc), "
        "and Python development headers (pyconfig.h)." +
        nvcc_hint + cuda_inc_hint
    )


def try_import_pycuda(warn=True):
    """
    Attempt to import PyCUDA. Returns (available, module_or_none).
    If warn=True, emit a RuntimeWarning with actionable setup hints.
    """
    try:
        import pycuda.driver as cuda  # type: ignore
        return True, cuda
    except Exception as exc:  # noqa: BLE001 - user environment issues
        if warn:
            warnings.warn(_build_help_message(exc), RuntimeWarning, stacklevel=2)
        return False, None


def warn_if_no_gpu():
    """
    Emit a warning if PyCUDA is unavailable. Returns True if available.
    """
    ok, _ = try_import_pycuda(warn=True)
    return ok
