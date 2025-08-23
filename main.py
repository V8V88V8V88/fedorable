#!/usr/bin/env python3

import sys
import os
import shlex
import fedorable.core

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib, Gio

# Use the default script path from the fedorable module
FEDORABLE_SCRIPT_PATH = fedorable.core.DEFAULT_SCRIPT_PATH
APP_ID = "io.github.v8v88v8v88.fedorablegtk"

class FedorableGtkApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.window = None

    def do_activate(self):
        if not self.window:
            self.window = FedorableMainWindow(application=self)
            self._check_script_availability()
        self.window.present()
        
    def _check_script_availability(self):
        """Check if the fedorable script exists and is executable"""
        if not os.path.exists(FEDORABLE_SCRIPT_PATH):
            self.window.show_error_dialog(
                "Error: Fedorable script not found!",
                f"Please ensure '{FEDORABLE_SCRIPT_PATH}' exists and is executable.\n"
                "You might need to adjust the FEDORABLE_SCRIPT_PATH variable in the Python script."
            )
        elif not os.access(FEDORABLE_SCRIPT_PATH, os.X_OK):
            self.window.show_error_dialog(
                "Error: Fedorable script not executable!",
                f"Please make '{FEDORABLE_SCRIPT_PATH}' executable (chmod +x)."
            )

class FedorableMainWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        self.process = None
        # Initialize the fedorable core
        self.fedorable = fedorable.core.FedorableCore(FEDORABLE_SCRIPT_PATH)

        self.set_title("Fedorable Maintenance GUI")
        self.set_default_size(800, 700)

        # --- UI Elements ---
        self.main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.set_content(self.main_box)

        # --- Task Panes ---
        paned = Gtk.Paned(orientation=Gtk.Orientation.VERTICAL, wide_handle=True, position=350)
        self.main_box.append(paned)

        # Top Pane: Controls
        controls_scrolled_window = Gtk.ScrolledWindow()
        controls_scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        controls_scrolled_window.set_vexpand(False)
        paned.set_start_child(controls_scrolled_window)

        controls_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=15, margin_top=10, margin_bottom=10, margin_start=10, margin_end=10)
        controls_scrolled_window.set_child(controls_box)

        # --- Checkboxes for Tasks ---
        self._setup_tasks_ui(controls_box)

        # --- Switches for Options ---
        self._setup_options_ui(controls_box)

        # --- Run Button ---
        self._setup_buttons(controls_box)

        # --- Bottom Pane: Output ---
        self._setup_output_view(paned)

        # --- Status Bar ---
        self.status_label = Gtk.Label(label="Ready.", xalign=0, margin_start=10, margin_end=10, margin_bottom=5)
        self.main_box.append(self.status_label)

    def _setup_tasks_ui(self, parent_box):
        """Setup the task checkboxes UI"""
        tasks_frame = Gtk.Frame(label=" Maintenance Tasks ")
        tasks_grid = Gtk.Grid(column_spacing=10, row_spacing=5, margin_top=5, margin_bottom=5, margin_start=5, margin_end=5)
        tasks_frame.set_child(tasks_grid)
        parent_box.append(tasks_frame)

        self.task_checkboxes = {}
        tasks = {name: (task.description, task.enabled) for name, task in self.fedorable.tasks.items()}
        row, col = 0, 0
        for key, (label, default) in tasks.items():
            cb = Gtk.CheckButton(label=label)
            cb.set_active(default)
            self.task_checkboxes[key] = cb
            tasks_grid.attach(cb, col, row, 1, 1)
            col += 1
            if col > 1:
                col = 0
                row += 1

    def _setup_options_ui(self, parent_box):
        """Setup the options switches UI"""
        options_frame = Gtk.Frame(label=" Options ")
        options_grid = Gtk.Grid(column_spacing=10, row_spacing=5, margin_top=5, margin_bottom=5, margin_start=5, margin_end=5)
        options_frame.set_child(options_grid)
        parent_box.append(options_frame)

        self.option_switches = {}
        options = {name: (option.description, option.enabled) for name, option in self.fedorable.options.items()}
        row, col = 0, 0
        for key, (label, default) in options.items():
            widget = Gtk.Switch()
            widget.set_active(default)
            hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            hbox.append(Gtk.Label(label=label, xalign=0))
            hbox.append(widget)
            options_grid.attach(hbox, col, row, 1, 1)
            
            self.option_switches[key] = widget
            col += 1
            if col > 1:
                col = 0
                row += 1

    def _setup_buttons(self, parent_box):
        """Setup the action buttons"""
        run_button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, halign=Gtk.Align.CENTER, spacing=10, margin_top=15)
        parent_box.append(run_button_box)

        self.run_button = Gtk.Button(label="Run Maintenance")
        self.run_button.add_css_class("suggested-action")
        self.run_button.connect("clicked", self.on_run_clicked)
        run_button_box.append(self.run_button)

        self.clear_button = Gtk.Button(label="Clear Output")
        self.clear_button.connect("clicked", self.on_clear_clicked)
        run_button_box.append(self.clear_button)

    def _setup_output_view(self, parent_pane):
        """Setup the output text view"""
        output_scrolled_window = Gtk.ScrolledWindow()
        output_scrolled_window.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        output_scrolled_window.set_vexpand(True)
        parent_pane.set_end_child(output_scrolled_window)

        self.output_view = Gtk.TextView()
        self.output_view.set_editable(False)
        self.output_view.set_cursor_visible(False)
        self.output_view.set_monospace(True)
        buffer = self.output_view.get_buffer()
        self.stderr_tag = buffer.create_tag("stderr", foreground="red")
        self.stdout_tag = buffer.create_tag("stdout", foreground="black")
        output_scrolled_window.set_child(self.output_view)

    def update_statusbar(self, text):
        """Update the status bar with text"""
        self.status_label.set_text(text)

    def show_error_dialog(self, primary_text, secondary_text=None):
        """Show an error dialog with primary and secondary text"""
        dialog = Adw.MessageDialog(transient_for=self, modal=True)
        dialog.set_heading("Error")
        dialog.set_body(primary_text)
        if secondary_text:
             dialog.set_extra_info(secondary_text)
        dialog.add_response("ok", "OK")
        dialog.connect("response", lambda d, r: d.close())
        dialog.present()

    def on_clear_clicked(self, button):
        """Handle clear button click"""
        buffer = self.output_view.get_buffer()
        buffer.set_text("")
        self.update_statusbar("Output cleared.")

    def set_controls_sensitive(self, sensitive):
        """Enable or disable all controls"""
        self.run_button.set_sensitive(sensitive)
        for cb in self.task_checkboxes.values():
            cb.set_sensitive(sensitive)
        for sw in self.option_switches.values():
            sw.set_sensitive(sensitive)
        self.clear_button.set_sensitive(sensitive)

    def build_command(self):
        """Build command line by updating the core object and getting its command"""
        # Update the core's tasks based on checkboxes
        for key, cb in self.task_checkboxes.items():
            if key in self.fedorable.tasks:
                self.fedorable.tasks[key].enabled = cb.get_active()
        
        # Update the core's options based on switches
        for key, sw in self.option_switches.items():
            if key in self.fedorable.options:
                self.fedorable.options[key].enabled = sw.get_active()
        
        # Build the command using the core
        return self.fedorable.build_command(use_pkexec=True)

    def append_output(self, text, tag):
        """Append text to the output view with the specified tag"""
        buffer = self.output_view.get_buffer()
        buffer.insert_with_tags(buffer.get_end_iter(), text, tag)
        self._auto_scroll_output()
        return False  # For GLib.idle_add

    def _auto_scroll_output(self):
        """Auto-scroll the output view if near the bottom"""
        adj = self.output_view.get_parent().get_vadjustment()
        # Check if near the bottom before auto-scrolling
        if adj.get_value() >= adj.get_upper() - adj.get_page_size() - 50:
            adj.set_value(adj.get_upper() - adj.get_page_size())

    def on_run_clicked(self, button):
        """Handle run button click"""
        if self.process:
            self.update_statusbar("Maintenance is already running.")
            return
            
        # Validate script existence and permissions
        if not self.fedorable.is_script_executable():
            self.show_error_dialog("Error: Script not found or not executable", 
                                  f"Cannot run: {self.fedorable.script_path}")
            return

        # Prepare UI and command
        command = self.build_command()
        self.on_clear_clicked(None)
        self.update_statusbar("Starting maintenance...")
        self.append_output(f"Running command: {' '.join(shlex.quote(c) for c in command)}\n\n", self.stdout_tag)
        self.set_controls_sensitive(False)

        try:
            # Spawn async process using GSubprocess
            self.process = Gio.Subprocess.new(
                 command,
                 flags=Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
            )

            # Communicate asynchronously to get streams
            self.process.communicate_utf8_async(None, None, self._on_process_communication_finished)

        except GLib.Error as e:
            self._handle_process_error(f"Failed to start process: {e.message}", e.message)
        except Exception as e:
            self._handle_process_error(f"Unexpected error starting process: {e}", str(e))

    def _handle_process_error(self, log_message, error_details):
        """Handle process execution errors"""
        print(log_message)
        self.show_error_dialog("Error Starting Process", 
                              f"Could not launch the maintenance script.\nDetails: {error_details}")
        self._finalize_run(False, -1)

    def _on_process_communication_finished(self, process, result):
        """Callback after Gio.Subprocess.communicate_utf8_async finishes"""
        try:
            success, stdout_data, stderr_data = process.communicate_utf8_finish(result)

            if stdout_data:
                 self.append_output(stdout_data, self.stdout_tag)
            if stderr_data:
                 self.append_output(stderr_data, self.stderr_tag)

            # Get exit status and finalize
            exit_status = process.get_exit_status()
            self._finalize_run(exit_status == 0, exit_status)

        except GLib.Error as e:
            print(f"Error during process communication: {e.message}")
            self.append_output(f"\n[GUI Communication Error: {e.message}]\n", self.stderr_tag)
            exit_status = process.get_exit_status() if process.get_if_exited() else -1
            self._finalize_run(False, exit_status)
        except Exception as e:
            print(f"Unexpected error during process communication: {e}")
            self.append_output(f"\n[GUI Unexpected Communication Error: {e}]\n", self.stderr_tag)
            exit_status = process.get_exit_status() if process.get_if_exited() else -1
            self._finalize_run(False, exit_status)
        finally:
            self.process = None

    def _finalize_run(self, success, exit_status):
        """Update UI after process finishes (runs on main thread)"""
        if success:
            self.update_statusbar("Maintenance finished successfully.")
            self.append_output("\n--- Maintenance Finished Successfully ---\n", self.stdout_tag)
        else:
            self.update_statusbar(f"Maintenance failed (Exit Code: {exit_status}). Check output.")
            self.append_output(f"\n--- Maintenance Failed (Exit Code: {exit_status}) ---\n", self.stderr_tag)
        self.set_controls_sensitive(True)
        return False

# --- Main Execution ---
def main():
    """Main entry point for the application"""
    app = FedorableGtkApp()
    return app.run(sys.argv)

if __name__ == "__main__":
    sys.exit(main())