import numpy as np
from src.utils.constants import epsilon0, kB, e

def debye_length(Te, ne):
    return np.sqrt(epsilon0 * kB * Te / (ne * e**2))
