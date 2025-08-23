#!/usr/bin/env python3
"""
Fedorable GTK GUI - Entry point script
"""

import sys
import os

# Add the parent directory to the path if running as script
if __name__ == "__main__" and __package__ is None:
    parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sys.path.insert(0, parent_dir)

# Import the main module
from main import main

# Run the application
if __name__ == "__main__":
    sys.exit(main())