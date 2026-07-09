"""
GTK3 GUI for ocws-llm-runner.
Local-first LLM chat and OCR assistant with full model/session management.
"""

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib
import threading
import requests
import json
import os


def _load_css():
    """Load tokens.css + app CSS from one provider so @define-color scoping works."""
    css = ""

    tokens_path = os.path.expanduser("~/.config/ocws/tokens.css")
    if os.path.isfile(tokens_path):
        with open(tokens_path) as f:
            css += f.read() + "\n"

    css += """
window {
    background-color: @theme_bg_color;
}

headerbar {
    background-color: @theme_bg_color;
    border-bottom: 1px solid @theme_fg_color;
}

headerbar title {
    color: @theme_text_color;
    font-weight: bold;
}

.sidebar {
    background-color: @theme_bg_color;
    border-right: 1px solid @theme_fg_color;
    padding: 8px;
}

.sidebar button {
    padding: 8px 12px;
    margin: 2px 0;
    border-radius: 8px;
    background-color: transparent;
    color: @theme_text_color;
    text-align: left;
}

.sidebar button:hover {
    background-color: @theme_bg_color;
    color: @theme_text_color;
}

.sidebar button.active {
    background-color: @theme_selected_bg_color;
    color: @theme_selected_fg_color;
}

.sidebar button.danger {
    color: @theme_text_color;
}

.sidebar button.danger:hover {
    background-color: @theme_bg_color;
}

.chat-area {
    background-color: @theme_bg_color;
    padding: 8px;
}

.message-user {
    background-color: @theme_selected_bg_color;
    border-radius: 12px;
    padding: 12px 16px;
    margin: 4px 60px 4px 120px;
    color: @theme_text_color;
}

.message-assistant {
    background-color: @theme_bg_color;
    border-radius: 12px;
    padding: 12px 16px;
    margin: 4px 120px 4px 60px;
    color: @theme_text_color;
}

.message-system {
    background-color: @theme_bg_color;
    border-radius: 8px;
    padding: 8px 12px;
    margin: 4px 80px;
    color: @theme_text_color;
    font-size: 11px;
}

.input-area {
    background-color: @theme_bg_color;
    border-top: 1px solid @theme_fg_color;
    padding: 8px;
}

.input-entry {
    background-color: @theme_bg_color;
    border: 1px solid @theme_fg_color;
    border-radius: 8px;
    padding: 8px 12px;
    color: @theme_text_color;
    font-size: 13px;
}

.input-entry:focus {
    border-color: @theme_selected_bg_color;
}

.send-button {
    background-color: @theme_selected_bg_color;
    color: @theme_selected_fg_color;
    border-radius: 8px;
    padding: 8px 16px;
    font-weight: bold;
}

.send-button:hover {
    background-color: @theme_selected_bg_color;
}

.ocr-button {
    background-color: transparent;
    color: @theme_text_color;
    border-radius: 8px;
    padding: 8px 12px;
}

.ocr-button:hover {
    background-color: @theme_bg_color;
}

.status-bar {
    background-color: @theme_bg_color;
    border-top: 1px solid @theme_fg_color;
    padding: 4px 8px;
    color: @theme_text_color;
    font-size: 11px;
}

.model-active {
    background-color: transparent;
    border-radius: 6px;
    padding: 4px 8px;
    color: @theme_selected_bg_color;
}

.model-inactive {
    background-color: transparent;
    border-radius: 6px;
    padding: 4px 8px;
    color: @theme_text_color;
}

session-item {
    padding: 6px 8px;
    margin: 2px 0;
    border-radius: 6px;
}

session-item:hover {
    background-color: @theme_bg_color;
}

session-item.active {
    background-color: @theme_bg_color;
    border-left: 3px solid @theme_selected_bg_color;
}

scrollbar {
    background-color: transparent;
}

scrollbar slider {
    background-color: @theme_bg_color;
    border-radius: 4px;
    min-width: 6px;
    min-height: 6px;
}

scrollbar slider:hover {
    background-color: @theme_bg_color;
}

frame {
    border: none;
}

frame > border {
    border: none;
}
"""
    return css


CSS = _load_css()


