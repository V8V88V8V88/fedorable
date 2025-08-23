"""
Command-line interface for Fedorable
"""

import argparse
import sys
import os
from . import __version__, core


def main():
    """Main entry point for the CLI"""
    args = parse_arguments()
    
    # Create the core object with configured script path
    try:
        fedorable = setup_fedorable_core(args)
        
        # Check if the script exists and is executable
        if not fedorable.is_script_executable():
            print(f"Error: Script not found or not executable: {fedorable.script_path}")
            return 1
        
        # Run the script
        return run_fedorable(fedorable, args.no_pkexec)
        
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


def parse_arguments():
    """Parse command-line arguments"""
    # Create the argument parser
    parser = argparse.ArgumentParser(
        description="Fedorable - Fedora System Maintenance",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    
    # Add version argument
    parser.add_argument('--version', action='version', version=f'Fedorable {__version__}')
    
    # Add script path argument
    parser.add_argument(
        '--script-path',
        help='Path to the fedorable.sh script',
        default=core.DEFAULT_SCRIPT_PATH
    )
    
    # Add no-pkexec argument
    parser.add_argument(
        '--no-pkexec',
        action='store_true',
        help="Don't use pkexec for privilege escalation (run directly)"
    )
    
    # Create a task group
    task_group = parser.add_argument_group('Tasks', 'Enable or disable specific maintenance tasks')
    
    # Add task arguments
    for name, task in core.FedorableCore.TASKS.items():
        task_group.add_argument(
            f'--{name.replace("_", "-")}',
            dest=f'task_{name}',
            action='store_true',
            default=None,
            help=f'Enable {task.description.lower()}'
        )
        task_group.add_argument(
            f'--no-{name.replace("_", "-")}',
            dest=f'task_{name}',
            action='store_false',
            help=f'Disable {task.description.lower()}'
        )
    
    # Create an options group
    option_group = parser.add_argument_group('Options', 'Script behavior options')
    
    # Add option arguments
    for name, option in core.FedorableCore.OPTIONS.items():
        option_group.add_argument(
            f'--{name.replace("_", "-")}',
            dest=f'option_{name}',
            action='store_true',
            help=option.description
        )
    
    # Add task preset arguments
    preset_group = parser.add_argument_group('Task Presets', 'Predefined task sets')
    preset_group.add_argument(
        '--all',
        action='store_true',
        help='Enable all tasks'
    )
    preset_group.add_argument(
        '--none',
        action='store_true',
        help='Disable all tasks'
    )
    
    return parser.parse_args()


def setup_fedorable_core(args):
    """
    Configure a FedorableCore object based on command-line arguments
    
    Args:
        args: Parsed command-line arguments
        
    Returns:
        FedorableCore: Configured core object
    """
    fedorable = core.FedorableCore(args.script_path)
    
    # Apply task presets
    if args.all:
        for name in fedorable.tasks:
            fedorable.tasks[name].enabled = True
    elif args.none:
        for name in fedorable.tasks:
            fedorable.tasks[name].enabled = False
    
    # Apply individual task settings
    for name in fedorable.tasks:
        arg_name = f'task_{name}'
        if hasattr(args, arg_name) and getattr(args, arg_name) is not None:
            fedorable.tasks[name].enabled = getattr(args, arg_name)
    
    # Apply option settings
    for name in fedorable.options:
        arg_name = f'option_{name}'
        if hasattr(args, arg_name) and getattr(args, arg_name):
            fedorable.options[name].enabled = True
            
    return fedorable


def run_fedorable(fedorable, no_pkexec=False):
    """
    Run the fedorable script with live output
    
    Args:
        fedorable: Configured FedorableCore object
        no_pkexec: Whether to skip pkexec
        
    Returns:
        int: Script exit code
    """
    # Define callback for real-time output
    def print_output(line, is_stderr):
        stream = sys.stderr if is_stderr else sys.stdout
        print(line, file=stream, end="")
    
    # Build and show the command
    command = fedorable.build_command(not no_pkexec)
    print(f"Running command: {' '.join(command)}")
    
    try:
        # Run the script
        return_code = fedorable.run(not no_pkexec, callback=print_output)
        print(f"\nScript exited with code: {return_code}")
        return return_code
    except Exception as e:
        print(f"Error running fedorable: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main()) 