
import numpy as np

def reactivity_feedback(temp, alpha):
    return -alpha * (temp - 300)

def transient_step(power, temp, alpha, dt):
    rho = reactivity_feedback(temp, alpha)
    power += rho * power * dt
    temp += power * dt * 1e-6
    return power, temp
