# ECG Wearable Market Research

## Current Landscape
- **AliveCor KardiaMobile**: Single-lead, FDA-cleared, cloud-based analysis. Data encrypted in transit (TLS) but processed on phone/cloud.
- **Apple Watch ECG**: Single-lead, on-device ML classification. Data stored in HealthKit, synced to iCloud.
- **Zio Patch (iRhythm)**: Continuous 14-day monitoring. Data sent to cloud for analysis by technicians.
- **BioTelemetry (Philips)**: Hospital-grade remote monitoring. HIPAA-compliant cloud infrastructure.

## Gap Analysis
All existing solutions rely on **software-level** encryption and access control:
- Raw ECG data exists in plaintext on the device (phone, watch, patch processor)
- Encryption happens at the application/OS layer — vulnerable to OS exploits, memory dumps, side-channel attacks
- Cloud processing means raw data traverses multiple systems

## Our Differentiation
**Hardware-enforced data isolation**: The FPGA processes raw ECG internally but only outputs:
1. AES-128 encrypted samples (ciphertext)
2. Plaintext classification result (Normal/Abnormal)

Raw ECG literally cannot be extracted — there is no bus, register, or interface that exposes it unencrypted. This is a fundamentally different security model from software encryption.

## Target Applications
- Clinical trials requiring HIPAA audit trails
- High-security patient monitoring (VIP, military, government)
- Medical device OEMs wanting hardware-level compliance
- Research institutions with strict IRB data handling requirements

## Market Size
- Remote patient monitoring: $71.9B by 2027 (Grand View Research)
- Medical device security: $8.2B by 2026 (MarketsandMarkets)
- Cardiac monitoring devices: $28.9B by 2027
