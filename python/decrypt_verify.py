#!/usr/bin/env python3
"""
decrypt_verify.py — Decrypt AES-128 ECG ciphertext from UART and verify integrity.
Proves the encryption works by recovering the original ECG samples.

Usage: python decrypt_verify.py [--port /dev/ttyUSBx] [--key <hex>]
"""

import argparse
import sys
import struct

try:
    import serial
except ImportError:
    print("Install pyserial: pip install pyserial")
    sys.exit(1)

try:
    from Crypto.Cipher import AES
except ImportError:
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        USE_CRYPTOGRAPHY = True
    except ImportError:
        print("Install pycryptodome or cryptography:")
        print("  pip install pycryptodome")
        sys.exit(1)
    else:
        USE_CRYPTOGRAPHY = True
else:
    USE_CRYPTOGRAPHY = False

# Default AES key (matches FPGA hardcoded key)
DEFAULT_KEY = "000102030405060708090a0b0c0d0e0f"


def decrypt_block(ciphertext, key_bytes):
    """Decrypt a single 16-byte AES-128 ECB block."""
    if USE_CRYPTOGRAPHY:
        cipher = Cipher(algorithms.AES(key_bytes), modes.ECB())
        dec = cipher.decryptor()
        return dec.update(ciphertext) + dec.finalize()
    else:
        cipher = AES.new(key_bytes, AES.MODE_ECB)
        return cipher.decrypt(ciphertext)


def extract_samples(plaintext):
    """Extract 12-bit ECG samples from a 128-bit (16-byte) decrypted block.
    Packing: 10 samples × 12 bits = 120 bits, padded to 128 bits.
    Samples are packed MSB-first: bits[127:116]=sample0, bits[115:104]=sample1, etc.
    """
    samples = []
    val = int.from_bytes(plaintext, 'big')
    for i in range(10):
        shift = 128 - 12 * (i + 1)
        sample = (val >> shift) & 0xFFF
        samples.append(sample)
    return samples


def main():
    parser = argparse.ArgumentParser(description="AES Decrypt & Verify ECG Data")
    parser.add_argument("--port", default="/dev/tty.usbserial-210",
                        help="Serial port")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--key", default=DEFAULT_KEY,
                        help="AES-128 key in hex (32 hex chars)")
    parser.add_argument("--count", type=int, default=100,
                        help="Number of blocks to decrypt")
    parser.add_argument("--plot", action="store_true",
                        help="Plot decrypted ECG waveform")
    args = parser.parse_args()

    key_bytes = bytes.fromhex(args.key)
    assert len(key_bytes) == 16, "Key must be 16 bytes (32 hex chars)"

    ser = serial.Serial(args.port, args.baud, timeout=2)
    print(f"Connected to {args.port}")
    print(f"AES Key: {args.key}")
    print(f"Decrypting {args.count} blocks...")

    all_samples = []
    blocks_decrypted = 0
    buf = bytearray()

    try:
        while blocks_decrypted < args.count:
            data = ser.read(256)
            if not data:
                continue
            buf.extend(data)

            while len(buf) >= 18:
                # Find encrypted ECG frame header
                try:
                    idx = buf.index(0xAA)
                except ValueError:
                    buf.clear()
                    break

                if idx > 0:
                    buf = buf[idx:]

                if len(buf) < 18:
                    break

                if buf[17] == 0x55:
                    cipher_block = bytes(buf[1:17])
                    plaintext = decrypt_block(cipher_block, key_bytes)
                    samples = extract_samples(plaintext)
                    all_samples.extend(samples)
                    blocks_decrypted += 1

                    # Show progress
                    hex_cipher = cipher_block.hex().upper()
                    hex_plain = plaintext.hex().upper()
                    print(f"[{blocks_decrypted:04d}] Cipher: {hex_cipher[:32]}...")
                    print(f"       Plain:  {hex_plain[:32]}...")
                    print(f"       Samples: {samples[:5]}...")

                    buf = buf[18:]
                else:
                    buf = buf[1:]

    except KeyboardInterrupt:
        pass
    finally:
        ser.close()

    print(f"\nDecrypted {blocks_decrypted} blocks, {len(all_samples)} samples total")

    if args.plot and all_samples:
        try:
            import matplotlib.pyplot as plt
            plt.figure(figsize=(12, 4))
            plt.plot(all_samples, 'g-', linewidth=0.5)
            plt.title("Decrypted ECG Waveform (from AES ciphertext)")
            plt.xlabel("Sample")
            plt.ylabel("ADC Value (12-bit)")
            plt.grid(True, alpha=0.3)
            plt.tight_layout()
            plt.savefig("decrypted_ecg.png", dpi=150)
            plt.show()
            print("Plot saved to decrypted_ecg.png")
        except ImportError:
            print("Install matplotlib for plotting: pip install matplotlib")


if __name__ == "__main__":
    main()
