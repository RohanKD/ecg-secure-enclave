#!/usr/bin/env python3
"""
pan_tompkins_ref.py — Reference Python Pan-Tompkins implementation
for validating the FPGA QRS detector.

This implements the same algorithm as the Verilog with matching parameters
so detected R-peaks can be directly compared.

Usage:
  python pan_tompkins_ref.py --input ecg_data.csv --output peaks.csv
  python pan_tompkins_ref.py --uart /dev/ttyUSBx  (live from FPGA raw output)
"""

import argparse
import numpy as np

FS = 500  # Sampling frequency (Hz)


def bandpass_filter(signal, fs=FS):
    """Simple IIR bandpass 5-15 Hz matching FPGA implementation.
    HPF: y[n] = alpha*(y[n-1] + x[n] - x[n-1]), alpha=248/256
    LPF: y[n] = (1-alpha)*x[n] + alpha*y[n-1], alpha=233/256
    """
    # High-pass filter (5 Hz)
    alpha_hp = 248.0 / 256.0
    hp_out = np.zeros(len(signal))
    for i in range(1, len(signal)):
        hp_out[i] = alpha_hp * (hp_out[i-1] + signal[i] - signal[i-1])

    # Low-pass filter (15 Hz)
    alpha_lp = 233.0 / 256.0
    lp_out = np.zeros(len(signal))
    for i in range(1, len(signal)):
        lp_out[i] = (1 - alpha_lp) * hp_out[i] + alpha_lp * lp_out[i-1]

    return lp_out


def derivative_filter(signal):
    """5-point derivative: y[n] = (-x[n-4] - 2*x[n-3] + 2*x[n-1] + x[n]) / 8"""
    out = np.zeros(len(signal))
    for i in range(4, len(signal)):
        out[i] = (-signal[i-4] - 2*signal[i-3] + 2*signal[i-1] + signal[i]) / 8.0
    return out


def squaring(signal):
    """Square the signal."""
    return signal ** 2


def moving_window_integration(signal, window_size=75):
    """Moving window integrator (150ms at 500Hz = 75 samples)."""
    out = np.zeros(len(signal))
    cumsum = 0
    buf = np.zeros(window_size)
    idx = 0
    for i in range(len(signal)):
        oldest = buf[idx]
        buf[idx] = signal[i]
        idx = (idx + 1) % window_size
        cumsum = cumsum + signal[i] - oldest
        out[i] = cumsum / window_size
    return out


def adaptive_threshold(integrated, refractory_samples=100):
    """Adaptive dual-threshold peak detection matching FPGA implementation.
    threshold = noise_level + 0.25 * (signal_level - noise_level)
    Refractory period: 200ms = 100 samples at 500Hz.
    """
    signal_level = 0.0
    noise_level = 0.0
    threshold1 = 0.0

    peaks = []
    refractory_counter = 0

    # Initialize with first second of data
    if len(integrated) > FS:
        signal_level = np.max(integrated[:FS]) * 0.5
        noise_level = np.mean(integrated[:FS]) * 0.5
        threshold1 = noise_level + 0.25 * (signal_level - noise_level)

    for i in range(len(integrated)):
        if refractory_counter > 0:
            refractory_counter -= 1
            continue

        if integrated[i] > threshold1:
            # Found a peak — search for local maximum
            peak_idx = i
            peak_val = integrated[i]

            # Look ahead up to 50 samples for the actual peak
            for j in range(i + 1, min(i + 50, len(integrated))):
                if integrated[j] > peak_val:
                    peak_val = integrated[j]
                    peak_idx = j
                elif integrated[j] < peak_val * 0.5:
                    break

            peaks.append(peak_idx)
            refractory_counter = refractory_samples

            # Update signal level
            signal_level = signal_level - signal_level / 8 + peak_val / 8
        else:
            # Update noise level
            noise_level = noise_level - noise_level / 8 + integrated[i] / 8

        # Update threshold
        threshold1 = noise_level + 0.25 * (signal_level - noise_level)

    return np.array(peaks)


def detect_qrs(ecg_signal, fs=FS):
    """Full Pan-Tompkins QRS detection pipeline."""
    # Step 1: Bandpass filter (5-15 Hz)
    filtered = bandpass_filter(ecg_signal, fs)

    # Step 2: Derivative
    derived = derivative_filter(filtered)

    # Step 3: Squaring
    squared = squaring(derived)

    # Step 4: Moving window integration
    integrated = moving_window_integration(squared, window_size=int(0.150 * fs))

    # Step 5: Adaptive threshold
    peaks = adaptive_threshold(integrated, refractory_samples=int(0.200 * fs))

    return peaks, filtered, integrated


