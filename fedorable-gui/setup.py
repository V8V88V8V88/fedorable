#!/usr/bin/env python3

from setuptools import setup, find_packages
import os
import re
from pathlib import Path

# Root directory of the project
ROOT_DIR = Path(__file__).parent

# Extract version with regex for better reliability
version_regex = re.compile(r'__version__\s*=\s*["\']([^"\']+)["\']')
try:
    init_file = ROOT_DIR / "src" / "fedorable" / "__init__.py"
    with open(init_file, "r") as f:
        version_match = version_regex.search(f.read())
        version = version_match.group(1) if version_match else "0.0.1"
except (FileNotFoundError, IOError):
    version = "0.0.1"

# Read README if available
readme_file = ROOT_DIR / "README.md"
try:
    with open(readme_file, "r", encoding="utf-8") as fh:
        long_description = fh.read()
except (FileNotFoundError, IOError):
    long_description = "A Fedora system maintenance toolkit"

# Create default README if not exists
if not readme_file.exists():
    default_readme = """# Fedorable

A Fedora system maintenance toolkit with CLI and GTK4 GUI interfaces.

## Features

- System updates and maintenance
- Package cleanup
- System optimization
- User-friendly graphical interface
- Command-line interface
"""
    with open(readme_file, "w", encoding="utf-8") as f:
        f.write(default_readme)
    long_description = default_readme

setup(
    name="fedorable",
    version=version,
    author="Fedorable Team",
    description="A Fedora system maintenance toolkit",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/username/fedorable",
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: POSIX :: Linux",
        "Environment :: X11 Applications :: GTK",
        "Topic :: System :: Systems Administration",
    ],
    package_dir={"": "src"},
    packages=find_packages(where="src"),
    include_package_data=True,
    python_requires=">=3.7",
    install_requires=[
        "PyGObject>=3.40.0",
    ],
    entry_points={
        "console_scripts": ["fedorable-cli=fedorable.cli:main"],
        "gui_scripts": ["fedorable-gui=main:main"],
    },
    data_files=[
        ('share/applications', ['data/fedorable-gui.desktop']),
        ('share/icons/hicolor/scalable/apps', ['data/fedorable-gui.svg']),
    ],
)