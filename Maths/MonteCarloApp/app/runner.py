from MonteCarloApp.app.reinforce import reinforce_with_baseline
from MonteCarloApp.app.bnn import BNN_MC_Dropout, predict_mc
from MonteCarloApp.app.diffusion import sample_numpyro_mc

def run_all():
    reinforce_with_baseline()
    import torch
    import matplotlib.pyplot as plt
    model = BNN_MC_Dropout()
    x = torch.linspace(-3, 3, 100).unsqueeze(1)
    mean, std = predict_mc(model, x)
    plt.plot(x.numpy(), mean.detach().numpy())
    plt.fill_between(x.squeeze().numpy(), (mean - 2*std).squeeze().detach().numpy(), (mean + 2*std).squeeze().detach().numpy(), alpha=0.3)
    plt.title("BNN MC-Dropout Uncertainty")
    plt.show()
    from jax import random
    rng_key = random.PRNGKey(0)
    sample_numpyro_mc(rng_key)