def compute_features(ecg_signal, peaks, fs=FS):
    """Compute feature vectors matching FPGA feature extractor."""
    features = []

    for i in range(2, len(peaks)):
        rr_current = peaks[i] - peaks[i-1]
        rr_previous = peaks[i-1] - peaks[i-2]

        # Mean RR over last 8 beats (or available)
        start = max(0, i - 7)
        rr_intervals = [peaks[j] - peaks[j-1] for j in range(start + 1, i + 1)]
        mean_rr = np.mean(rr_intervals)
        rr_var = np.max(rr_intervals) - np.min(rr_intervals)

        # RR ratios
        rr_ratio_prev = rr_current / rr_previous if rr_previous > 0 else 1.0
        rr_ratio_mean = rr_current / mean_rr if mean_rr > 0 else 1.0

        # QRS width (simplified: samples where signal > 50% of peak)
        peak_val = abs(ecg_signal[peaks[i]]) if peaks[i] < len(ecg_signal) else 0
        qrs_width = 0
        if peak_val > 0:
            threshold = peak_val * 0.25
            for j in range(max(0, peaks[i] - 50), min(len(ecg_signal), peaks[i] + 50)):
                if abs(ecg_signal[j]) > threshold:
                    qrs_width += 1

        # Normalized amplitude
        norm_amp = min(peak_val / 1000.0, 4.0) if peak_val > 0 else 0

        # Heart rate
        hr = 60.0 * fs / rr_current if rr_current > 0 else 0

        # RR deviation from mean
        rr_dev = abs(rr_current - mean_rr) / mean_rr if mean_rr > 0 else 0

        feat = [
            min(rr_current / fs * 2, 3.9),      # Current RR (scaled to ~0-4 range)
            min(rr_previous / fs * 2, 3.9),      # Previous RR
            min(mean_rr / fs * 2, 3.9),          # Mean RR
            min(rr_var / fs * 2, 3.9),           # RR variability
            min(rr_ratio_prev, 3.9),             # RR/prev ratio
            min(rr_ratio_mean, 3.9),             # RR/mean ratio
            min(qrs_width / 50.0 * 2, 3.9),     # QRS width (scaled)
            min(norm_amp, 3.9),                   # Normalized amplitude
            min(rr_dev * 4, 3.9),                # RR deviation
            min(hr / 200.0 * 4, 3.9),           # Heart rate (scaled)
        ]
        features.append(feat)

    return np.array(features)


def quantize_features(features, bits=8, int_bits=3):
    """Quantize features to Q3.5 fixed-point (matching FPGA)."""
    frac_bits = bits - int_bits
    scale = 2 ** frac_bits
    max_val = (2 ** (bits - 1) - 1) / scale
    min_val = -(2 ** (bits - 1)) / scale

    quantized = np.clip(features, min_val, max_val)
    quantized = np.round(quantized * scale).astype(np.int8)
    return quantized


def main():
    parser = argparse.ArgumentParser(description="Pan-Tompkins Reference Implementation")
    parser.add_argument("--input", help="Input CSV file (one sample per line)")
    parser.add_argument("--output", default="peaks.csv", help="Output peaks CSV")
    parser.add_argument("--plot", action="store_true", help="Plot results")
    args = parser.parse_args()

    if args.input:
        # Load ECG data
        ecg = np.loadtxt(args.input, delimiter=',')
        if ecg.ndim > 1:
            ecg = ecg[:, 0]  # Take first column

        print(f"Loaded {len(ecg)} samples ({len(ecg)/FS:.1f} seconds)")

        # Detect QRS
        peaks, filtered, integrated = detect_qrs(ecg)
        print(f"Detected {len(peaks)} R-peaks")

        # Compute features
        if len(peaks) > 2:
            features = compute_features(filtered, peaks)
            quantized = quantize_features(features)
            print(f"Computed {len(features)} feature vectors")

            # Compute heart rates
            for i in range(min(10, len(peaks) - 1)):
                rr = peaks[i+1] - peaks[i]
                hr = 60 * FS / rr
                print(f"  Beat {i}: RR={rr} samples, HR={hr:.0f} BPM")

        # Save peaks
        np.savetxt(args.output, peaks, fmt='%d')
        print(f"Peaks saved to {args.output}")

        if args.plot:
            try:
                import matplotlib.pyplot as plt
                fig, axes = plt.subplots(3, 1, figsize=(14, 8), sharex=True)

                t = np.arange(len(ecg)) / FS

                axes[0].plot(t, ecg, 'b-', linewidth=0.5)
                axes[0].plot(peaks / FS, ecg[peaks], 'rv', markersize=8)
                axes[0].set_ylabel('Raw ECG')
                axes[0].set_title('Pan-Tompkins QRS Detection (Reference)')

                axes[1].plot(t, filtered, 'g-', linewidth=0.5)
                axes[1].set_ylabel('Bandpass Filtered')

                axes[2].plot(t, integrated, 'm-', linewidth=0.5)
                axes[2].set_ylabel('Integrated')
                axes[2].set_xlabel('Time (s)')

                plt.tight_layout()
                plt.savefig('pan_tompkins_ref.png', dpi=150)
                plt.show()
            except ImportError:
                print("Install matplotlib for plotting")
    else:
        print("Specify --input <csv_file>")
        print("Example: python pan_tompkins_ref.py --input ecg_data.csv --plot")


if __name__ == "__main__":
    main()
