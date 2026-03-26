# ⚡ WSB Flash Clean v3.1

<p align="center">
  <img src="wsb_flash_clean_v3.0.ico" width="180"/>
</p>

<p align="center">
  <b style="font-size:18px;">WSB TECH</b><br>
  <span style="font-size:13px;">by <b>Will Bezerra</b></span>
</p>

<p align="center">
  <b>Manual Windows cleaning • Safe and aggressive icon rebuild modes • Portable execution</b>
</p>

---

## 🚀 Overview

**WSB Flash Clean** is a portable Windows maintenance utility designed for **manual on-demand cleaning**.

Unlike the AutoClean branch, Flash Clean is focused on **click-to-run execution**, giving the user direct control over when maintenance tasks are performed.

---

## ⚙️ Core Features

- 🧠 Intelligent cache cleaning
- 🔐 Login & session preservation
- 🖥️ Safe icon cleaning mode
- 🔥 Aggressive deep icon rebuild mode
- 🧩 Portable `.ps1` workflow
- 🔔 WSB visual identity and structured logs
- 📦 No installation required

---

## 🔥 Available Editions

### 1. Editable / Development
- `WSBFlashClean v3.1.ps1`
- Aggressive icon cleaning
- Intended for development and internal editing

### 2. Safe Editable
- `WSBFlashClean v3.1(SAFE).ps1`
- Preserves desktop icon size, layout and auto-arrange settings
- Does not restart Explorer during icon cleaning

### 3. Public Protected (Safe)
- `WSBFlashClean v3.1(SAFE) - PUBLIC PROTECTED.ps1`
- Safe icon cleaning
- Public release with integrity validation

### 4. Public Protected (Aggressive)
- `WSBFlashClean v3.1 - AGGRESSIVE PUBLIC PROTECTED.ps1`
- Deep icon rebuild mode
- Public release with integrity validation

---

## 🧪 How It Works

### Manual Execution

```powershell
powershell -ExecutionPolicy Bypass -File "WSBFlashClean v3.1.ps1"
```

### Suggested Usage

| Scenario | Recommended File |
| -------- | ---------------- |
| Internal editing / development | `WSBFlashClean v3.1.ps1` |
| Manual safe cleaning | `WSBFlashClean v3.1(SAFE).ps1` |
| Public release (safe) | `WSBFlashClean v3.1(SAFE) - PUBLIC PROTECTED.ps1` |
| Public release (deep repair) | `WSBFlashClean v3.1 - AGGRESSIVE PUBLIC PROTECTED.ps1` |

---

## 🧼 What Gets Cleaned

- Windows temporary files
- System cache and logs
- Application cache
- Browser cache
- Icon cache and thumbnail cache
- Jump Lists and visual shell residues

---

## 🔒 What Is Preserved

- Cookies
- Login Data
- Web Data
- Sessions
- Local Storage
- IndexedDB
- Authentication tokens
- Critical application preferences

---

## 🛡️ Privacy & Security

- No telemetry
- No data collection
- No external connections
- 100% local processing

Public protected builds include:
- File integrity validation (self-hash)
- Local violation logging
- Safe fallback execution blocking when tampering is detected

---

## 📦 Project Structure

```text
WSB_Flash_Clean/
 ├── WSBFlashClean v3.1.ps1
 ├── WSBFlashClean v3.1(SAFE).ps1
 ├── WSBFlashClean v3.1(SAFE) - PUBLIC PROTECTED.ps1
 ├── WSBFlashClean v3.1 - AGGRESSIVE PUBLIC PROTECTED.ps1
 ├── wsb_flash_clean_v3.0.ico
 ├── build_wsb_flash_clean.bat
 ├── README.md
 ├── PRIVACY.md
 └── LICENSE.txt
```

---

## ⚠️ Notes

- Run as Administrator
- Safe builds are recommended for most users
- Aggressive icon rebuild may reset visual desktop preferences
- Public protected builds require the final SHA256 hash to be inserted before release

---

## 👨‍💻 Developer

**WSB TECH — Will Bezerra**

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
