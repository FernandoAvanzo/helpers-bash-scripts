import numpy as np
import matplotlib.pyplot as plt
from src.utils.constants import e

def simulate(N=10000):
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
