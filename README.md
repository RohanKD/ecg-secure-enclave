# ECG Secure Enclave

FPGA-based secure enclave for medical ECG on **Basys 3 (Artix-7 XC7A35T)**.

## Concept
Raw ECG data is confined within FPGA fabric. Only AES-128 encrypted samples and plaintext arrhythmia classification are output.

## Platform: Basys 3
- Xilinx Artix-7 XC7A35T (20,800 LUTs, 90 DSP slices)
- Built-in XADC: 12-bit, 1 MSPS — direct analog ECG input
- On-board VGA, UART, 7-segment, LEDs
- Estimated utilization: ~29% LUT, 8% FF, 12% BRAM

## ECG Frontend: AD8232
- Single-lead heart rate monitor analog front end
- 20k/10k voltage divider for XADC input scaling

## Status
- [x] Market research
- [x] Patent landscape
- [x] Platform selection (Basys 3)
- [x] Feasibility analysis
- [ ] Algorithm research
- [ ] Architecture design
- [ ] RTL implementation
