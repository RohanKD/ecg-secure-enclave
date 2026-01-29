# Technical Feasibility Analysis

## Platform Evaluation

| Platform | FPGA | ADC | LUTs | BRAM | DSP | Price | Verdict |
|----------|------|-----|------|------|-----|-------|---------|
| Basys 3 | XC7A35T | XADC built-in | 20,800 | 50 (36Kb) | 90 | $149 | **Selected** |
| Zybo Z7-20 | XC7Z020 | XADC + ARM | 53,200 | 140 | 220 | $299 | Overkill, ARM adds attack surface |
| iCE40 UP5K | iCE40UP5K | None | 5,280 | 30 | 8 | $50 | Too small, no ADC |
| ECP5-25F | LFE5U-25F | None | 24,000 | 56 | 28 | $100 | No ADC, open-source tools only |

## Why Basys 3 (XC7A35T)
- **Built-in XADC**: 12-bit, 1 MSPS — eliminates external ADC, reduces BOM
- **Sufficient resources**: Our design needs ~6K LUTs (29%), fits with comfortable margin
- **On-board I/O**: VGA, UART, 7-seg display, LEDs, switches — all needed for our design
- **Vivado support**: Full synthesis, implementation, and simulation toolchain
- **Academic pricing**: $149 through Digilent Academic Program

## Resource Budget Estimate

| Module | LUTs | FFs | BRAM | DSP |
|--------|------|-----|------|-----|
| XADC + scaler | 200 | 150 | 0 | 1 |
| Bandpass filter | 400 | 300 | 0 | 2 |
| Derivative + squarer | 300 | 200 | 0 | 1 |
| Moving average | 200 | 150 | 1 | 0 |
| Adaptive threshold | 300 | 250 | 0 | 0 |
| Feature extraction | 500 | 400 | 0 | 1 |
| MLP classifier | 400 | 300 | 2 | 1 |
| AES-128 | 2500 | 1200 | 0 | 0 |
| VGA display | 500 | 300 | 2 | 0 |
| UART + output mux | 200 | 100 | 0 | 0 |
| 7-seg + LEDs | 150 | 80 | 0 | 0 |
| Clock + control | 200 | 100 | 0 | 0 |
| Font ROM | 200 | 50 | 1 | 0 |
| **Total** | **~6050** | **~3480** | **6** | **7** |
| **Available** | 20,800 | 41,600 | 50 | 90 |
| **Utilization** | 29% | 8% | 12% | 8% |

## XADC Specifications
- Resolution: 12-bit
- Sample rate: Up to 1 MSPS (we use 500 Hz — more than sufficient for ECG)
- Input range: 0–1V differential
- Channel: VAUX6 (pins J3/K3 on Basys 3 Pmod JA)
- External: 20k/10k voltage divider to scale AD8232 output (0–3.3V) to XADC range (0–1V)

## AD8232 ECG Frontend
- Single-lead heart rate monitor analog front end
- Output: 0–3.3V analog, proportional to ECG amplitude
- Built-in instrumentation amplifier, HPF, LPF
- Leads-off detection (digital output, active low)
- Supply: 3.3V (matches Basys 3 Pmod)

## Conclusion
Design is feasible on Basys 3 with comfortable resource margins. Critical path is likely AES round computation or MLP MAC operation. 100 MHz clock provides ample timing margin for both.