class LLMRunnerApp:
    """Main GTK3 application for ocws-llm-runner."""
    
    def __init__(self, port=5000):
        self.port = port
        self.base_url = f"http://127.0.0.1:{port}"
        self.session_id = None
        
        # Apply CSS
        self.css_provider = Gtk.CssProvider()
        self.css_provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            self.css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )
        
        # Create application
        self.app = Gtk.Application(
            application_id="org.ocws.llm-runner",
            flags=Gtk.ApplicationFlags.DEFAULT_FLAGS
        )
        self.app.connect("activate", self.on_activate)
    
    def on_activate(self, app):
        """Build the UI."""
        self.window = Gtk.ApplicationWindow(application=app)
        self.window.set_title("OCWS LLM Runner")
        self.window.set_default_size(1000, 700)
        self.window.set_position(Gtk.WindowPosition.CENTER)
        
        # Header bar with controls
        self.header = Gtk.HeaderBar()
        self.header.set_show_close_button(True)
        self.header.set_title("OCWS LLM Runner")
        self.header.set_subtitle("Local-first LLM Chat & OCR Assistant")
        
        # Header buttons
        self._build_header_buttons()
        
        self.window.set_titlebar(self.header)
        
        # Main layout
        main_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        self.window.add(main_box)
        
        # Left sidebar (sessions + model)
        left_sidebar = self._build_left_sidebar()
        main_box.pack_start(left_sidebar, False, False, 0)
        
        # Separator
        main_box.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
        
        # Chat area (center)
        chat_box = self._build_chat_area()
        main_box.pack_start(chat_box, True, True, 0)
        
        # Initialize session
        GLib.idle_add(self._init_session)
        
        self.window.show_all()
    
    # ============================================================
    # Header Bar
    # ============================================================
    
    def _build_header_buttons(self):
        """Add buttons to header bar."""
        # Server status indicator
        self.server_status = Gtk.Label(label="●")
        self.server_status.get_style_context().add_class("model-inactive")
        self.header.pack_start(self.server_status)
        
        # Stop button
        stop_btn = Gtk.Button(label="⏹ Stop")
        stop_btn.connect("clicked", self.on_stop_server)
        self.header.pack_start(stop_btn)
        
        # Start button
        start_btn = Gtk.Button(label="▶ Start")
        start_btn.connect("clicked", self.on_start_server)
        self.header.pack_start(start_btn)
        
        # Separator
        sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        self.header.pack_start(sep)
        
        # Refresh button
        refresh_btn = Gtk.Button(label="↻ Refresh")
        refresh_btn.connect("clicked", self.on_refresh_status)
        self.header.pack_end(refresh_btn)
    
    # ============================================================
    # Left Sidebar (Sessions + Model)
    # ============================================================
    
    def _build_left_sidebar(self):
        """Build left sidebar with sessions list and model info."""
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        sidebar.get_style_context().add_class("sidebar")
        sidebar.set_size_request(220, -1)
        
        # --- Sessions Section ---
        sessions_label = Gtk.Label(label="Sessions")
        sessions_label.set_xalign(0)
        sessions_label.get_style_context().add_class("dim-label")
        sidebar.pack_start(sessions_label, False, False, 4)
        
        # New session button
        new_session_btn = Gtk.Button(label="+ New Session")
        new_session_btn.connect("clicked", self.on_new_session)
        sidebar.pack_start(new_session_btn, False, False, 0)
        
        # Sessions list (scrollable)
        self.sessions_scroll = Gtk.ScrolledWindow()
        self.sessions_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.sessions_scroll.set_size_request(-1, 200)
        
        self.sessions_list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.sessions_scroll.add(self.sessions_list)
        sidebar.pack_start(self.sessions_scroll, False, False, 0)
        
        # Separator
        sidebar.pack_start(Gtk.Separator(), False, False, 8)
        
        # --- Model Section ---
        model_label = Gtk.Label(label="Model")
        model_label.set_xalign(0)
        model_label.get_style_context().add_class("dim-label")
        sidebar.pack_start(model_label, False, False, 4)
        
        # Current model status
        self.model_status = Gtk.Label(label="No model loaded")
        self.model_status.set_xalign(0)
        self.model_status.set_line_wrap(True)
        self.model_status.get_style_context().add_class("model-inactive")
        sidebar.pack_start(self.model_status, False, False, 0)
        
        # Model controls
        model_controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        
        load_btn = Gtk.Button(label="Load")
        load_btn.connect("clicked", self.on_load_model)
        model_controls.pack_start(load_btn, True, True, 0)
        
        eject_btn = Gtk.Button(label="Eject")
        eject_btn.get_style_context().add_class("danger")
        eject_btn.connect("clicked", self.on_eject_model)
        model_controls.pack_start(eject_btn, True, True, 0)
        
        sidebar.pack_start(model_controls, False, False, 4)
        
        # Quick model switch (combo)
        self.model_combo = Gtk.ComboBoxText()
        self.model_combo.connect("changed", self.on_model_combo_changed)
        sidebar.pack_start(self.model_combo, False, False, 0)
        
        browse_btn = Gtk.Button(label="Browse GGUF Files...")
        browse_btn.connect("clicked", self.on_browse_models)
        sidebar.pack_start(browse_btn, False, False, 4)
        
        download_btn = Gtk.Button(label="Download Model...")
        download_btn.connect("clicked", self.on_download_model)
        sidebar.pack_start(download_btn, False, False, 0)
        
        # Separator
        sidebar.pack_start(Gtk.Separator(), False, False, 8)
        
        # --- System Prompt ---
        prompt_label = Gtk.Label(label="System Prompt")
        prompt_label.set_xalign(0)
        prompt_label.get_style_context().add_class("dim-label")
        sidebar.pack_start(prompt_label, False, False, 4)
        
        self.system_prompt = Gtk.TextView()
        self.system_prompt.set_wrap_mode(Gtk.WrapMode.WORD)
        self.system_prompt.set_size_request(-1, 60)
        self.system_prompt.get_buffer().set_text("You are a helpful assistant.")
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.system_prompt)
        sidebar.pack_start(scroll, False, False, 0)
        
        return sidebar
    
    # ============================================================
    # Chat Area
    # ============================================================
    
    def _build_chat_area(self):
        """Build the chat display and input area."""
        chat_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        chat_box.get_style_context().add_class("chat-area")
        
        # Chat display
        self.chat_scroll = Gtk.ScrolledWindow()
        self.chat_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        
        self.chat_display = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.chat_display.set_margin_start(8)
        self.chat_display.set_margin_end(8)
        self.chat_display.set_margin_top(8)
        self.chat_display.set_margin_bottom(8)
        
        self.chat_scroll.add(self.chat_display)
        chat_box.pack_start(self.chat_scroll, True, True, 0)
        
        # Input area
        input_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        input_box.get_style_context().add_class("input-area")
        input_box.set_margin_start(8)
        input_box.set_margin_end(8)
        input_box.set_margin_bottom(8)
        
        ocr_btn = Gtk.Button(label="OCR")
        ocr_btn.get_style_context().add_class("ocr-button")
        ocr_btn.connect("clicked", self.on_ocr_region)
        input_box.pack_start(ocr_btn, False, False, 0)
        
        self.input_entry = Gtk.TextView()
        self.input_entry.set_wrap_mode(Gtk.WrapMode.WORD)
        self.input_entry.set_size_request(-1, 40)
        self.input_entry.get_style_context().add_class("input-entry")
        self.input_entry.connect("key-press-event", self.on_entry_keypress)
        
        entry_scroll = Gtk.ScrolledWindow()
        entry_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        entry_scroll.add(self.input_entry)
        input_box.pack_start(entry_scroll, True, True, 0)
        
        send_btn = Gtk.Button(label="Send")
        send_btn.get_style_context().add_class("send-button")
        send_btn.connect("clicked", self.on_send_message)
        input_box.pack_start(send_btn, False, False, 0)
        
        chat_box.pack_start(input_box, False, False, 0)
        
        # Status bar
        self.status_bar = Gtk.Label(label="Ready")
        self.status_bar.set_xalign(0)
        self.status_bar.get_style_context().add_class("status-bar")
        chat_box.pack_start(self.status_bar, False, False, 0)
        
        return chat_box
    
    # ============================================================
    # Session Management
    # ============================================================
    
    def _init_session(self):
        """Initialize session on startup."""
        try:
            response = requests.get(f"{self.base_url}/api/sessions/active", timeout=5)
            if response.status_code == 200:
                data = response.json()
                self.session_id = data.get("id")
                self._refresh_sessions_list()
                self._load_chat_history()
        except Exception:
            pass
        
        GLib.idle_add(self._refresh_all)
        return False
    
    def _refresh_sessions_list(self):
        """Refresh the sessions list in sidebar."""
        # Clear existing
        for child in self.sessions_list.get_children():
            self.sessions_list.remove(child)
        
        try:
            response = requests.get(f"{self.base_url}/api/sessions", timeout=5)
            if response.status_code == 200:
                data = response.json()
                sessions = data.get("sessions", [])
                active_id = data.get("active")
                
                for session in sessions:
                    item = self._create_session_item(session, active_id)
                    self.sessions_list.pack_start(item, False, False, 0)
                
                self.sessions_list.show_all()
        except Exception:
            pass
    
    def _create_session_item(self, session, active_id):
        """Create a session list item widget."""
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.get_style_context().add_class("session-item")
        
        if session["id"] == active_id:
            box.get_style_context().add_class("active")
        
        # Session info
        info_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        
        name_label = Gtk.Label(label=session.get("name", "Unnamed"))
        name_label.set_xalign(0)
        name_label.set_ellipsize(3)  # Pango.EllipsizeMode.END
        info_box.pack_start(name_label, False, False, 0)
        
        msg_count = session.get("message_count", 0)
        meta_label = Gtk.Label(label=f"{msg_count} messages")
        meta_label.set_xalign(0)
        meta_label.get_style_context().add_class("dim-label")
        meta_label.set_margin_left(8)
        info_box.pack_start(meta_label, False, False, 0)
        
        box.pack_start(info_box, True, True, 0)
        
        # Click to activate
        event_box = Gtk.EventBox()
        event_box.add(box)
        event_box.connect("button-press-event", self._on_session_click, session["id"])
        
        return event_box
    
    def _on_session_click(self, widget, event, session_id):
        """Handle session click."""
        if event.button == 1:  # Left click
            self._switch_session(session_id)
        elif event.button == 3:  # Right click
            self._show_session_context_menu(session_id, event)
    
    def _switch_session(self, session_id):
        """Switch to a different session."""
        try:
            requests.put(
                f"{self.base_url}/api/sessions/active",
                json={"session_id": session_id},
                timeout=5
            )
            self.session_id = session_id
            self._refresh_sessions_list()
            self._load_chat_history()
        except Exception as e:
            self.status_bar.set_text(f"Error switching session: {e}")
    
    def _load_chat_history(self):
        """Load chat history for current session."""
        # Clear current display
        for child in self.chat_display.get_children():
            self.chat_display.remove(child)
        
        if not self.session_id:
            self.add_message("system", "No session selected")
            return
        
        try:
            response = requests.get(
                f"{self.base_url}/api/sessions/{self.session_id}/history",
                timeout=5
            )
            if response.status_code == 200:
                data = response.json()
                history = data.get("history", [])
                
                if not history:
                    self.add_message("system", "New conversation started")
                else:
                    for msg in history:
                        role = msg.get("role", "user")
                        content = msg.get("content", "")
                        self.add_message(role, content)
        except Exception:
            self.add_message("system", "Could not load history")
    
    def _show_session_context_menu(self, session_id, event):
        """Show context menu for session."""
        menu = Gtk.Menu()
        
        rename_item = Gtk.MenuItem(label="Rename")
        rename_item.connect("activate", self._on_rename_session, session_id)
        menu.append(rename_item)
        
        delete_item = Gtk.MenuItem(label="Delete")
        delete_item.connect("activate", self._on_delete_session, session_id)
        menu.append(delete_item)
        
        export_item = Gtk.MenuItem(label="Export")
        export_item.connect("activate", self._on_export_session, session_id)
        menu.append(export_item)
        
        menu.show_all()
        menu.popup_at_pointer(event)
    
    def _on_rename_session(self, widget, session_id):
        """Rename a session."""
        dialog = Gtk.Dialog(
            title="Rename Session",
            parent=self.window,
            flags=Gtk.DialogFlags.MODAL,
            buttons=(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                     Gtk.STOCK_OK, Gtk.ResponseType.OK)
        )
        
        entry = Gtk.Entry()
        entry.set_hexpand(True)
        dialog.get_content_area().pack_start(entry, True, True, 12)
        
        dialog.show_all()
        response = dialog.run()
        
        if response == Gtk.ResponseType.OK:
            new_name = entry.get_text().strip()
            if new_name:
                try:
                    requests.put(
                        f"{self.base_url}/api/sessions/{session_id}",
                        json={"name": new_name},
                        timeout=5
                    )
                    self._refresh_sessions_list()
                except Exception as e:
                    self.status_bar.set_text(f"Rename failed: {e}")
        
        dialog.destroy()
    
    def _on_delete_session(self, widget, session_id):
        """Delete a session."""
        dialog = Gtk.MessageDialog(
            parent=self.window,
            flags=Gtk.DialogFlags.MODAL,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.YES_NO,
            text="Delete this session?"
        )
        
        response = dialog.run()
        dialog.destroy()
        
        if response == Gtk.ResponseType.YES:
            try:
                requests.delete(
                    f"{self.base_url}/api/sessions/{session_id}",
                    timeout=5
                )
                self._refresh_sessions_list()
                self.status_bar.set_text("Session deleted")
            except Exception as e:
                self.status_bar.set_text(f"Delete failed: {e}")
    
    def _on_export_session(self, widget, session_id):
        """Export session to file."""
        dialog = Gtk.FileChooserDialog(
            title="Export Session",
            parent=self.window,
            action=Gtk.FileChooserAction.SAVE
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_SAVE, Gtk.ResponseType.OK
        )
        dialog.set_current_name(f"session-{session_id}.json")
        
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            filepath = dialog.get_filename()
            try:
                resp = requests.get(
                    f"{self.base_url}/api/export/session/{session_id}",
                    timeout=5
                )
                if resp.status_code == 200:
                    with open(filepath, "w") as f:
                        json.dump(resp.json(), f, indent=2)
                    self.status_bar.set_text(f"Exported to {filepath}")
            except Exception as e:
                self.status_bar.set_text(f"Export failed: {e}")
        
        dialog.destroy()
    
    def on_new_session(self, button):
        """Create a new session."""
        try:
            response = requests.post(
                f"{self.base_url}/api/sessions",
                json={"name": f"Session {__import__('datetime').datetime.now().strftime('%H:%M')}"},
                timeout=5
            )
            if response.status_code == 200:
                data = response.json()
                self.session_id = data.get("session_id")
                self._refresh_sessions_list()
                self._load_chat_history()
                self.status_bar.set_text("New session created")
        except Exception as e:
            self.status_bar.set_text(f"Error: {e}")
    
    # ============================================================
    # Model Management
    # ============================================================
    
    def _refresh_model_info(self):
        """Refresh model info in sidebar."""
        try:
            response = requests.get(f"{self.base_url}/api/models", timeout=5)
            if response.status_code == 200:
                data = response.json()
                current = data.get("current_model")
                models = data.get("models", [])
                
                # Update status label
                if current:
                    name = os.path.basename(current)
                    self.model_status.set_text(f"Loaded: {name}")
                    self.model_status.get_style_context().remove_class("model-inactive")
                    self.model_status.get_style_context().add_class("model-active")
                else:
                    self.model_status.set_text("No model loaded")
                    self.model_status.get_style_context().remove_class("model-active")
                    self.model_status.get_style_context().add_class("model-inactive")
                
                # Update combo box
                self.model_combo.disconnect_by_func(self.on_model_combo_changed)
                self.model_combo.remove_all()
                self.model_combo.append_text("Select model...")
                for m in models:
                    self.model_combo.append_text(m["name"])
                self.model_combo.set_active(0)
                self.model_combo.connect("changed", self.on_model_combo_changed)
        except Exception:
            pass
    
    def on_model_combo_changed(self, combo):
        """Handle model selection from combo box."""
        text = combo.get_active_text()
        if not text or text == "Select model...":
            return
        
        # Find model path
        try:
            response = requests.get(f"{self.base_url}/api/models", timeout=5)
            if response.status_code == 200:
                models = response.json().get("models", [])
                for m in models:
                    if m["name"] == text:
                        self._load_model_by_path(m["path"])
                        break
        except Exception as e:
            self.status_bar.set_text(f"Error: {e}")
    
    def _load_model_by_path(self, path):
        """Load model by path."""
        self.model_status.set_text("Loading...")
        self.status_bar.set_text(f"Loading model: {os.path.basename(path)}...")
        
        thread = threading.Thread(
            target=self._load_model_thread,
            args=(path,),
            daemon=True
        )
        thread.start()
    
    def _load_model_thread(self, path):
        """Load model in background."""
        try:
            response = requests.post(
                f"{self.base_url}/api/model/load",
                json={"path": path},
                timeout=300
            )
            if response.status_code == 200:
                GLib.idle_add(self._on_model_loaded, path)
            else:
                GLib.idle_add(self._show_status, "Failed to load model")
        except Exception as e:
            GLib.idle_add(self._show_status, f"Error: {e}")
    
    def _on_model_loaded(self, path):
        """Handle model loaded."""
        self._refresh_model_info()
        self.status_bar.set_text(f"Model loaded: {os.path.basename(path)}")
        return False
    
    def on_load_model(self, button):
        """Open file chooser to load a model."""
        dialog = Gtk.FileChooserDialog(
            title="Select GGUF Model",
            parent=self.window,
            action=Gtk.FileChooserAction.OPEN
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_OPEN, Gtk.ResponseType.OK
        )
        
        filter_gguf = Gtk.FileFilter()
        filter_gguf.set_name("GGUF Models")
        filter_gguf.add_pattern("*.gguf")
        dialog.add_filter(filter_gguf)
        
        model_dir = os.path.expanduser("~/.local/share/ocws/models")
        if os.path.isdir(model_dir):
            dialog.set_current_folder(model_dir)
        
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            filepath = dialog.get_filename()
            self._load_model_by_path(filepath)
        
        dialog.destroy()
    
    def on_eject_model(self, button):
        """Eject the current model."""
        try:
            response = requests.post(f"{self.base_url}/api/model/eject", timeout=10)
            if response.status_code == 200:
                self._refresh_model_info()
                self.status_bar.set_text("Model ejected")
        except Exception as e:
            self.status_bar.set_text(f"Eject failed: {e}")
    
    def on_browse_models(self, button):
        """Browse and switch between downloaded models."""
        dialog = Gtk.Dialog(
            title="Switch Model",
            parent=self.window,
            flags=Gtk.DialogFlags.MODAL,
            buttons=(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        )
        dialog.set_default_size(500, 400)
        
        content = dialog.get_content_area()
        
        try:
            response = requests.get(f"{self.base_url}/api/models", timeout=5)
            if response.status_code == 200:
                data = response.json()
                models = data.get("models", [])
                current = data.get("current_model")
                
                if not models:
                    label = Gtk.Label(label="No models found. Download a model first.")
                    content.pack_start(label, True, True, 12)
                else:
                    listbox = Gtk.ListBox()
                    listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
                    
                    for m in models:
                        row = Gtk.ListBoxRow()
                        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
                        box.set_margin_start(12)
                        box.set_margin_end(12)
                        box.set_margin_top(8)
                        box.set_margin_bottom(8)
                        
                        # Model name and info
                        info_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
                        
                        name_label = Gtk.Label(label=m["name"])
                        name_label.set_xalign(0)
                        name_label.set_ellipsize(3)
                        info_box.pack_start(name_label, False, False, 0)
                        
                        size_label = Gtk.Label(label=m.get("size_human", ""))
                        size_label.set_xalign(0)
                        size_label.get_style_context().add_class("dim-label")
                        info_box.pack_start(size_label, False, False, 0)
                        
                        box.pack_start(info_box, True, True, 0)
                        
                        # Status / action
                        if m["path"] == current:
                            status_label = Gtk.Label(label="● Active")
                            status_label.get_style_context().add_class("model-active")
                            box.pack_end(status_label, False, False, 0)
                        else:
                            switch_btn = Gtk.Button(label="Switch")
                            switch_btn.connect("clicked", self._on_switch_model, m["path"], dialog)
                            box.pack_end(switch_btn, False, False, 0)
                        
                        row.add(box)
                        listbox.add(row)
                    
                    content.pack_start(listbox, True, True, 0)
        except Exception:
            label = Gtk.Label(label="Could not connect to server")
            content.pack_start(label, True, True, 12)
        
        dialog.show_all()
        dialog.run()
        dialog.destroy()
    
    def _on_switch_model(self, button, path, dialog):
        """Switch to a different model."""
        button.set_sensitive(False)
        button.set_label("Loading...")
        
        thread = threading.Thread(
            target=self._switch_model_thread,
            args=(path,),
            daemon=True
        )
        thread.start()
        dialog.destroy()
    
    def _switch_model_thread(self, path):
        """Switch model in background."""
        try:
            response = requests.post(
                f"{self.base_url}/api/model/switch",
                json={"path": path},
                timeout=300
            )
            if response.status_code == 200:
                GLib.idle_add(self._on_model_switched, path)
        except Exception as e:
            GLib.idle_add(self._show_status, f"Switch failed: {e}")
    
    def _on_model_switched(self, path):
        """Handle model switched."""
        self._refresh_model_info()
        self.status_bar.set_text(f"Switched to: {os.path.basename(path)}")
        return False
    
    def on_download_model(self, button):
        """Download a model from recommendations."""
        dialog = Gtk.Dialog(
            title="Download Model",
            parent=self.window,
            flags=Gtk.DialogFlags.MODAL,
            buttons=(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        )
        dialog.set_default_size(600, 500)
        
        content = dialog.get_content_area()
        
        try:
            response = requests.get(f"{self.base_url}/api/models", timeout=5)
            if response.status_code == 200:
                data = response.json()
                recommendations = data.get("recommendations", {})
                
                notebook = Gtk.Notebook()
                
                for category, models in recommendations.items():
                    if not models:
                        continue
                    
                    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
                    box.set_margin_start(12)
                    box.set_margin_end(12)
                    box.set_margin_top(12)
                    
                    for model in models:
                        model_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
                        
                        name_label = Gtk.Label(label=f"<b>{model['name']}</b>")
                        name_label.set_use_markup(True)
                        name_label.set_xalign(0)
                        model_box.pack_start(name_label, False, False, 0)
                        
                        info = f"Size: {model['size']} | RAM: {model['ram']}"
                        info_label = Gtk.Label(label=info)
                        info_label.set_xalign(0)
                        model_box.pack_start(info_label, False, False, 0)
                        
                        purpose_label = Gtk.Label(label=f"Best for: {model['best_for']}")
                        purpose_label.set_xalign(0)
                        purpose_label.get_style_context().add_class("dim-label")
                        model_box.pack_start(purpose_label, False, False, 0)
                        
                        dl_btn = Gtk.Button(label=f"Download {model['name']}")
                        dl_btn.connect("clicked", self._on_download_clicked, model, dialog)
                        model_box.pack_start(dl_btn, False, False, 4)
                        
                        sep = Gtk.Separator()
                        model_box.pack_start(sep, False, False, 4)
                        
                        box.pack_start(model_box, False, False, 0)
                    
                    scroll = Gtk.ScrolledWindow()
                    scroll.add(box)
                    notebook.append_page(scroll, Gtk.Label(label=category.capitalize()))
                
                content.pack_start(notebook, True, True, 0)
        except Exception:
            label = Gtk.Label(label="Could not fetch recommendations")
            content.pack_start(label, True, True, 12)
        
        dialog.show_all()
        dialog.run()
        dialog.destroy()
    
    def _on_download_clicked(self, button, model, dialog):
        """Start downloading a model."""
        button.set_sensitive(False)
        button.set_label("Downloading...")
        
        thread = threading.Thread(
            target=self._download_model_thread,
            args=(model, button),
            daemon=True
        )
        thread.start()
    
    def _download_model_thread(self, model, button):
        """Download model in background."""
        try:
            response = requests.post(
                f"{self.base_url}/api/model/download",
                json={"url": model["url"], "filename": model["filename"]},
                timeout=10
            )
            if response.status_code == 200:
                GLib.idle_add(self._show_status, f"Downloading {model['name']}...")
        except Exception as e:
            GLib.idle_add(self._show_status, f"Download error: {e}")
    
    # ============================================================
    # Server Controls
    # ============================================================
    
    def on_start_server(self, button):
        """Start the server (signal)."""
        self.status_bar.set_text("Server start requested...")
        # Server is managed externally or by main.py
        self._refresh_all()
    
    def on_stop_server(self, button):
        """Stop the server."""
        dialog = Gtk.MessageDialog(
            parent=self.window,
            flags=Gtk.DialogFlags.MODAL,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text="Stop the server?"
        )
        
        response = dialog.run()
        dialog.destroy()
        
        if response == Gtk.ResponseType.YES:
            try:
                # Try to stop via API (if server has a stop endpoint)
                requests.post(f"{self.base_url}/api/stop", timeout=2)
            except Exception:
                pass
            self.status_bar.set_text("Server stopped")
    
    def on_refresh_status(self, button):
        """Refresh all status info."""
        self._refresh_all()
    
    def _refresh_all(self):
        """Refresh all UI elements."""
        self._refresh_sessions_list()
        self._refresh_model_info()
        self._check_server_status()
        return False
    
    def _check_server_status(self):
        """Check if server is running."""
        try:
            response = requests.get(f"{self.base_url}/api/health", timeout=2)
            if response.status_code == 200:
                self.server_status.get_style_context().remove_class("model-inactive")
                self.server_status.get_style_context().add_class("model-active")
                self.server_status.set_tooltip_text("Server running")
        except Exception:
            self.server_status.get_style_context().remove_class("model-active")
            self.server_status.get_style_context().add_class("model-inactive")
            self.server_status.set_tooltip_text("Server not running")
    
    # ============================================================
    # Chat
    # ============================================================
    
    def add_message(self, role, content):
        """Add a message to the chat display."""
        msg_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        
        if role == "user":
            msg_box.get_style_context().add_class("message-user")
        elif role == "assistant":
            msg_box.get_style_context().add_class("message-assistant")
        else:
            msg_box.get_style_context().add_class("message-system")
        
        label = Gtk.Label(label=content)
        label.set_xalign(0)
        label.set_line_wrap(True)
        label.set_selectable(True)
        label.set_max_width_chars(80)
        msg_box.pack_start(label, False, False, 0)
        
        self.chat_display.pack_start(msg_box, False, False, 0)
        self.chat_display.show_all()
        
        adjustment = self.chat_scroll.get_vadjustment()
        adjustment.set_value(adjustment.get_upper())
    
    def get_input_text(self):
        """Get text from input entry."""
        buf = self.input_entry.get_buffer()
        start = buf.get_start_iter()
        end = buf.get_end_iter()
        return buf.get_text(start, end, True).strip()
    
    def clear_input(self):
        """Clear input entry."""
        self.input_entry.get_buffer().set_text("")
    
    def on_entry_keypress(self, widget, event):
        """Handle keypress in input entry."""
        if event.keyval == 65293:  # Enter
            if event.state & Gdk.ModifierType.SHIFT_MASK:
                return False
            else:
                self.on_send_message(widget)
                return True
        return False
    
    def on_send_message(self, button):
        """Send a chat message."""
        message = self.get_input_text()
        if not message:
            return
        
        self.clear_input()
        self.add_message("user", message)
        
        self.input_entry.set_sensitive(False)
        self.status_bar.set_text("Thinking...")
        
        thread = threading.Thread(
            target=self._send_message_thread,
            args=(message,),
            daemon=True
        )
        thread.start()
    
    def _send_message_thread(self, message):
        """Send message to server."""
        try:
            buf = self.system_prompt.get_buffer()
            start = buf.get_start_iter()
            end = buf.get_end_iter()
            system_prompt = buf.get_text(start, end, True).strip()
            
            response = requests.post(
                f"{self.base_url}/api/chat",
                json={
                    "message": message,
                    "session_id": self.session_id,
                    "system_prompt": system_prompt,
                },
                timeout=120
            )
            
            if response.status_code == 200:
                data = response.json()
                assistant_message = data.get("response", "No response")
                self.session_id = data.get("session_id", self.session_id)
            else:
                assistant_message = f"Error: {response.status_code}"
                
        except requests.ConnectionError:
            assistant_message = "Error: Could not connect to server"
        except Exception as e:
            assistant_message = f"Error: {str(e)}"
        
        GLib.idle_add(self._show_response, assistant_message)
    
    def _show_response(self, message):
        """Show assistant response."""
        self.add_message("assistant", message)
        self.input_entry.set_sensitive(True)
        self.status_bar.set_text("Ready")
        self.input_entry.grab_focus()
        self._refresh_sessions_list()
        return False
    
    # ============================================================
    # OCR
    # ============================================================
    
    def on_ocr_region(self, button):
        """Capture screen region and OCR it."""
        self.status_bar.set_text("Select region to OCR...")
        
        thread = threading.Thread(
            target=self._ocr_region_thread,
            daemon=True
        )
        thread.start()
    
    def _ocr_region_thread(self):
        """OCR screen region."""
        try:
            response = requests.post(f"{self.base_url}/api/ocr/region", timeout=30)
            if response.status_code == 200:
                text = response.json().get("text", "")
                if text:
                    GLib.idle_add(self._insert_ocr_text, text)
                else:
                    GLib.idle_add(self._show_status, "No text detected")
            else:
                GLib.idle_add(self._show_status, "OCR failed")
        except Exception as e:
            GLib.idle_add(self._show_status, f"OCR error: {e}")
    
    def _insert_ocr_text(self, text):
        """Insert OCR text into input."""
        buf = self.input_entry.get_buffer()
        buf.set_text(text)
        self.status_bar.set_text("OCR complete — text inserted")
        return False
    
    def _show_status(self, text):
        """Show status message."""
        self.status_bar.set_text(text)
        return False
    
    # ============================================================
    # Run
    # ============================================================
    
    def run(self):
        """Run the application."""
        self.app.run(None)
