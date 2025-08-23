"""
Core functionality for the Fedorable package.
Provides interfaces to the fedorable.sh script.
"""

import os
import subprocess
import sys
import threading
from pathlib import Path

# Calculate the default script path more reliably using Path
DEFAULT_SCRIPT_PATH = str(Path(__file__).parent.parent.parent / "fedorable.sh")

class FedorableTask:
    """
    Represents a maintenance task in the fedorable script
    """
    def __init__(self, name, description, enabled=True, flag=None):
        """
        Initialize a task
        
        Args:
            name (str): Internal task name
            description (str): Human-readable task description
            enabled (bool): Whether the task is enabled by default
            flag (str): Command-line flag (--no-flag)
        """
        self.name = name
        self.description = description
        self.enabled = enabled
        self.flag = flag or f"--no-{name.replace('_', '-')}"
    
    def __repr__(self):
        return f"<FedorableTask {self.name} enabled={self.enabled}>"


class FedorableOption:
    """
    Represents a command-line option for the fedorable script
    """
    def __init__(self, name, description, enabled=False, flag=None):
        """
        Initialize an option
        
        Args:
            name (str): Internal option name
            description (str): Human-readable option description
            enabled (bool): Whether the option is enabled by default
            flag (str): Command-line flag (--flag)
        """
        self.name = name
        self.description = description
        self.enabled = enabled
        self.flag = flag or f"--{name.replace('_', '-')}"
    
    def __repr__(self):
        return f"<FedorableOption {self.name} enabled={self.enabled}>"


class FedorableCore:
    """
    Core class for interacting with the fedorable.sh script
    """
    # Standard tasks available in fedorable.sh
    TASKS = {
        "update": FedorableTask("update", "Update System Packages", True),
        "autoremove": FedorableTask("autoremove", "Autoremove Unused Packages", True),
        "clean_dnf": FedorableTask("clean_dnf", "Clean DNF Cache", True),
        "clean_kernels": FedorableTask("clean_kernels", "Remove Old Kernels", True),
        "clean_journal": FedorableTask("clean_journal", "Clean System Journal", True),
        "clean_temp": FedorableTask("clean_temp", "Clean Temporary Files", True),
        "update_grub": FedorableTask("update_grub", "Update GRUB/Bootloader", True),
        "clean_flatpak": FedorableTask("clean_flatpak", "Clean/Update Flatpak", True),
        "optimize_rpmdb": FedorableTask("optimize_rpmdb", "Optimize RPM Database", True),
        "reset_failed_units": FedorableTask("reset_failed_units", "Reset Failed Systemd Units", True),
        "trim": FedorableTask("trim", "Run SSD TRIM", True),
    }
    
    # Standard options available in fedorable.sh
    OPTIONS = {
        "yes": FedorableOption("yes", "Assume 'Yes' to prompts", False),
        "dry_run": FedorableOption("dry_run", "Dry Run (No changes made)", False),
        "check_only": FedorableOption("check_only", "Check for Updates Only", False),
        "quiet": FedorableOption("quiet", "Quiet Mode (Less output)", False),
    }
    
    def __init__(self, script_path=None):
        """
        Initialize the core
        
        Args:
            script_path (str, optional): Path to the fedorable.sh script. If None, use the default.
        """
        self.script_path = script_path or DEFAULT_SCRIPT_PATH
        # Create copies of task and option dictionaries to avoid modifying class variables
        self.tasks = {name: FedorableTask(task.name, task.description, task.enabled) 
                     for name, task in self.TASKS.items()}
        self.options = {name: FedorableOption(option.name, option.description, option.enabled) 
                       for name, option in self.OPTIONS.items()}
        
    def is_script_executable(self):
        """Check if the script exists and is executable."""
        return os.path.exists(self.script_path) and os.access(self.script_path, os.X_OK)
    
    def build_command(self, use_pkexec=True):
        """
        Build the command line to run the script
        
        Args:
            use_pkexec (bool): Whether to use pkexec for privilege escalation
            
        Returns:
            list: Command line arguments list
        """
        # Start with the base command
        command = ["pkexec", self.script_path] if use_pkexec else [self.script_path]
        
        # Add disabled tasks
        for name, task in self.tasks.items():
            if not task.enabled:
                command.append(task.flag)
        
        # Add enabled options
        for name, option in self.options.items():
            if option.enabled:
                command.append(option.flag)
        
        return command
    
    def run(self, use_pkexec=True, callback=None):
        """
        Run the script
        
        Args:
            use_pkexec (bool): Whether to use pkexec for privilege escalation
            callback (callable): Callback function for output lines
            
        Returns:
            int: Return code from the script
            
        Raises:
            FileNotFoundError: If the script doesn't exist or isn't executable
        """
        if not self.is_script_executable():
            raise FileNotFoundError(f"Script not found or not executable: {self.script_path}")
        
        command = self.build_command(use_pkexec)
        
        if callback:
            return self._run_with_callback(command, callback)
        else:
            # Run without callback
            return subprocess.call(command)
    
    def _run_with_callback(self, command, callback):
        """
        Run the script with a callback for real-time output
        
        Args:
            command (list): Command line arguments
            callback (callable): Callback function for output lines
            
        Returns:
            int: Return code from the script
        """
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        # Create and start threads to read stdout and stderr
        threads = []
        for pipe, is_stderr in [(process.stdout, False), (process.stderr, True)]:
            thread = threading.Thread(
                target=self._read_output, 
                args=(pipe, is_stderr, callback)
            )
            thread.daemon = True
            thread.start()
            threads.append(thread)
        
        # Wait for process to finish
        return_code = process.wait()
        
        # Wait for threads to finish
        for thread in threads:
            thread.join()
        
        return return_code
    
    @staticmethod
    def _read_output(pipe, is_stderr, callback):
        """
        Read output from a pipe and send to callback
        
        Args:
            pipe (file): Pipe to read from
            is_stderr (bool): Whether this is stderr
            callback (callable): Callback function
        """
        for line in pipe:
            callback(line, is_stderr)


# Simple command-line interface when run directly
def main():
    """Command-line interface when run directly"""
    core = FedorableCore()
    
    if not core.is_script_executable():
        print(f"Error: Script not found or not executable: {core.script_path}")
        return 1
    
    # Use a simple callback to print output
    def print_output(line, is_stderr):
        stream = sys.stderr if is_stderr else sys.stdout
        print(line, file=stream, end="")
    
    print(f"Running fedorable script: {core.script_path}")
    try:
        return_code = core.run(callback=print_output)
        print(f"\nScript exited with code: {return_code}")
        return return_code
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

# For command-line usage
if __name__ == "__main__":
    sys.exit(main()) 