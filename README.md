# 🛡️ My Home Vault
**A Professional-Grade Backup Guardian for Linux**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-5.1.5-blue.svg)](#)
[![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)

Professional-grade data protection for Linux, powered by Rsync & ZFS.

My Home Vault is a robust, automated backup engine designed for users who want enterprise-level data security without the complexity. Whether you are using a standard external drive or a high-end ZFS pool, My Home Vault stands guard over your data.


✨ Key Features

    Zero-Knowledge Setup: A 30-second first-run wizard detects your drives and configures the vault automatically.

    VAULT-FIX & SCAN: Bit-rot protection that verifies data integrity using checksums and repairs corrupted files.

    Crash-Proof Logic: Smart handling of USB disconnections and NAS network drops.

    Automated Retention: Keeps your history for 14 days (customizable) and purges old data automatically to save space.

    Non-Interactive Mode: Fully compatible with cron for 100% automated, "set-and-forget" backups.

    ZFS Mastery: Includes atomic snapshot naming (collision-proof), mount verification, and LZ4 compression.

📦 Installation
1. Download the Engine
# For the Standard Edition
```bash
curl -O https://raw.githubusercontent.com/waelisa/my-home-vault/main/my-home-vault.sh
```
# For the ZFS Edition
```bash
curl -O https://raw.githubusercontent.com/waelisa/my-home-vault/main/my-home-vault-zfs.sh
```
2. Make it Executable
```bash
chmod +x my-home-vault*.sh
```
3. Launch the Wizard
# Standard
```bash

./my-home-vault.sh
```
# ZFS (Requires Sudo)
```bash

sudo ./my-home-vault-zfs.sh
```
🛠 Advanced Usage

My Home Vault supports several flags for automation:

    --quiet: Run without output (perfect for cron).

    --dry-run: Test the backup without moving any data.

    --vault-fix: Deep-scan and repair data corruption.

💾 Recommended Hardware

To ensure your vault performs at its peak, we recommend CMR-based NAS drives that can handle high metadata traffic.

    Seagate IronWolf: Optimized for ZFS snapshots and high-frequency file linking.

    WD Red Plus: Ideal for stable, long-term archival and LZ4 compression.

👤 Author

Wael Isa

    Website: [wael.name](https://www.wael.name)

    GitHub: @waelisa

📜 License

This project is licensed under the MIT License. Use it, change it, share it.
---

## ☕ Support the Project

If **My Home Vault** has saved your data (or your sanity), consider buying the author a coffee! Your support helps keep the project updated and "Crash-Proof."

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg)](https://www.paypal.me/YOUR_PAYPAL_USERNAME)

> *Every bit helps maintain the vault!*

---
