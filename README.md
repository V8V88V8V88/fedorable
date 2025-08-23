# Fedorable

<div align="center">

**A powerful maintenance and optimization toolkit for Fedora Linux systems**

</div>

---

## ✨ Overview

Fedorable is a comprehensive system maintenance suite that keeps your Fedora installation clean, efficient, and well-maintained. The toolkit offers three seamless interfaces to match your workflow:

- 🛠️ **Standalone Bash Script** - For quick maintenance operations
- 💻 **Command-Line Interface** - For advanced control and automation
- 🖥️ **Modern GTK4 GUI** - For user-friendly visual management

---

## 🚀 Core Features

<details open>
<summary><b>System Maintenance</b></summary>
<br>

| Feature | Description |
|---------|-------------|
| **System Updates** | Keep your packages up-to-date with the latest features and security patches |
| **Package Cleanup** | Intelligently remove unused packages and dependencies to free up space |
| **DNF Cache Management** | Reclaim valuable disk space from accumulated package caches |
| **Old Kernel Removal** | Maintain only necessary kernel versions while preserving system stability |
| **Temporary File Cleanup** | Remove unnecessary temporary files that accumulate over time |

</details>

<details open>
<summary><b>System Optimization</b></summary>
<br>

| Feature | Description |
|---------|-------------|
| **Journal Management** | Control systemd journal size for better disk usage |
| **RPM Database Optimization** | Improve package management performance and reliability |
| **GRUB/Bootloader Updates** | Keep bootloader configuration current and optimized |
| **SSD TRIM Support** | Maintain SSD performance and extend drive lifespan |
| **Flatpak Management** | Clean and update Flatpak applications for better performance |
| **Failed Unit Reset** | Automatically fix stuck systemd services for smoother operation |

</details>

---

## 📦 Installation

<details open>
<summary><b>Dependencies</b></summary>
<br>

```bash
# Install required dependencies on Fedora
sudo dnf install python3-gobject gtk4 libadwaita
```

</details>

<details open>
<summary><b>Quick Install</b></summary>
<br>

```bash
# Clone the repository
git clone https://github.com/V8V88V8V88/fedorable.git
cd fedorable

# Make the script executable (for script-only usage)
chmod +x fedorable.sh

# Install the complete package with GUI and CLI
pip install .
```

</details>

---

## 🔧 Usage

<details open>
<summary><b>Bash Script</b></summary>
<br>

The standalone bash script provides a simple way to perform system maintenance:

```bash
# Run with default settings (requires root privileges)
sudo ./fedorable.sh

# Show available options
./fedorable.sh --help

# Run with specific options
sudo ./fedorable.sh --no-clean-temp --no-clean-kernels
```

</details>

<details open>
<summary><b>Command-Line Interface</b></summary>
<br>

The CLI offers more flexibility and control for advanced users and automation:

```bash
# View all available options
fedorable-cli --help

# Run all maintenance tasks
fedorable-cli

# Run with specific tasks enabled/disabled
fedorable-cli --no-clean-temp --update --autoremove

# Run in different modes
fedorable-cli --yes --dry-run
fedorable-cli --none --update --clean-dnf
```

</details>

<details open>
<summary><b>Graphical Interface</b></summary>
<br>

The GTK4 GUI provides the most user-friendly experience with real-time feedback:

```bash
# Launch the graphical application
fedorable-gui
```

<div align="center">
<i>Enjoy a beautiful, intuitive interface for managing your system maintenance</i>
</div>

</details>

---

## 📋 Maintenance Tasks

Fedorable performs a comprehensive set of system maintenance operations:

<table>
  <tr>
    <th align="left">Task</th>
    <th align="left">Description</th>
    <th align="center">Default</th>
  </tr>
  <tr>
    <td><b>Update</b></td>
    <td>Updates system packages with latest versions</td>
    <td align="center">✅</td>
  </tr>
  <tr>
    <td><b>Autoremove</b></td>
    <td>Removes unused dependencies and packages</td>
    <td align="center">✅</td>
  </tr>
  <tr>
    <td><b>Clean DNF</b></td>
    <td>Clears DNF package cache to free disk space</td>
    <td align="center">✅</td>
  </tr>
  <tr>
    <td><b>Clean Kernels</b></td>
    <td>Removes old kernel versions safely</td>
    <td align="center">✅</td>
  </tr>
  <tr>
    <td><b>Clean Journal</b></td>
    <td>Maintains systemd journal size within limits</td>
    <td align="center">✅</td>
  </tr>
  <tr>
    <td><b>Clean Temp</b></td>
    <td>Removes unnecessary temporary files</td>
    <td align="center">✅</td>
  </tr>
  <tr>
    <td><b>Update GRUB</b></td>
    <td>Updates bootloader configuration</td>
    <td align="center">✅</td>
  </tr>
  <tr>
    <td><b>Clean Flatpak</b></td>
    <td>Maintains Flatpak applications and runtime</td>
    <td align="center">✅</td>
  </tr>
  <tr>
    <td><b>Optimize RPM DB</b></td>
    <td>Improves package manager performance</td>
    <td align="center">✅</td>
  </tr>
  <tr>
    <td><b>Reset Failed Units</b></td>
    <td>Fixes stuck systemd services</td>
    <td align="center">✅</td>
  </tr>
  <tr>
    <td><b>TRIM</b></td>
    <td>Optimizes SSD performance</td>
    <td align="center">✅</td>
  </tr>
</table>

---

## 💻 Development

<details>
<summary><b>Setting Up Development Environment</b></summary>
<br>

```bash
# Set up a development environment
git clone https://github.com/V8V88V8V88/fedorable.git
cd fedorable
pip install -e .

# Run directly from source
python fedorable-gui/src/main.py
```

</details>

---

## 🔒 Security

Fedorable performs system-wide operations that require elevated privileges. Always review scripts before execution with sudo. While we prioritize system safety through careful coding practices and non-destructive operations, user discretion is advised.

---

## 👥 Contributing

Contributions are welcome! Whether it's bug reports, feature requests, documentation improvements, or code contributions, your help makes Fedorable better for everyone.

---

## 📄 License

This project is licensed under the MIT License.

---

<div align="center">

**Keep your Fedora system clean and optimized with Fedorable!**

</div>