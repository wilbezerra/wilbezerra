# ⚡ WSB Auto Clean GE v3.3.2

<p align="center">
  <img src="wsb_auto_clean_ge_v3.3.2.ico" width="180"/>
</p>

<p align="center">
  <b style="font-size:18px;">WSB TECH</b><br>
  <span style="font-size:13px;">by <b>Will Bezerra</b></span>
</p>

<p align="center">
  <b>Limpeza inteligente do Windows • Preserva logins • Automação silenciosa</b>
</p>

---

## 🚀 Overview

**WSB Auto Clean GE** is a portable Windows maintenance utility designed to perform **intelligent, safe cleaning** without removing logins, sessions, or critical application data.

The system uses an **adaptive cache detection engine**, allowing it to automatically clean newly installed applications without requiring updates.

---

## ⚙️ Core Features

- 🧠 Smart Cache Discovery Engine (AppData + System)
- 🔐 Full Login & Session Preservation
- ⚡ Silent Execution at Windows Startup
- 🔄 Self-Recovery Infrastructure (Auto Repair)
- 🧩 .ps1 and .exe Compatibility
- 🖥️ Deep Icon Cache Rebuild (Explorer Reset)
- 🔌 USB Sentinel (Monitoring + Protection)
- 🔔 WSB Toast Notification System
- 📦 Portable Architecture (No installation required)

---

## 🔥 What's New (v3.3.2 Enhanced)

- Intelligent auto-detection of cache folders for new applications
- Advanced whitelist/blacklist system to prevent profile corruption
- Improved preservation of authentication data (cookies, sessions, tokens)
- Safer AppData scanning without affecting critical structures
- Explorer rebuild refinement (prevents window loop/bugs)
- Stability improvements across browsers and Electron-based apps
- Unified cleaning logic across system and applications
- Prepared structure for future integrity protection (public builds)

---

## 🧪 How It Works

### Manual Execution

```powershell
powershell -ExecutionPolicy Bypass -File "WSBAutoClean.ps1"
```

### Behavior

| Action      | Result                  |
| ----------- | ----------------------- |
| First Run   | Enables automatic mode  |
| Second Run  | Disables automatic mode |
| System Boot | Runs cleaning silently  |

---

## 🧼 What Gets Cleaned

- Windows temporary files
- System cache and logs
- Application cache (auto-detected)
- Browser cache (Chromium & Firefox)
- GPU, shader and code caches

---

## 🔒 What Is Preserved

- Cookies
- Login Data
- Web Data
- Sessions
- Local Storage
- IndexedDB
- Authentication tokens

---

## 🛡️ Privacy & Security

- No telemetry
- No data collection
- No external connections
- 100% local processing

---

## 🧠 Architecture

- PowerShell Core Engine
- Task Scheduler Persistence
- WMI (USB Monitoring)
- WinRT (Toast System)
- Auto-Recovery Layer

---

## 📦 Project Structure

```
WSB_AutoClean_GE/
 ├── WSBAutoClean.ps1
 ├── WSBAutoClean.exe
 ├── wsb_auto_clean_ge_v3.3.2.ico
 ├── build_wsb_autoclean.bat
 ├── README.md
 └── LICENSE.txt
```

---

## ⚠️ Notes

- Run as Administrator
- First launch after cleaning may be slightly slower (cache rebuild)
- Avoid running alongside aggressive cleaning tools

---

## 👨‍💻 Developer

WSB TECH — Will Bezerra

---

## ⭐ Support

If you find this project useful, consider giving it a star on GitHub.

---

## ⚡ WSB TECH

Intelligent automation. Zero compromise on user experience.

---

## 🔐 Privacy Policy

This software does not collect, transmit, or store any personal data.  
All operations are performed locally on the user's machine.

For full details, see [Privacy Policy](PRIVACY.md)