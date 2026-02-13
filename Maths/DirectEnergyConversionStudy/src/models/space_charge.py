import numpy as np
from src.utils.constants import epsilon0

def child_langmuir_current(q, m, V, d):
    return (4/9)*epsilon0*np.sqrt(2*q/m)*(V**1.5)/(d**2)
