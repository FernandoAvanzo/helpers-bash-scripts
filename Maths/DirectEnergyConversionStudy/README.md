# Direct Nuclear Energy Conversion Study Project

Author: Physics Research Simulation  
Created: 2026-02-13

## Overview

This repository contains research-grade simulations and theoretical models for:

- Direct fission fragment energy conversion
- Fusion charged particle direct conversion
- Space-charge modeling
- Plasma shielding effects
- Magnetic collimation
- Hybrid electrostatic-thermal reactor modeling
- Economic modeling comparison

The goal of this project is to build a scalable research framework for advanced nuclear energy systems.

---

## Project Structure

```
src/
    simulations/        # Monte Carlo and particle tracking simulations
    models/             # Analytical physics models
    utils/              # Shared physical constants and helpers
docs/                   # Markdown theory documentation
notebooks/              # Future Jupyter notebooks
data/                   # Output data files
```

---

## How to Run

Install requirements:

```bash
pip install -r requirements.txt
```

Run example simulation:

```bash
python src/simulations/monte_carlo_3d.py
```

---

## Future Extensions

- Full Maxwell solver
- Self-consistent Poisson-Boltzmann solver
- Magnet quench modeling
- Lifecycle economic simulation
- Fusion reactor optimization

