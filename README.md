# ECG Secure Enclave

FPGA-based secure enclave for medical ECG on Basys 3 (Artix-7 XC7A35T).

## Architecture (WIP)
```
AD8232 → XADC → Voltage Scaler → QRS Detection → Feature Extraction → MLP Classifier
                                       ↓
                                  AES-128 Encrypt → UART
```

## Algorithm: Pan-Tompkins QRS Detection
Implemented reference Python version. Pipeline stages:
1. Bandpass filter (5–15 Hz)
2. Derivative filter (5-point)
3. Squaring
4. Moving window integration (150 ms)
5. Adaptive thresholding with refractory period

## Status
- [x] Market research & patents
- [x] Platform selection (Basys 3)
- [x] Pan-Tompkins Python reference
- [ ] AES-128 & MLP research
- [ ] Architecture design
- [ ] RTL implementation
