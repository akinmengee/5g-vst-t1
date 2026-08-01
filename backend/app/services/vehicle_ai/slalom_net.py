"""Slalom tespiti için LSTM ağı — FTR'deki `predict.py`'den birebir taşındı.

Ağırlık dosyası (`slalom_lstm.pt`) bu sınıf tanımına göre eğitildiği için mimari
DEĞİŞTİRİLMEMELİDİR.
"""

import torch
import torch.nn as nn


class SlalomLSTM(nn.Module):
    def __init__(self, input_size: int = 1, hidden_size: int = 128, num_layers: int = 2) -> None:
        super().__init__()
        self.hidden_size = hidden_size
        self.num_layers = num_layers
        self.lstm = nn.LSTM(input_size, hidden_size, num_layers, batch_first=True)
        self.fc = nn.Linear(hidden_size, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        h0 = torch.zeros(self.num_layers, x.size(0), self.hidden_size).to(x.device)
        c0 = torch.zeros(self.num_layers, x.size(0), self.hidden_size).to(x.device)
        out, _ = self.lstm(x, (h0, c0))
        out = out[:, -1, :]
        return self.fc(out)
