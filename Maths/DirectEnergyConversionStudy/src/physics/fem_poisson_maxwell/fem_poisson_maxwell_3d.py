
import numpy as np

def assemble_poisson_3d(nx, ny, nz, dx, epsilon0):
    N = nx*ny*nz
    A = np.zeros((N,N))
    b = np.zeros(N)
    return A, b

def solve_system(A, b):
    return np.linalg.solve(A, b)
