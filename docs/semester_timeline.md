# ECG Secure Enclave — Semester Development Timeline

## Week 1 (Jan 12–18): Project Ideation & Market Research
- Researched wearable ECG market (AliveCor, Apple Watch ECG, Zio patch)
- Identified gap: no hardware-enforced encryption for medical ECG — most devices rely on software/OS-level security
- Explored HIPAA technical safeguard requirements (45 CFR § 164.312)
- Initial concept: FPGA-based secure enclave where raw ECG data never leaves the chip unencrypted

## Week 2 (Jan 19–25): Prior Art & Patent Research
- Patent landscape search on Google Patents and USPTO
- Key prior art reviewed:
  - US10892057B2 — Implantable medical device with AES encryption (Medtronic)
  - US20190246920A1 — Wearable ECG with cloud-based arrhythmia detection
  - US11202578B2 — FPGA-based medical data processing
- Identified differentiation: on-chip classification + encryption in a single FPGA pipeline — classification result is plaintext, raw signal is always encrypted
- Drafted initial patent claims around hardware-enforced data isolation

## Week 3 (Jan 26–Feb 1): Technical Feasibility & Platform Selection
- Evaluated FPGA platforms: Basys 3 (Artix-7), Zybo (Zynq), iCE40, ECP5
- Selected Basys 3 (XC7A35T) — built-in XADC for analog input, sufficient resources, low cost ($149)
- Studied XADC specifications: 1 MSPS, 12-bit, differential inputs
- Researched AD8232 single-lead ECG analog front end
- Confirmed resource budget feasibility: ~6K LUTs needed vs 20.8K available

## Week 4 (Feb 2–8): Algorithm Research — QRS Detection
- Studied Pan-Tompkins QRS detection algorithm (1985 paper)
- Implemented reference Pan-Tompkins in Python (`pan_tompkins_ref.py`)
- Tested on MIT-BIH Arrhythmia Database samples
- Mapped algorithm stages to hardware pipeline: bandpass → derivative → squarer → moving average → adaptive threshold
- Determined fixed-point requirements: 16-bit signed sufficient for 12-bit ADC input

## Week 5 (Feb 9–15): Algorithm Research — AES-128 & MLP Classifier
- Studied AES-128 (FIPS-197) for on-chip encryption
- Evaluated AES implementation strategies: fully pipelined vs iterative
  - Chose iterative (11 rounds, ~23 cycles) to minimize LUT usage
- Researched lightweight neural network architectures for arrhythmia classification
- Designed MLP topology: 10 features → 8 hidden → 2 output
- Selected Q3.5 fixed-point (8-bit) for weights to fit in BRAM

## Week 6 (Feb 16–22): Architecture Design & Module Hierarchy
- Defined complete system architecture and dataflow
- Designed module hierarchy: top → {xadc, voltage_scaler, ecg_pipeline, mlp_classifier, aes128, uart_tx, vga, seven_seg, led_status, output_mux}
- Specified all inter-module interfaces (data widths, valid/ready signals)
- Created pin mapping for Basys 3 constraints (XDC)
- Estimated resource utilization: ~29% LUT, 8% FF, 12% BRAM, 8% DSP

## Week 7 (Feb 23–Mar 1): RTL — XADC & Analog Input Chain
- Implemented `clk_divider.v` — 100MHz → 25MHz (VGA), 500Hz (ADC), 1kHz (7-seg)
- Implemented `xadc_interface.v` — Direct XADC primitive instantiation, DRP state machine, VAUX6 channel
- Implemented `voltage_scaler.v` — ×3 compensation for external 20k/10k divider, 12-bit clamp
- Designed external voltage divider circuit for AD8232 → XADC input scaling (3.3V → 1.0V range)

## Week 8 (Mar 2–8): RTL — ECG Signal Processing Pipeline
- Implemented `bandpass_filter.v` — Cascaded IIR highpass (5Hz) + lowpass (15Hz), 5-stage pipeline
- Implemented `derivative_filter.v` — 5-point causal derivative with shift register
- Implemented `squarer.v` — DSP48-inferred multiply with scaling and saturation
- Implemented `moving_avg.v` — 75-sample circular buffer, running sum
- Implemented `adaptive_threshold.v` — Peak detection with adaptive signal/noise levels, refractory period
- Implemented `qrs_detector.v` — Structural chain of all 5 stages

## Week 9 (Mar 9–15): RTL — Feature Extraction & MLP Classifier
- Implemented `rr_interval.v`, `rr_stats.v` — RR interval measurement and 8-beat statistics
- Implemented `qrs_width.v`, `amplitude.v` — QRS morphology features
- Implemented `feature_extractor.v` — 10-feature vector (80-bit packed output)
- Implemented `mlp_classifier.v` — Sequential MAC architecture, 6-state FSM
- Implemented `mac_unit.v`, `relu.v`, `weight_rom.v` — MLP building blocks
- Trained MLP on synthetic arrhythmia data (`train_mlp.py`), exported Q3.5 weights

## Week 10 (Mar 16–22): RTL — AES-128 Encryption Engine
- Implemented `sbox.v` — Full 256-entry AES substitution box
- Implemented `shift_rows.v`, `mix_columns.v` — AES round operations with GF(2^8) math
- Implemented `key_expansion.v` — Iterative round key generation
- Implemented `aes128_encrypt.v` — 11-round iterative encryption FSM
- Verified against NIST FIPS-197 test vectors — 3/3 PASS

## Week 11 (Mar 23–29): RTL — VGA Display & Output Interfaces
- Implemented `vga_controller.v` — 640×480@60Hz sync generator
- Implemented `vga_waveform.v` — Scrolling ECG trace with 640-sample BRAM buffer
- Implemented `vga_text.v` + `font_rom.v` — Text overlay (HR, status, title)
- Implemented `uart_tx.v` — 115200 baud 8N1 transmitter
- Implemented `output_mux.v` — Framed UART protocol (0xAA=encrypted, 0xBB=classification)
- Implemented `seven_seg.v`, `led_status.v` — BPM display and status indicators

## Week 12 (Mar 30–Apr 5): Integration, Testing & Debugging
- Implemented `top_basys3.v` — Top-level integration of all 13 modules
- Wrote `basys3.xdc` — Complete pin constraints for all I/O
- Ran interface verification: all 30 module instantiations — zero port mismatches
- Testbench development and debugging:
  - `tb_aes128.v` — NIST vector verification (PASS)
  - `tb_qrs_detector.v` — Debugged squarer scaling, testbench race conditions, threshold tuning → 10 beats at 60 BPM (PASS)
  - `tb_mlp_classifier.v` — Pipeline functional verification (PASS)
  - `tb_top.v` — Full integration test
- Wrote Python host tools: `uart_monitor.py`, `decrypt_verify.py`

## Week 13 (Apr 6–12): Synthesis Setup & FPGA Preparation
- Set up Vivado build flow (`build.tcl`, `program.tcl`)
- Configured UTM Linux VM with Rosetta for Vivado on Apple Silicon
- Installed openFPGALoader for Mac-native FPGA programming
- Prepared BOM: Basys 3 + AD8232 + electrode pads + jumper wires
- Next: Vivado synthesis → bitstream generation → hardware test
