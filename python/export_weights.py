#!/usr/bin/env python3
"""
export_weights.py — Convert trained PyTorch model to .mem hex files for FPGA.
Standalone script for re-exporting weights without retraining.

Usage: python export_weights.py --model model.pth --output ../mem/
"""

import argparse
import numpy as np
import os

try:
    import torch
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False


def quantize_to_q35(value):
    """Quantize float to Q3.5 (8-bit signed, 5 fractional bits)."""
    scale = 32
    q = int(np.round(value * scale))
    q = max(-128, min(127, q))
    return q & 0xFF


def export_from_pth(model_path, output_dir):
    """Load PyTorch checkpoint and export weights."""
    if not HAS_TORCH:
        print("PyTorch required. Install with: pip install torch")
        return

    state_dict = torch.load(model_path, map_location='cpu')

    # Handle both full model and state_dict saves
    if hasattr(state_dict, 'state_dict'):
        state_dict = state_dict.state_dict()

    W1 = state_dict['fc1.weight'].numpy()  # [8, 10]
    b1 = state_dict['fc1.bias'].numpy()    # [8]
    W2 = state_dict['fc2.weight'].numpy()  # [2, 8]
    b2 = state_dict['fc2.bias'].numpy()    # [2]

    export_arrays(W1, b1, W2, b2, output_dir)


def export_from_npz(npz_path, output_dir):
    """Load numpy weights and export."""
    data = np.load(npz_path)
    export_arrays(data['W1'], data['b1'], data['W2'], data['b2'], output_dir)


def export_arrays(W1, b1, W2, b2, output_dir):
    """Export weight arrays as .mem files."""
    os.makedirs(output_dir, exist_ok=True)

    all_weights = []

    # Layer 1 weights: [8 neurons][10 inputs]
    for i in range(8):
        for j in range(10):
            all_weights.append(quantize_to_q35(W1[i, j]))

    # Layer 1 biases: [8]
    for i in range(8):
        all_weights.append(quantize_to_q35(b1[i]))

    # Layer 2 weights: [2 neurons][8 inputs]
    for i in range(2):
        for j in range(8):
            all_weights.append(quantize_to_q35(W2[i, j]))

    # Layer 2 biases: [2]
    for i in range(2):
        all_weights.append(quantize_to_q35(b2[i]))

    assert len(all_weights) == 106, f"Expected 106 weights, got {len(all_weights)}"

    # Write combined file
    path = os.path.join(output_dir, "weights.mem")
    with open(path, 'w') as f:
        for w in all_weights:
            f.write(f"{w:02X}\n")
    print(f"Exported {len(all_weights)} weights to {path}")

    # Verification: print as signed values
    print("\nVerification (signed Q3.5 values):")
    for i, w in enumerate(all_weights):
        signed_val = w if w < 128 else w - 256
        float_val = signed_val / 32.0
        if i < 80:
            n, inp = divmod(i, 10)
            label = f"L1_W[{n}][{inp}]"
        elif i < 88:
            label = f"L1_b[{i-80}]"
        elif i < 104:
            n, inp = divmod(i - 88, 8)
            label = f"L2_W[{n}][{inp}]"
        else:
            label = f"L2_b[{i-104}]"
        if i < 5 or i in [80, 88, 104]:
            print(f"  {label:15s} = 0x{w:02X} = {signed_val:4d} = {float_val:+.5f}")


def main():
    parser = argparse.ArgumentParser(description="Export MLP weights to .mem")
    parser.add_argument("--model", help="PyTorch model file (.pth)")
    parser.add_argument("--npz", help="NumPy weights file (.npz)")
    parser.add_argument("--output", default="../mem", help="Output directory")
    args = parser.parse_args()

    output_dir = os.path.join(os.path.dirname(__file__), args.output)

    if args.model:
        export_from_pth(args.model, output_dir)
    elif args.npz:
        export_from_npz(args.npz, output_dir)
    else:
        print("Specify --model <file.pth> or --npz <file.npz>")


if __name__ == "__main__":
    main()
