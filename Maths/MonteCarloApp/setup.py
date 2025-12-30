from setuptools import setup, find_packages

setup(
    name='MonteCarloApp',
    version='0.1',
    packages=find_packages(),
    install_requires=open('requirements.txt').readlines(),
    entry_points={'console_scripts': ['monte-carlo-app=run:main']},
    author='Fernando Avanzo',
    description='Monte Carlo modeling suite including RL, BNNs, and generative models'
)