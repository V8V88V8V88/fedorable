# src/window.py
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib
from .tasks import SystemTasks

@Gtk.Template(resource_path='/com/github/fedorable/window.ui')
class FedorableWindow(Adw.ApplicationWindow):
    __gtype_name__ = 'FedorableWindow'

    # Template widgets
    main_stack = Gtk.Template.Child()
    tasks_list = Gtk.Template.Child()
    progress_bar = Gtk.Template.Child()
    status_label = Gtk.Template.Child()
    run_button = Gtk.Template.Child()

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.tasks = SystemTasks()
        self.setup_tasks()
        
    def setup_tasks(self):
        """Initialize the task list with available maintenance options."""
        task_names = [
            "Backup System Configurations",
            "Update System",
            "System Cleanup",
            "User Data Cleanup"
        ]
        
        for name in task_names:
            row = Adw.ActionRow(title=name)
            switch = Gtk.Switch(valign=Gtk.Align.CENTER)
            row.add_suffix(switch)
            self.tasks_list.append(row)
    
    @Gtk.Template.Callback()
    def on_run_clicked(self, button):
        """Handle run button click by collecting selected tasks and executing them."""
        selected_tasks = self._get_selected_tasks()
        
        if not selected_tasks:
            self._show_no_tasks_dialog()
            return
            
        self.run_tasks(selected_tasks)
    
    def _get_selected_tasks(self):
        """Get list of selected task indices."""
        selected_tasks = []
        for i, row in enumerate(self.tasks_list):
            switch = row.get_last_child()
            if switch.get_active():
                selected_tasks.append(i)
        return selected_tasks
    
    def _show_no_tasks_dialog(self):
        """Display a dialog when no tasks are selected."""
        dialog = Adw.MessageDialog(
            transient_for=self,
            heading="No Tasks Selected",
            body="Please select at least one task to run.",
            buttons=["OK"]
        )
        dialog.present()
    
    def run_tasks(self, task_indices):
        """Execute the selected tasks and update the UI accordingly."""
        # Disable button and show progress view
        self.run_button.set_sensitive(False)
        self.main_stack.set_visible_child_name('progress')
        
        total_tasks = len(task_indices)
        task_methods = [
            self.tasks.backup_system_config,
            self.tasks.update_system,
            self.tasks.cleanup_system,
            self.tasks.cleanup_user_data
        ]
        
        # Execute each selected task
        for i, task_idx in enumerate(task_indices):
            progress = (i / total_tasks)
            self.progress_bar.set_fraction(progress)
            
            task_name = self.tasks_list.get_row_at_index(task_idx).get_title()
            GLib.idle_add(self.status_label.set_text, f"Running {task_name}...")
            
            if 0 <= task_idx < len(task_methods):
                task_methods[task_idx]()
        
        # Reset UI state
        self.progress_bar.set_fraction(1.0)
        self.status_label.set_text("Tasks completed!")
        self.run_button.set_sensitive(True)
        self.main_stack.set_visible_child_name('tasks')