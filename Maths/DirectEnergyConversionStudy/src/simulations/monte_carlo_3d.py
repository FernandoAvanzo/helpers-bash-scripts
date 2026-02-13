from __future__ import annotations

import os
import sys

import numpy as np
import matplotlib.pyplot as plt

# Allow running as a script without installing the package.
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from src.utils.constants import e
from src.utils.gpu import warn_if_no_gpu

def simulate(N=10000, use_gpu=False):
    if use_gpu:
        # GPU path not implemented; warn and fall back to CPU.
        warn_if_no_gpu()

    q = 20*e
    m = 1.6e-25
    E_particle = 100e6*e
    v0 = np.sqrt(2*E_particle/m)

    theta = np.arccos(1-2*np.random.rand(N))
    vz = v0*np.cos(theta)

    efficiency = np.mean(vz[vz>0]/v0)
    return efficiency

if __name__ == "__main__":
    eff = simulate()
    print("Monte Carlo Efficiency:", eff)
