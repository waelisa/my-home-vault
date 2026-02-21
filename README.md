# 🛡️ My Home Vault (v5.1.5)
**A Professional-Grade Backup Guardian for Linux**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-5.1.5-blue.svg)](#)
[![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)

**My Home Vault** is a lightweight yet powerful backup utility designed for users who want enterprise-level data protection without the complexity. Optimized for home servers and NAS systems (like the Asustor AS4004T), it handles everything from local USB syncs to remote SSH backups with built-in integrity healing.

---

## ✨ Features

* **🧙 Zero-Coding Wizard:** Interactive first-run setup configures your paths and NAS settings in seconds.
* **📉 Space-Saving Incrementals:** Uses `rsync` with hard links (`--link-dest`) to provide 14+ days of history for the storage price of a single backup.
* **🔧 VAULT-FIX (Repair Mode):** Performs bit-for-bit checksum verification to identify and repair silent data corruption (bit rot).
* **🔌 Crash-Proof USB Handling:** Automatically detects read-only filesystems and attempts self-repair remounts.
* **⏰ Set-and-Forget:** Integrated Cron scheduling for automatic nightly backups.
* **📊 Log Management:** Automated log rotation and cleanup keeps your system lean.
* **🔔 Desktop Alerts:** Native Linux notifications keep you informed of backup status.

---

## 🚀 Quick Start

Protect your data in three simple commands:

# 1. Download the script
```bash
curl -O [https://raw.githubusercontent.com/waelisa/my-home-vault/main/my-home-vault.sh](https://raw.githubusercontent.com/waelisa/my-home-vault/main/my-home-vault.sh)
```
# 2. Make it executable
```bash
chmod +x my-home-vault.sh
```

# 3. Run and follow the wizard
```bash
./my-home-vault.sh
```

🛠 How It Works
The Magic of Hard Links

My Home Vault doesn't just copy files. It uses intelligent linking logic. If a file hasn't changed since yesterday, the script creates a "Hard Link" on your NAS.

    Yesterday's Backup: 500GB

    Today's Backup (with 1GB of new photos): Uses only 1GB of actual new disk space.

    Result: You get 14 full-looking restore points while only using a fraction of the space.

Data Integrity (VAULT-SCAN)

Most backup tools only check file size and date. My Home Vault's VAULT-SCAN reads every bit of data on the destination and compares MD5 hashes against the source. If bit-rot is detected, VAULT-FIX surgicaly replaces only the corrupted files.
📋 Requirements

    OS: Any modern Linux distro (Arch, Manjaro, Ubuntu, Debian, Fedora).

    Dependencies: rsync, ssh, curl (Standard on 99% of systems).

    NAS Support: Compatible with any SSH-enabled NAS (Optimized for Asustor ADM).

💾 Hardware Recommendations

For users with large datasets, the speed of your backup depends on your drive technology. We recommend:
Drive Type	Best For	Why?
WD Red Plus	Quiet Home Office	Reliable CMR tech for constant rsync tasks.
Seagate IronWolf	Performance / Health	Integrated health management for Asustor NAS.
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
