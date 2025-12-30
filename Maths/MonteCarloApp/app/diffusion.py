import numpyro
import numpyro.distributions as dist
import jax.numpy as jnp

def sample_numpyro_mc(rng_key, latent_dim=4, n_samples=1000):
    def model():
        return numpyro.sample("latent", dist.Normal(0, 1).expand([latent_dim]))
    samples = jnp.stack([model() for _ in range(n_samples)])
    print("Sampled NumPyro latent MC mean:", samples.mean(axis=0))
    return samples