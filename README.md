# ECG Secure Enclave

FPGA-based secure enclave for medical ECG on Basys 3 (Artix-7 XC7A35T).
Hardware-enforced HIPAA compliance — raw ECG never leaves the FPGA unencrypted.

## Architecture
See [docs/architecture_design.md](docs/architecture_design.md) for full module hierarchy and dataflow.

```
top_basys3
├── clk_divider, xadc_interface, voltage_scaler
├── ecg_pipeline (qrs_detector + feature_extractor)
├── mlp_classifier (weight_rom + mac_unit + relu)
├── aes128_encrypt (sbox + shift_rows + mix_columns + key_expansion)
├── output_mux + uart_tx
├── vga_controller + vga_waveform + vga_text + font_rom
└── seven_seg + led_status
```

## Resource Budget
| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUTs | ~6,050 | 20,800 | 29% |
| FFs | ~3,480 | 41,600 | 8% |
| BRAM | 6 | 50 | 12% |
| DSP | 7 | 90 | 8% |

## Status
- [x] Research & feasibility
- [x] Algorithm prototyping (Python)
- [x] Architecture design
- [x] Pin constraints (XDC)
- [ ] RTL implementation (starting next week)
