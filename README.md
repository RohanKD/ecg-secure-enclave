# ECG Secure Enclave

FPGA-based secure enclave for medical ECG on Basys 3 (Artix-7 XC7A35T).

## Architecture
```
AD8232 → XADC → Scaler → ECG Pipeline (Pan-Tompkins) → MLP Classifier → UART (class)
                               ↓                              ↓
                          AES-128 Encrypt ──────────────► UART (encrypted)
                               ↓
                          VGA Display (local)
```

## Algorithms
- **QRS Detection**: Pan-Tompkins (bandpass → derivative → squarer → moving avg → threshold)
- **Classification**: MLP neural network (10→8→2), Q3.5 fixed-point weights
- **Encryption**: AES-128 ECB, iterative implementation (11 rounds)

## Status
- [x] Market research & patents
- [x] Platform selection & feasibility
- [x] Pan-Tompkins reference implementation
- [x] MLP training pipeline
- [x] AES-128 algorithm research
- [ ] Detailed architecture design
- [ ] RTL implementation
