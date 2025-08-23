# src/tasks.py
import subprocess
import os
from pathlib import Path
import datetime

class SystemTasks:
    def __init__(self):
        if os.geteuid() != 0:
            raise PermissionError("This application must be run as root")
    
    def backup_system_config(self):
        """Backup important system configuration files."""
        backup_dir = Path(f"/root/system_backup_{datetime.date.today().strftime('%Y%m%d')}")
        backup_dir.mkdir(parents=True, exist_ok=True)
        
        configs = [
            "/etc/dnf",
            "/etc/fstab",
            "/etc/default/grub",
            "/etc/hostname",
            "/etc/hosts"
        ]
        
        for config in configs:
            config_path = Path(config)
            if not config_path.exists():
                continue
                
            try:
                if config_path.is_dir():
                    subprocess.run(['cp', '-r', str(config_path), str(backup_dir)], check=True)
                else:
                    subprocess.run(['cp', str(config_path), str(backup_dir)], check=True)
            except subprocess.CalledProcessError:
                print(f"Failed to backup {config}")
    
    def update_system(self):
        """Update system packages."""
        try:
            subprocess.run(['dnf', 'upgrade', '-y'], check=True)
        except subprocess.CalledProcessError:
            print("System update failed")
    
    def cleanup_system(self):
        """Remove unnecessary packages and clean DNF caches."""
        try:
            # Remove unneeded packages
            subprocess.run(['dnf', 'autoremove', '-y'], check=False)
            
            # Clean DNF caches
            subprocess.run(['dnf', 'clean', 'all'], check=False)
            
            # Rebuild cache
            subprocess.run(['dnf', 'makecache'], check=False)
            
            # Remove old kernels (using a safer approach)
            subprocess.run(['dnf', 'remove', '--oldinstallonly', '--setopt=installonly_limit=2', '-y'], check=False)
        except Exception as e:
            print(f"Cleanup error: {e}")
    
    def cleanup_user_data(self):
        """Clean user caches and history files."""
        try:
            # Clean thumbnails and cache directories
            for cache_dir in ['thumbnails', '.cache']:
                subprocess.run([
                    'find', '/home', '-type', 'd', '-name', cache_dir, 
                    '-exec', 'rm', '-rf', '{}', ';'
                ], check=False)
            
            # Clear bash history files
            subprocess.run(['truncate', '-s', '0', '/root/.bash_history'], check=False)
            subprocess.run([
                'find', '/home', '-name', '.bash_history', 
                '-exec', 'truncate', '-s', '0', '{}', ';'
            ], check=False)
        except Exception as e:
            print(f"User data cleanup error: {e}")
    
    def optimize_system(self):
        """Perform system optimizations."""
        try:
            # Update GRUB configuration
            subprocess.run(['grub2-mkconfig', '-o', '/boot/grub2/grub.cfg'], check=False)
            
            # Run FSTRIM if available
            if Path('/usr/sbin/fstrim').exists():
                subprocess.run(['fstrim', '-av'], check=False)
            
            # Rebuild RPM database
            subprocess.run(['rpm', '--rebuilddb'], check=False)
        except Exception as e:
            print(f"Optimization error: {e}")
    
    def run_task(self, task_number):
        """Run a specific task by number."""
        task_map = {
            1: self.backup_system_config,
            2: self.update_system,
            3: self.cleanup_system,
            4: self.cleanup_user_data,
            5: self.optimize_system
        }
        
        if task_number in task_map:
            task_map[task_number]()