#!/usr/bin/env python3
"""
uart_monitor.py — ECG Secure Enclave UART Dashboard
Reads UART output from Basys 3 and displays:
  - Left panel: encrypted hex stream (what an attacker sees)
  - Right panel: classification result + heart rate (what a doctor sees)

Protocol:
  0xAA [16 bytes ciphertext] 0x55  — Encrypted ECG block
  0xBB [class] [HR_hi] [HR_lo] 0x55 — Classification result

Usage: python uart_monitor.py [--port /dev/ttyUSBx] [--baud 115200]
"""

import argparse
import sys
import time
import threading
from collections import deque

try:
    import serial
except ImportError:
    print("Install pyserial: pip install pyserial")
    sys.exit(1)


class ECGMonitor:
    def __init__(self, port, baud):
        self.port = port
        self.baud = baud
        self.ser = None
        self.running = False

        # Data buffers
        self.cipher_blocks = deque(maxlen=100)
        self.last_classification = None  # 0=normal, 1=abnormal
        self.last_hr = 0
        self.raw_samples = deque(maxlen=2000)  # For plotting

        # Stats
        self.cipher_count = 0
        self.class_count = 0

    def connect(self):
        try:
            self.ser = serial.Serial(self.port, self.baud, timeout=1)
            print(f"Connected to {self.port} at {self.baud} baud")
            return True
        except serial.SerialException as e:
            print(f"Error opening {self.port}: {e}")
            return False

    def read_loop(self):
        """Main read loop — parse framed UART packets."""
        self.running = True
        buf = bytearray()

        while self.running:
            try:
                data = self.ser.read(256)
                if not data:
                    continue
                buf.extend(data)

                # Parse frames from buffer
                while len(buf) >= 2:
                    if buf[0] == 0xAA:
                        # Encrypted ECG frame: AA + 16 bytes + 55 = 18 bytes
                        if len(buf) < 18:
                            break
                        if buf[17] == 0x55:
                            cipher = bytes(buf[1:17])
                            self.cipher_blocks.append(cipher)
                            self.cipher_count += 1
                            buf = buf[18:]
                        else:
                            # Framing error, skip byte
                            buf = buf[1:]

                    elif buf[0] == 0xBB:
                        # Classification frame: BB + class + HR_hi + HR_lo + 55 = 5 bytes
                        if len(buf) < 5:
                            break
                        if buf[4] == 0x55:
                            self.last_classification = buf[1]
                            self.last_hr = (buf[2] << 8) | buf[3]
                            self.class_count += 1
                            buf = buf[5:]
                        else:
                            buf = buf[1:]

                    else:
                        # Unknown byte, skip
                        buf = buf[1:]

            except serial.SerialException:
                print("Serial connection lost")
                self.running = False
            except KeyboardInterrupt:
                self.running = False

    def display_loop(self):
        """Terminal display update loop."""
        while self.running:
            self.render_dashboard()
            time.sleep(0.5)

    def render_dashboard(self):
        """Render the terminal dashboard."""
        # Clear screen
        print("\033[2J\033[H", end="")

        print("=" * 72)
        print("     ECG SECURE ENCLAVE — FPGA PRIVACY MONITOR")
        print("=" * 72)
        print()

        # Left side: encrypted data
        print("--- ENCRYPTED STREAM (attacker's view) ---")
        if self.cipher_blocks:
            for i, block in enumerate(list(self.cipher_blocks)[-5:]):
                hex_str = block.hex().upper()
                print(f"  [{self.cipher_count - 4 + i:04d}] {hex_str}")
        else:
            print("  (waiting for encrypted data...)")
        print()

        # Right side: classification
        print("--- CLINICAL OUTPUT (doctor's view) ---")
        if self.last_classification is not None:
            status = "NORMAL" if self.last_classification == 0 else "ABNORMAL"
            color = "\033[92m" if self.last_classification == 0 else "\033[91m"
            reset = "\033[0m"
            print(f"  Heart Rate: {self.last_hr} BPM")
            print(f"  Status:     {color}{status}{reset}")
        else:
            print("  (waiting for classification...)")
        print()

        print(f"--- Stats: {self.cipher_count} cipher blocks, "
              f"{self.class_count} classifications ---")
        print()
        print("Press Ctrl+C to exit")

    def run(self):
        if not self.connect():
            return

        # Start read thread
        read_thread = threading.Thread(target=self.read_loop, daemon=True)
        read_thread.start()

        try:
            self.display_loop()
        except KeyboardInterrupt:
            pass
        finally:
            self.running = False
            if self.ser:
                self.ser.close()
            print("\nDisconnected.")


def main():
    parser = argparse.ArgumentParser(description="ECG Secure Enclave UART Monitor")
    parser.add_argument("--port", default="/dev/tty.usbserial-210",
                        help="Serial port (default: /dev/tty.usbserial-210)")
    parser.add_argument("--baud", type=int, default=115200,
                        help="Baud rate (default: 115200)")
    args = parser.parse_args()

    monitor = ECGMonitor(args.port, args.baud)
    monitor.run()


if __name__ == "__main__":
    main()
