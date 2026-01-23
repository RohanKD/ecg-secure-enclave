# ECG Secure Enclave

FPGA-based secure enclave for medical ECG — hardware-enforced HIPAA compliance.

## Concept
Raw ECG data is confined within FPGA fabric. Only AES-128 encrypted samples and plaintext arrhythmia classification are output. No software, no OS, no attack surface.

## Research
- Market analysis: gap in hardware-level ECG data protection
- Patent landscape: reviewed 4 key patents, identified freedom to operate
- Key differentiation: on-chip classification + encryption in single FPGA pipeline

## Status
- [x] Market research
- [x] Patent landscape search
- [ ] Platform selection & feasibility
- [ ] Architecture design
- [ ] RTL implementation
