# ECG Secure Enclave — FPGA-Based Medical ECG with Hardware-Enforced HIPAA Compliance

A hardware security architecture for medical ECG acquisition, classification, and encryption on a Xilinx Artix-7 FPGA (Basys 3). Raw ECG data never leaves the FPGA unencrypted — only AES-128 ciphertext and plaintext arrhythmia classification are output.

## Architecture

```
AD8232 → XADC → Voltage Scaler → ECG Pipeline → MLP Classifier → UART (classification)
                                      ↓
                                 AES-128 Encrypt → UART (encrypted ECG)
                                      ↓
                                 VGA Display (local only)
```

## Key Features

- **Hardware-enforced data isolation**: Raw ECG samples exist only within the FPGA fabric
- **Real-time QRS detection**: Pan-Tompkins algorithm implemented in streaming hardware
- **On-chip arrhythmia classification**: 10→8→2 MLP neural network in fixed-point arithmetic
- **AES-128 encryption**: NIST FIPS-197 compliant, encrypts every sample before UART output
- **Live monitoring**: VGA waveform display + 7-segment BPM + LED status indicators

## Platform

- **FPGA**: Digilent Basys 3 (Xilinx Artix-7 XC7A35T)
- **ECG Frontend**: AD8232 single-lead heart rate monitor
- **Resource Usage**: ~29% LUT, 8% FF, 12% BRAM, 8% DSP

## Repository Structure

```
rtl/            — Verilog RTL source (33 modules)
sim/            — Testbenches and test data
mem/            — Weight and font ROM initialization files
python/         — Host tools (UART monitor, training, verification)
constraints/    — Basys 3 pin assignments (XDC)
docs/           — Research notes and design documents
scripts/        — Build and setup scripts
```

## Building

Requires Vivado ML Standard (free) with Artix-7 device support:

```bash
vivado -mode batch -source build.tcl
```

Programming the FPGA (Mac):
```bash
openFPGALoader -b basys3 ecg_secure_enclave.bit
```

## Verification

| Test | Result |
|------|--------|
| AES-128 (3 NIST vectors) | PASS |
| QRS Detection (60 BPM) | PASS |
| MLP Classification | PASS |
| Interface Consistency (30 ports) | PASS |

## Georgia Tech Create-X I2P — Spring 2026
