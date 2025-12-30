import torch
import torch.nn as nn
import torch.nn.functional as F

def predict_mc(model, x, n_samples=100):
    model.train()
    preds = torch.stack([model(x) for _ in range(n_samples)])
    return preds.mean(0), preds.std(0)

class BNN_MC_Dropout(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(1, 64)
        self.drop = nn.Dropout(p=0.1)
        self.fc2 = nn.Linear(64, 1)

    def forward(self, x):
        x = F.relu(self.fc1(x))
        x = self.drop(x)
        return self.fc2(x)