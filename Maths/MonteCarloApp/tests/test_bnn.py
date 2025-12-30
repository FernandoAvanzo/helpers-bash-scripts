import torch
from MonteCarloApp.app.bnn import BNN_MC_Dropout, predict_mc

def test_bnn_prediction_shape():
    model = BNN_MC_Dropout()
    x = torch.linspace(-2, 2, 10).unsqueeze(1)
    mean, std = predict_mc(model, x, n_samples=10)
    assert mean.shape == x.shape
    assert std.shape == x.shape