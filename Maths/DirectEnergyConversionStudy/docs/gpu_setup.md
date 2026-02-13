# GPU Setup (PyCUDA)

If `pip install -r requirements-gpu.txt` fails with errors like:

- "nvcc not in path"
- "pyconfig.h: No such file or directory"

install the prerequisites below.

## 1) CUDA Toolkit (nvcc)

Ensure `nvcc` is available:

```bash
nvcc --version
```

If `nvcc` is missing, install the CUDA Toolkit and export the paths:

```bash
export CUDA_HOME=/usr/local/cuda
export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"
```

If CUDA headers are in a non-standard location, set:

```bash
export CUDA_INC_DIR=/path/to/cuda/include
```

## 2) Python Development Headers (pyconfig.h)

PyCUDA needs the Python headers for your interpreter.

Check where Python expects them:

```bash
python - <<'PY'
import sysconfig
print(sysconfig.get_config_var("INCLUDEPY"))
PY
```

That directory must contain `pyconfig.h`.

Examples:

- Ubuntu/Debian:

```bash
sudo apt-get update
sudo apt-get install -y build-essential python3-dev
# For a specific version:
sudo apt-get install -y python3.10-dev
```

- Fedora/RHEL:

```bash
sudo dnf install -y gcc-c++ python3-devel
```

## 3) Install GPU Requirements

```bash
pip install -r requirements.txt -r requirements-gpu.txt
```
