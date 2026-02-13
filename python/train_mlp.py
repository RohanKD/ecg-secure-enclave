#!/usr/bin/env python3
"""
train_mlp.py — Train and quantize a 10→8→2 MLP for ECG beat classification.
Uses MIT-BIH Arrhythmia Database features (or synthetic data for testing).
Exports quantized weights for FPGA deployment.

Usage:
  python train_mlp.py --synthetic   (train on synthetic data for testing)
  python train_mlp.py --data mitbih_features.npz  (train on real features)
"""

import argparse
import numpy as np
import os

try:
    import torch
    import torch.nn as nn
    import torch.optim as optim
    from torch.utils.data import DataLoader, TensorDataset
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False
    print("PyTorch not available. Using numpy-only training (limited).")


class ECGClassifierTorch(nn.Module):
    """10 → 8 (ReLU) → 2 MLP for ECG classification."""
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(10, 8)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(8, 2)

    def forward(self, x):
        x = self.relu(self.fc1(x))
        x = self.fc2(x)
        return x


def generate_synthetic_data(n_samples=5000):
    """Generate synthetic ECG feature data for testing the pipeline.
    Normal beats: regular RR intervals, normal QRS width, normal amplitude.
    Abnormal beats: irregular RR, wide QRS, abnormal amplitude.
    """
    np.random.seed(42)

    # Normal beats (class 0) — ~70% of data
    n_normal = int(n_samples * 0.7)
    normal_features = np.random.randn(n_normal, 10).astype(np.float32) * 0.3
    # Set typical normal values
    normal_features[:, 0] = np.random.normal(1.6, 0.2, n_normal)   # RR ~800ms = 75 BPM
    normal_features[:, 1] = np.random.normal(1.6, 0.2, n_normal)   # Prev RR
    normal_features[:, 2] = np.random.normal(1.6, 0.15, n_normal)  # Mean RR
    normal_features[:, 3] = np.random.normal(0.2, 0.1, n_normal)   # RR variability (low)
    normal_features[:, 4] = np.random.normal(1.0, 0.1, n_normal)   # RR ratio ~1.0
    normal_features[:, 5] = np.random.normal(1.0, 0.1, n_normal)   # RR/mean ratio ~1.0
    normal_features[:, 6] = np.random.normal(0.5, 0.15, n_normal)  # QRS width (normal)
    normal_features[:, 7] = np.random.normal(1.5, 0.3, n_normal)   # Amplitude
    normal_features[:, 8] = np.random.normal(0.1, 0.05, n_normal)  # RR deviation (low)
    normal_features[:, 9] = np.random.normal(1.5, 0.2, n_normal)   # HR ~75

    # Abnormal beats (class 1) — ~30% of data
    n_abnormal = n_samples - n_normal
    abnormal_features = np.random.randn(n_abnormal, 10).astype(np.float32) * 0.3
    abnormal_features[:, 0] = np.random.normal(1.0, 0.5, n_abnormal)   # Irregular RR
    abnormal_features[:, 1] = np.random.normal(1.8, 0.4, n_abnormal)   # Different prev RR
    abnormal_features[:, 2] = np.random.normal(1.4, 0.3, n_abnormal)   # Mean RR varies
    abnormal_features[:, 3] = np.random.normal(0.8, 0.3, n_abnormal)   # High variability
    abnormal_features[:, 4] = np.random.normal(0.6, 0.3, n_abnormal)   # RR ratio off
    abnormal_features[:, 5] = np.random.normal(0.7, 0.3, n_abnormal)   # RR/mean ratio off
    abnormal_features[:, 6] = np.random.normal(1.2, 0.4, n_abnormal)   # Wide QRS
    abnormal_features[:, 7] = np.random.normal(2.5, 0.5, n_abnormal)   # High amplitude
    abnormal_features[:, 8] = np.random.normal(0.6, 0.3, n_abnormal)   # High deviation
    abnormal_features[:, 9] = np.random.normal(2.0, 0.5, n_abnormal)   # Abnormal HR

    features = np.vstack([normal_features, abnormal_features])
    labels = np.array([0] * n_normal + [1] * n_abnormal)

    # Shuffle
    idx = np.random.permutation(len(features))
    features = features[idx]
    labels = labels[idx]

    # Clip to Q3.5 range (-4.0 to 3.96875)
    features = np.clip(features, -4.0, 3.96875)

    return features, labels


