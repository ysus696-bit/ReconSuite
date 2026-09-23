# recon.sh — Automated Reconnaissance Pipeline

![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Kali Linux](https://img.shields.io/badge/Kali_Linux-557C94?style=for-the-badge&logo=kalilinux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)
![Version](https://img.shields.io/badge/Version-1.0.0-orange?style=for-the-badge)

> **⚠️ Disclaimer:** This tool is intended for **educational purposes and authorized security testing only**.  
> Only use it on systems you own or have explicit written permission to test.  
> The author is not responsible for any misuse or damage caused by this tool.

---

## Overview

`recon.sh` is a modular, automated reconnaissance pipeline built for penetration testers, CTF players, and bug bounty hunters. It integrates industry-standard tools into a single workflow and generates a clean HTML report with all findings.

Designed for use in labs, CTF environments, and authorized engagements — built and tested on **Kali Linux**.

---

## Features

-  **Three input modes** — single host, file list (`.txt`), or full CIDR range
-  **Nmap** — port scanning with service/version detection and default scripts
-  **Gobuster** — directory and file brute-forcing
-  **Nikto** — web server vulnerability scanning
-  **Nuclei** — template-based vulnerability detection
-  **HTML report** — auto-generated, timestamped, self-contained output
-  **Modular design** — enable or disable tools per scan
-  **Progress indicators** — colored output for easy readability

---

## Demo

```
╔══════════════════════════════════════════════════════╗
║              recon.sh v1.0 — by yisus666-bit         ║
╚══════════════════════════════════════════════════════╝

[*] Target     : 10.10.11.25
[*] Mode       : Single Host
[*] Output dir : ./recon_output/10.10.11.25_20250610_142301/
[*] Started at : 2025-06-10 14:23:01

[+] Running Nmap scan...
    → Ports found: 22, 80, 443, 8080

[+] Running Gobuster on port 80...
    → /admin       (Status: 301)
    → /uploads     (Status: 200)
    → /api/v1      (Status: 200)
    → /config.php  (Status: 403)

[+] Running Nikto on port 80...
    → Outdated Apache version detected
    → X-Frame-Options header missing

[+] Running Nuclei...
    → [critical] CVE-2021-41773 — Apache Path Traversal
    → [medium]   Missing security headers

[✔] HTML Report generated: ./recon_output/report_10.10.11.25.html
[✔] Scan completed in 4m 32s
```
<img width="1239" height="907" alt="report" src="https://github.com/user-attachments/assets/c0d04851-d2e3-45a1-9442-2c1ea81c90ec" />


---

## Requirements

| Tool       | Install command                                  |
|------------|--------------------------------------------------|
| `nmap`     | `sudo apt install nmap`                          |
| `gobuster` | `sudo apt install gobuster`                      |
| `nikto`    | `sudo apt install nikto`                         |
| `nuclei`   | `go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest` |
| `wordlist` | `/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt` |

> All tools come pre-installed on **Kali Linux**. Nuclei templates update automatically on first run.

---

## Installation

```bash
# Clone the repository
git clone https://github.com/yisus666-bit/pentest-tools.git
cd pentest-tools

# Make the script executable
chmod +x recon.sh

# Optional: move to PATH for global access
sudo cp recon.sh /usr/local/bin/recon
```

---

## Usage

### Basic syntax

```bash
./recon.sh [MODE] [TARGET] [OPTIONS]
```

### Mode 1 — Single Host

```bash
# Scan a single IP or hostname
./recon.sh -t 10.10.11.25

# With custom output directory
./recon.sh -t 10.10.11.25 -o /tmp/results
```

### Mode 2 — File List

```bash
# Scan multiple targets from a .txt file (one host per line)
./recon.sh -f targets.txt

# Example targets.txt:
# 10.10.11.10
# 10.10.11.20
# 10.10.11.30
```

### Mode 3 — CIDR Range

```bash
# Scan an entire subnet
./recon.sh -c 192.168.1.0/24

# Limit to first discovery (fast mode)
./recon.sh -c 10.10.10.0/24 --fast
```

### Flags

| Flag           | Description                             |
|----------------|-----------------------------------------|
| `-t <host>`    | Single target IP or hostname            |
| `-f <file>`    | File with list of targets               |
| `-c <CIDR>`    | CIDR network range                      |
| `-o <dir>`     | Custom output directory                 |
| `--fast`       | Skip Nikto and Nuclei (faster scan)     |
| `--no-gobuster`| Skip directory brute-forcing            |
| `-h`           | Show help                               |

---

## Output Structure

```
recon_output/
└── 10.10.11.25_20250610_142301/
    ├── nmap_results.txt
    ├── gobuster_80.txt
    ├── gobuster_443.txt
    ├── nikto_80.txt
    ├── nuclei_results.txt
    └── report_10.10.11.25.html   ←  Main HTML report
```

---

## Tested Environments

| Environment          | Status  |
|----------------------|---------|
| Kali Linux 2024.x    | ✅ OK   |
| HackTheBox machines  | ✅ OK   |
| TryHackMe rooms      | ✅ OK   |
| Local VMware labs    | ✅ OK   |
| Bug bounty (authorized) | ✅ OK |

---

## Roadmap

- [ ] Add Feroxbuster as alternative to Gobuster
- [ ] OSINT module (Shodan, theHarvester)
- [ ] JSON output format
- [ ] Slack/Discord webhook notifications
- [ ] Docker container support

---

## 👤 Author

**Andres** ([@ysus696-bit])  
Network & Telecom Engineer transitioning into Cybersecurity  

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---
