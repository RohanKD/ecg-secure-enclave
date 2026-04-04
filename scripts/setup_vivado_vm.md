# UTM + Vivado Setup Guide for Apple Silicon Mac

## Step 1: Create UTM VM

1. Open **UTM** (`/Applications/UTM.app`)
2. Click **"Create a New Virtual Machine"**
3. Select **"Virtualize"** (NOT Emulate — we use ARM64 Ubuntu + Rosetta)
4. Select **"Linux"**
5. Check **"Use Apple Virtualization"** and **"Enable Rosetta"**
6. Browse and select the ISO: `~/Downloads/ubuntu-22.04.5-live-server-arm64.iso`
7. Configure:
   - **RAM**: 8192 MB (8 GB)
   - **CPU Cores**: 4
   - **Storage**: 50 GB (dynamically allocated)
8. Add a **Shared Directory**: `/Users/rohan/i2p_fpga` (this lets the VM access your RTL files)
9. Name the VM: `vivado-fpga`
10. Click **Save**, then **Start** the VM

## Step 2: Install Ubuntu

1. Follow the Ubuntu Server installer defaults
2. Set username: `rohan`, pick a password
3. Enable OpenSSH server when prompted
4. After install completes, remove the ISO from UTM VM settings and reboot

## Step 3: Post-Install Setup (run inside VM)

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install desktop environment (needed for Vivado GUI)
sudo apt install -y ubuntu-desktop-minimal

# Install Vivado dependencies
sudo apt install -y libtinfo5 libncurses5 libx11-6 libxext6 libxrender1 \
  libxtst6 libxi6 libfreetype6 fontconfig python3 python3-pip \
  default-jre xterm locales

# Enable Rosetta for x86 binary translation
sudo apt install -y binfmt-support
sudo mkdir -p /media/rosetta
sudo mount -t virtiofs rosetta /media/rosetta
echo "rosetta\t/media/rosetta\tvirtiofs\tro,nofail\t0\t0" | sudo tee -a /etc/fstab
sudo /usr/sbin/update-binfmts --install rosetta /media/rosetta/rosetta \
  --magic "\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00" \
  --mask "\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff" \
  --credentials yes --preserve no --fix-binary yes

# Mount shared directory (access to i2p_fpga files)
sudo mkdir -p /mnt/i2p_fpga
sudo mount -t virtiofs share /mnt/i2p_fpga
echo "share\t/mnt/i2p_fpga\tvirtiofs\trw,nofail\t0\t0" | sudo tee -a /etc/fstab

# Generate locale
sudo locale-gen en_US.UTF-8

# Reboot to apply desktop + Rosetta
sudo reboot
```

## Step 4: Download & Install Vivado

1. On your **Mac** browser, go to:
   https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools.html

2. Download **"Vivado ML Standard Edition - Web Installer"** for **Linux** (the .bin file, ~300 MB)
   - You need a free AMD/Xilinx account

3. Copy the installer to the shared directory:
   ```bash
   # On Mac:
   cp ~/Downloads/Xilinx_Unified_*_Lin64.bin /Users/rohan/i2p_fpga/
   ```

4. Inside the VM:
   ```bash
   cd /mnt/i2p_fpga
   chmod +x Xilinx_Unified_*_Lin64.bin
   sudo ./Xilinx_Unified_*_Lin64.bin
   ```

5. In the Vivado installer GUI:
   - Select **"Vivado ML Standard"** (free, no license needed)
   - Under "Devices", uncheck everything EXCEPT **"Artix-7"**
   - Install to `/tools/Xilinx/Vivado/2024.1` (or latest version)
   - This minimizes download size to ~15-20 GB

6. After install, add to PATH:
   ```bash
   echo 'source /tools/Xilinx/Vivado/2024.1/settings64.sh' >> ~/.bashrc
   source ~/.bashrc
   ```

## Step 5: Build the FPGA Bitstream

```bash
cd /mnt/i2p_fpga
mkdir -p reports
vivado -mode batch -source build.tcl
```

This runs synthesis, implementation, and bitstream generation.
Output: `ecg_secure_enclave.bit`

## Step 6: Program the FPGA

### Option A: From the VM (if USB passthrough works)
1. Connect Basys 3 via USB
2. In UTM, pass through the USB device to the VM
3. Inside VM:
   ```bash
   vivado -mode batch -source program.tcl
   ```

### Option B: From Mac using openFPGALoader
```bash
# On Mac:
brew install openfpgaloader
openFPGALoader -b basys3 ecg_secure_enclave.bit
```
This is simpler — no USB passthrough needed.