def quantize_to_q35(value):
    """Quantize a float to Q3.5 format (8-bit signed, 5 fractional bits).
    Range: -4.0 to +3.96875, resolution: 0.03125
    """
    scale = 32  # 2^5
    q = int(np.round(value * scale))
    q = max(-128, min(127, q))
    return q & 0xFF  # Return as unsigned byte for hex export


def train_pytorch(features, labels, epochs=100, lr=0.01):
    """Train the MLP using PyTorch."""
    X = torch.FloatTensor(features)
    y = torch.LongTensor(labels)

    dataset = TensorDataset(X, y)
    loader = DataLoader(dataset, batch_size=64, shuffle=True)

    model = ECGClassifierTorch()
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=lr)

    for epoch in range(epochs):
        total_loss = 0
        correct = 0
        total = 0
        for batch_X, batch_y in loader:
            optimizer.zero_grad()
            outputs = model(batch_X)
            loss = criterion(outputs, batch_y)
            loss.backward()
            optimizer.step()

            total_loss += loss.item()
            _, predicted = outputs.max(1)
            correct += predicted.eq(batch_y).sum().item()
            total += batch_y.size(0)

        if (epoch + 1) % 20 == 0:
            acc = 100.0 * correct / total
            print(f"Epoch {epoch+1}/{epochs}: loss={total_loss/len(loader):.4f}, acc={acc:.1f}%")

    # Final accuracy
    model.eval()
    with torch.no_grad():
        outputs = model(X)
        _, predicted = outputs.max(1)
        acc = 100.0 * predicted.eq(y).sum().item() / len(y)
        print(f"\nFinal accuracy: {acc:.1f}%")

    return model


def train_numpy(features, labels, epochs=200, lr=0.01):
    """Simple numpy MLP training (fallback if no PyTorch)."""
    np.random.seed(42)
    n_in, n_hidden, n_out = 10, 8, 2

    # Xavier initialization
    W1 = np.random.randn(n_in, n_hidden).astype(np.float32) * np.sqrt(2.0 / n_in)
    b1 = np.zeros(n_hidden, dtype=np.float32)
    W2 = np.random.randn(n_hidden, n_out).astype(np.float32) * np.sqrt(2.0 / n_hidden)
    b2 = np.zeros(n_out, dtype=np.float32)

    for epoch in range(epochs):
        # Forward
        z1 = features @ W1 + b1
        a1 = np.maximum(0, z1)  # ReLU
        z2 = a1 @ W2 + b2
        # Softmax
        exp_z2 = np.exp(z2 - z2.max(axis=1, keepdims=True))
        probs = exp_z2 / exp_z2.sum(axis=1, keepdims=True)

        # Cross-entropy loss
        n = len(labels)
        loss = -np.log(probs[np.arange(n), labels] + 1e-8).mean()

        # Backward
        dz2 = probs.copy()
        dz2[np.arange(n), labels] -= 1
        dz2 /= n

        dW2 = a1.T @ dz2
        db2 = dz2.sum(axis=0)
        da1 = dz2 @ W2.T
        dz1 = da1 * (z1 > 0).astype(np.float32)
        dW1 = features.T @ dz1
        db1 = dz1.sum(axis=0)

        # Update
        W1 -= lr * dW1
        b1 -= lr * db1
        W2 -= lr * dW2
        b2 -= lr * db2

        if (epoch + 1) % 40 == 0:
            preds = np.argmax(z2, axis=1)
            acc = 100.0 * np.mean(preds == labels)
            print(f"Epoch {epoch+1}/{epochs}: loss={loss:.4f}, acc={acc:.1f}%")

    preds = np.argmax(features @ W1 + b1, axis=1)  # Simplified
    # Proper forward pass for final accuracy
    z1 = features @ W1 + b1
    a1 = np.maximum(0, z1)
    z2 = a1 @ W2 + b2
    preds = np.argmax(z2, axis=1)
    acc = 100.0 * np.mean(preds == labels)
    print(f"\nFinal accuracy: {acc:.1f}%")

    return W1, b1, W2, b2


