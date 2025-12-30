from torch import nn, optim
import torch
import gym

class PolicyNetwork(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(4, 16)
        self.fc2 = nn.Linear(16, 2)

    def forward(self, x):
        x = torch.relu(self.fc1(x))
        return torch.softmax(self.fc2(x), dim=-1)

def reinforce_with_baseline(env_name="CartPole-v1", episodes=1000):
    env = gym.make(env_name)
    policy = PolicyNetwork()
    baseline = torch.zeros(1, requires_grad=True)
    optimizer = optim.Adam(list(policy.parameters()) + [baseline], lr=1e-2)
    for episode in range(episodes):
        state = env.reset()[0]
        log_probs, rewards = [], []
        done = False
        while not done:
            state_tensor = torch.tensor(state, dtype=torch.float32)
            probs = policy(state_tensor)
            m = torch.distributions.Categorical(probs)
            action = m.sample()
            log_probs.append(m.log_prob(action))
            state, reward, done, _ = env.step(action.item())
            rewards.append(reward)
        returns, G = [], 0
        for r in reversed(rewards):
            G = r + 0.99 * G
            returns.insert(0, G)
        returns = torch.tensor(returns)
        entropy = -torch.stack(log_probs).mean()
        baseline_loss = ((returns - baseline) ** 2).mean()
        pg_loss = -torch.stack(log_probs) @ (returns - baseline.detach())
        loss = pg_loss + baseline_loss - 0.01 * entropy
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
    env.close()