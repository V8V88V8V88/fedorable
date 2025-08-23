# Fedorable

A comprehensive Fedora system maintenance toolkit with CLI and GTK4 GUI interfaces.

## Features

- System updates and maintenance
- Package cleanup and auto-removal
- Old kernel management
- Systemd journal cleanup
- Temporary file removal
- GRUB/Bootloader updates
- Flatpak management
- RPM database optimization
- Systemd failed units reset
- SSD TRIM support
- User-friendly GTK4 graphical interface
- Command-line interface

## Installation

### Dependencies

```bash
# Install dependencies (Fedora)
sudo dnf install python3-gobject gtk4 libadwaita
```

### From Source

```bash
# Clone the repository
git clone https://github.com/username/fedorable.git
cd fedorable

# Install the package
pip install .

# Or install in development mode
pip install -e .
```

## Usage

### GUI

```bash
# Launch the graphical interface
fedorable-gui
```

### CLI

```bash
# Show help
fedorable-cli --help

# Run with default settings (all maintenance tasks)
fedorable-cli

# Run with specific tasks
fedorable-cli --no-clean-temp --update --autoremove

# Run with options
fedorable-cli --yes --dry-run

# Disable all tasks then selectively enable some
fedorable-cli --none --update --clean-dnf
```

### Bash Script

The package also includes a standalone bash script that can be used directly:

```bash
# Run with default settings
sudo ./fedorable.sh

# View available options
./fedorable.sh --help

# Run specific tasks only
sudo ./fedorable.sh --no-clean-temp --no-clean-kernels --no-trim
```

## Development

```bash
# Set up a development environment
git clone https://github.com/username/fedorable.git
cd fedorable
pip install -e .

# Run the application directly from source
python fedorable-gui/src/main.py
```

## License

MIT 