def export_weights_torch(model, output_dir):
    """Export PyTorch model weights as .mem hex files for FPGA."""
    W1 = model.fc1.weight.detach().numpy()  # Shape: [8, 10]
    b1 = model.fc1.bias.detach().numpy()    # Shape: [8]
    W2 = model.fc2.weight.detach().numpy()  # Shape: [2, 8]
    b2 = model.fc2.bias.detach().numpy()    # Shape: [2]

    export_weights_arrays(W1, b1, W2, b2, output_dir)


def export_weights_arrays(W1, b1, W2, b2, output_dir):
    """Export weight arrays as .mem hex files."""
    os.makedirs(output_dir, exist_ok=True)

    # Combined weights file for weight_rom.v
    # Layout: L1 weights (80), L1 biases (8), L2 weights (16), L2 biases (2) = 106
    all_weights = []

    # Layer 1 weights: neuron i, input j → address i*10 + j
    for i in range(8):
        for j in range(10):
            all_weights.append(quantize_to_q35(W1[i, j]))

    # Layer 1 biases
    for i in range(8):
        all_weights.append(quantize_to_q35(b1[i]))

    # Layer 2 weights: neuron i, input j → address 88 + i*8 + j
    for i in range(2):
        for j in range(8):
            all_weights.append(quantize_to_q35(W2[i, j]))

    # Layer 2 biases
    for i in range(2):
        all_weights.append(quantize_to_q35(b2[i]))

    # Write combined .mem file
    mem_path = os.path.join(output_dir, "weights.mem")
    with open(mem_path, 'w') as f:
        for w in all_weights:
            f.write(f"{w:02X}\n")
    print(f"Wrote {len(all_weights)} weights to {mem_path}")

    # Also write separate layer files for debugging
    for name, data in [("weights_layer1.mem", W1.flatten()),
                       ("weights_layer2.mem", W2.flatten())]:
        path = os.path.join(output_dir, name)
        with open(path, 'w') as f:
            for v in data:
                f.write(f"{quantize_to_q35(v):02X}\n")
        print(f"Wrote {name}")

    # Print weight statistics
    print(f"\nWeight statistics:")
    print(f"  L1 weights: min={W1.min():.3f}, max={W1.max():.3f}, mean={W1.mean():.3f}")
    print(f"  L1 biases:  min={b1.min():.3f}, max={b1.max():.3f}")
    print(f"  L2 weights: min={W2.min():.3f}, max={W2.max():.3f}, mean={W2.mean():.3f}")
    print(f"  L2 biases:  min={b2.min():.3f}, max={b2.max():.3f}")


def main():
    parser = argparse.ArgumentParser(description="Train ECG MLP Classifier")
    parser.add_argument("--data", help="Path to feature data (.npz)")
    parser.add_argument("--synthetic", action="store_true",
                        help="Use synthetic data for testing")
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--lr", type=float, default=0.01)
    parser.add_argument("--output", default="../mem",
                        help="Output directory for weight files")
    args = parser.parse_args()

    if args.synthetic:
        print("Generating synthetic training data...")
        features, labels = generate_synthetic_data(5000)
    elif args.data:
        data = np.load(args.data)
        features = data['features'].astype(np.float32)
        labels = data['labels'].astype(np.int64)
    else:
        print("Specify --synthetic or --data <file.npz>")
        return

    print(f"Training data: {features.shape[0]} samples, {features.shape[1]} features")
    print(f"Class distribution: {np.sum(labels==0)} normal, {np.sum(labels==1)} abnormal")

    # Clip features to Q3.5 range
    features = np.clip(features, -4.0, 3.96875)

    output_dir = os.path.join(os.path.dirname(__file__), args.output)

    if HAS_TORCH:
        print("\nTraining with PyTorch...")
        model = train_pytorch(features, labels, args.epochs, args.lr)
        export_weights_torch(model, output_dir)
    else:
        print("\nTraining with NumPy (fallback)...")
        W1, b1, W2, b2 = train_numpy(features, labels, args.epochs, args.lr)
        export_weights_arrays(W1, b1, W2, b2, output_dir)

    print(f"\nWeights exported to {output_dir}/")
    print("Copy weights.mem to your Vivado project directory for FPGA synthesis.")


if __name__ == "__main__":
    main()
