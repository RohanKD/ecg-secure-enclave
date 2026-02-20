# System Architecture Design

## Top-Level Dataflow

```
                    ┌─────────────────────────────────────┐
                    │           FPGA (XC7A35T)            │
                    │                                     │
  AD8232 ──────────►│ XADC ──► Scaler ──► ECG Pipeline ──┼──► VGA Display
  (ECG analog)      │                    │    │           │   (local only)
                    │                    │    ▼           │
                    │                    │  Feature ──► MLP│──► 7-Seg (BPM)
                    │                    │  Extractor   │  │
                    │                    │             ▼  │
                    │                    ▼         Classify│
                    │                AES-128         │    │
                    │                    │           │    │
                    │                    ▼           ▼    │
                    │              Output Mux ──► UART ──┼──► Host PC
                    │              (0xAA enc)  (0xBB cls) │
                    │                                     │
                    │  Switches ──► Key/Config             │
                    │  LEDs ◄── Status                    │
                    └─────────────────────────────────────┘
```

## Security Boundary
The FPGA fabric IS the security boundary. Raw ECG exists only as:
- Register values within the signal processing pipeline
- These registers have no external interface — no bus master can read them
- The ONLY paths out of the FPGA are:
  1. AES-encrypted UART (ciphertext)
  2. Classification result UART (2-bit: Normal/Abnormal)
  3. VGA display (physically local, no digital output)

## Module Hierarchy

```
top_basys3
├── clk_divider          (100MHz → 25MHz, 500Hz, 1kHz)
├── xadc_interface       (XADC DRP controller, VAUX6)
├── voltage_scaler       (×3 compensation, 12-bit clamp)
├── ecg_pipeline
│   ├── qrs_detector
│   │   ├── bandpass_filter    (IIR HPF 5Hz + LPF 15Hz)
│   │   ├── derivative_filter  (5-point causal)
│   │   ├── squarer            (DSP48, scaled)
│   │   ├── moving_avg         (75-sample window)
│   │   └── adaptive_threshold (peak detect + refractory)
│   └── feature_extractor
│       ├── rr_interval        (beat-to-beat timing)
│       ├── rr_stats           (mean, variability)
│       ├── qrs_width          (complex duration)
│       └── amplitude          (R-peak amplitude)
├── mlp_classifier
│   ├── weight_rom             (Q3.5 weights in BRAM)
│   ├── mac_unit               (multiply-accumulate)
│   └── relu                   (activation function)
├── aes128_encrypt
│   ├── sbox                   (SubBytes lookup)
│   ├── shift_rows             (row permutation)
│   ├── mix_columns            (GF(2^8) multiply)
│   └── key_expansion          (round key generation)
├── output_mux                 (UART framing)
├── uart_tx                    (115200 baud 8N1)
├── vga_controller             (640×480 sync gen)
├── vga_waveform               (scrolling ECG trace)
├── vga_text                   (text overlay)
│   └── font_rom               (8×16 ASCII font)
├── seven_seg                  (BPM display)
└── led_status                 (heartbeat, alerts)
```

## Interface Conventions
- All data paths: 16-bit signed (ECG pipeline), 8-bit unsigned (MLP), 128-bit (AES)
- Handshaking: `valid` signal accompanies every data transfer
- Clock domain: Single 100 MHz clock, with clock enables for slower rates
- Reset: Active-high synchronous reset from Basys 3 center button
