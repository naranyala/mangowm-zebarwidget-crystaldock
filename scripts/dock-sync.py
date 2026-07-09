#!/usr/bin/env python3
"""dock-sync.py — 4-Way Bi-Directional Dock Pin Synchronizer

Keeps pinned apps in sync across DMS, Noctalia, Crystal-dock, and SFWBar.
Also maintains a persistent backup state file for crash recovery.

Usage:
  dock-sync.py              Start sync daemon
  dock-sync.py --once       Sync once and exit
  dock-sync.py --restore    Restore from backup state
  dock-sync.py --backup     Save current state to backup
  dock-sync.py --status     Show current state from all docks
"""

import os
import sys
import time
import subprocess
import ast
import re
import json
import fcntl

HOME = os.environ.get("HOME", "/tmp")

# Paths
NOCTALIA_CONFIG = os.path.join(HOME, ".config/noctalia/config.toml")
OCWS_SETTINGS = os.path.join(HOME, ".config/ocws/settings.config")
SFWBAR_WIDGET = os.path.join(HOME, ".config/ocws/widgets/core/dock-apps.widget")
CRYSTAL_CONFIG = os.path.join(HOME, ".config/crystal-dock/panel_1.conf")
GSETTINGS_CMD = ["gsettings", "get", "org.gnome.shell", "favorite-apps"]

# Persistent state
STATE_DIR = os.path.join(HOME, ".local/share/ocws")
STATE_FILE = os.path.join(STATE_DIR, "dock_apps")
BACKUP_FILE = os.path.join(STATE_DIR, "dock_apps.backup")

# Items that are structural in docks rather than actual apps
STRUCTURAL_APPS = {"show-desktop", "separator", "lxqt-lockscreen", "lxqt-logout"}

# Lock file to prevent concurrent sync
LOCK_FILE = os.path.join(STATE_DIR, "dock-sync.lock")


def clean_apps(apps):
    """Clean the app list of .desktop extensions and structural pseudo-apps."""
    cleaned = []
    for a in apps:
        base = a.replace('.desktop', '').strip()
        if base and base not in STRUCTURAL_APPS:
            cleaned.append(base)
    return cleaned


def log(msg):
    print(f"[Dock Sync] {msg}", flush=True)


# === File Locking ===

class FileLock:
    """Simple file-based lock to prevent concurrent sync."""
    def __init__(self, path):
        self.path = path
        self.fd = None

    def acquire(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.fd = open(self.path, 'w')
        try:
            fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.fd.write(str(os.getpid()))
            self.fd.flush()
            return True
        except (IOError, OSError):
            self.fd.close()
            self.fd = None
            return False

    def release(self):
        if self.fd:
            fcntl.flock(self.fd, fcntl.LOCK_UN)
            self.fd.close()
            self.fd = None
            try:
                os.unlink(self.path)
            except OSError:
                pass


# === DMS (GNOME gsettings) ===

def get_dms():
    try:
        output = subprocess.check_output(GSETTINGS_CMD, text=True, timeout=5).strip()
        apps = ast.literal_eval(output)
        return clean_apps(apps)
    except Exception as e:
        log(f"Error reading DMS: {e}")
        return None


def set_dms(apps):
    desktop_apps = [f"{a}.desktop" if not a.endswith('.desktop') else a for a in apps]
    val = str(desktop_apps).replace("'", '"')
    subprocess.run(["gsettings", "set", "org.gnome.shell", "favorite-apps", val],
                   timeout=5, capture_output=True)


# === Noctalia ===

def get_noctalia():
    if not os.path.exists(NOCTALIA_CONFIG):
        return None
    try:
        with open(NOCTALIA_CONFIG, "r", encoding="utf-8") as f:
            content = f.read()
        match = re.search(r'^\s*pinned\s*=\s*(\[[^\]]*\])', content, re.MULTILINE)
        if match:
            return clean_apps(ast.literal_eval(match.group(1)))
    except Exception as e:
        log(f"Error reading Noctalia: {e}")
    return None


def set_noctalia(apps):
    if not os.path.exists(NOCTALIA_CONFIG):
        return
    with open(NOCTALIA_CONFIG, "r", encoding="utf-8") as f:
        content = f.read()
    val = str(apps).replace("'", '"')
    if re.search(r'^\s*pinned\s*=', content, re.MULTILINE):
        new_content = re.sub(r'^\s*pinned\s*=.*$', f'pinned = {val}', content, flags=re.MULTILINE)
    else:
        new_content = re.sub(r'^\[dock\]', f'[dock]\npinned = {val}', content, flags=re.MULTILINE)
    with open(NOCTALIA_CONFIG, "w", encoding="utf-8") as f:
        f.write(new_content)


# === Crystal Dock ===

def get_crystaldock():
    if not os.path.exists(CRYSTAL_CONFIG):
        return None
    try:
        with open(CRYSTAL_CONFIG, "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("launchers="):
                    val = line.split("=", 1)[1].strip().strip('"')
                    apps = val.split(";")
                    return clean_apps(apps)
    except Exception as e:
        log(f"Error reading Crystal-dock: {e}")
    return None


def set_crystaldock(apps):
    if not os.path.exists(CRYSTAL_CONFIG):
        return
    with open(CRYSTAL_CONFIG, "r", encoding="utf-8") as f:
        content = f.read()
    new_launchers = "show-desktop;" + ";".join(apps) + ";separator;lxqt-lockscreen;lxqt-logout;separator"
    new_content = re.sub(r'^launchers=.*$', f'launchers="{new_launchers}"', content, flags=re.MULTILINE)
    with open(CRYSTAL_CONFIG, "w", encoding="utf-8") as f:
        f.write(new_content)


# === SFWBar (OCWS) ===

def get_sfwbar():
    if not os.path.exists(OCWS_SETTINGS):
        return None
    try:
        with open(OCWS_SETTINGS, "r", encoding="utf-8") as f:
            for line in f:
                match = re.search(r'Set\s+OCWS_DOCK_APPS\s*=\s*"([^"]*)"', line)
                if match:
                    apps = match.group(1).split(",")
                    return clean_apps(apps)
    except Exception as e:
        log(f"Error reading SFWBar: {e}")
    return None


def render_sfwbar_widget(apps):
    lines = ["#Api2", "# dock-apps.widget — Auto-generated by dock-sync.py\n"]
    for app in apps:
        app_clean = app.strip()
        if not app_clean:
            continue
        tooltip = app_clean.capitalize().replace('-', ' ')
        block = f"""# --- {tooltip} ---
button {{
  style = "dock_app"
  tooltip = "{tooltip}"
  action = Exec("{app_clean}")
  image {{
    icon = "{app_clean}"
    css = "* {{ min-width: 32px; min-height: 32px; }}"
  }}
}}
"""
        lines.append(block)
    lines.append("""# --- Separator ---
label {
  style = "dock_sep"
  value = "|"
}

# --- Settings ---
button {
  style = "dock_app"
  tooltip = "OCWS Settings"
  action = Exec("ocws-settings")
  image {
    icon = "preferences-desktop-symbolic"
    css = "* { min-width: 32px; min-height: 32px; }"
  }
}""")
    if os.path.exists(os.path.dirname(SFWBAR_WIDGET)):
        with open(SFWBAR_WIDGET, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))


def set_sfwbar(apps):
    if not os.path.exists(OCWS_SETTINGS):
        return
    with open(OCWS_SETTINGS, "r", encoding="utf-8") as f:
        content = f.read()
    val = ",".join(apps)
    new_content = re.sub(r'(Set\s+OCWS_DOCK_APPS\s*=\s*)"[^"]*"', rf'\g<1>"{val}"', content)
    with open(OCWS_SETTINGS, "w", encoding="utf-8") as f:
        f.write(new_content)
    render_sfwbar_widget(apps)


# === State Management ===

GETTERS = [get_dms, get_noctalia, get_crystaldock, get_sfwbar]
SETTERS = [set_dms, set_noctalia, set_crystaldock, set_sfwbar]
DOCK_NAMES = ["DMS", "Noctalia", "Crystal-dock", "SFWBar"]


def read_state_from_any_dock():
    """Read pinned apps from whichever dock was most recently modified."""
    dconf_path = os.path.join(HOME, ".config/dconf/user")
    mtimes = {
        0: get_mtime(dconf_path),
        1: get_mtime(NOCTALIA_CONFIG),
        2: get_mtime(CRYSTAL_CONFIG),
        3: get_mtime(OCWS_SETTINGS)
    }
    
    newest_idx = max(mtimes, key=mtimes.get)
    apps = GETTERS[newest_idx]()
    if apps is not None:
        log(f"Determined {DOCK_NAMES[newest_idx]} as newest state source")
        return apps

    # Fallback to the original priority order if the newest one is empty/None
    for i, getter in enumerate(GETTERS):
        apps = getter()
        if apps is not None:
            return apps
    return []


def save_backup(apps):
    """Save apps to persistent backup file."""
    os.makedirs(STATE_DIR, exist_ok=True)
    state = {
        "apps": apps,
        "count": len(apps),
        "timestamp": time.time()
    }
    # Atomic write
    tmp = BACKUP_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, BACKUP_FILE)


def load_backup():
    """Load apps from backup file."""
    if not os.path.exists(BACKUP_FILE):
        return []
    try:
        with open(BACKUP_FILE, "r", encoding="utf-8") as f:
            state = json.load(f)
        return state.get("apps", [])
    except Exception:
        return []


def sync_all(apps, last_apps=None):
    """Push apps to all dock implementations and track changes."""
    if last_apps is not None:
        added = [a for a in apps if a not in last_apps]
        removed = [a for a in last_apps if a not in apps]
        if added:
            log(f"Added: {added}")
        if removed:
            log(f"Removed: {removed}")

    for setter in SETTERS:
        try:
            setter(apps)
        except Exception as e:
            log(f"Error setting dock: {e}")
    save_backup(apps)


def restore_from_backup():
    """Restore apps from backup to all running docks."""
    apps = load_backup()
    if not apps:
        log("No backup state found")
        return False
    log(f"Restoring {len(apps)} apps from backup: {apps}")
    sync_all(apps)
    return True


def show_status():
    """Show current state from all docks."""
    print("=== Dock Pin Status ===")
    print()
    for name, getter in zip(DOCK_NAMES, GETTERS):
        apps = getter()
        if apps is not None:
            print(f"{name}: {len(apps)} apps")
            print(f"  {apps}")
        else:
            print(f"{name}: (not available)")
        print()

    backup = load_backup()
    if backup:
        print(f"Backup: {len(backup)} apps")
        print(f"  {backup}")
    else:
        print("Backup: (none)")
    print()

    # Show state file
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, "r") as f:
            print(f"State file: {f.read().strip()}")


# === Daemon Mode ===

def run_daemon():
    """Run the sync daemon with file locking."""
    lock = FileLock(LOCK_FILE)
    if not lock.acquire():
        log("Another sync daemon is already running")
        sys.exit(1)

    try:
        log("4-Way Bi-Directional Sync Daemon Started...")

        # Read initial state from any available dock
        apps = read_state_from_any_dock()
        if not apps:
            # Fall back to backup
            apps = load_backup()
            if apps:
                log(f"No active dock found, restoring {len(apps)} apps from backup")
                sync_all(apps)
            else:
                log("No dock apps found and no backup available")
                apps = []
        else:
            log(f"Initial state from active dock: {len(apps)} apps")
            sync_all(apps)

        last_apps = list(apps)
        last_mtimes = {
            "noctalia": get_mtime(NOCTALIA_CONFIG),
            "crystal": get_mtime(CRYSTAL_CONFIG),
            "sfwbar": get_mtime(OCWS_SETTINGS)
        }

        log("Listening for changes across all docks...")

        while True:
            time.sleep(1.5)

            # Check DMS (via gsettings, no file to watch)
            dms_apps = get_dms()
            if dms_apps is not None and dms_apps != last_apps:
                log(f"DMS changed: {len(dms_apps)} apps")
                sync_all(dms_apps, last_apps)
                last_apps = dms_apps
                last_mtimes = refresh_mtimes()
                continue

            # Check Noctalia
            m_noct = get_mtime(NOCTALIA_CONFIG)
            if m_noct > last_mtimes["noctalia"]:
                last_mtimes["noctalia"] = m_noct
                n_apps = get_noctalia()
                if n_apps is not None and n_apps != last_apps:
                    log(f"Noctalia changed: {len(n_apps)} apps")
                    sync_all(n_apps, last_apps)
                    last_apps = n_apps
                    last_mtimes = refresh_mtimes()
                    continue

            # Check Crystal
            m_crys = get_mtime(CRYSTAL_CONFIG)
            if m_crys > last_mtimes["crystal"]:
                last_mtimes["crystal"] = m_crys
                c_apps = get_crystaldock()
                if c_apps is not None and c_apps != last_apps:
                    log(f"Crystal-dock changed: {len(c_apps)} apps")
                    sync_all(c_apps, last_apps)
                    last_apps = c_apps
                    last_mtimes = refresh_mtimes()
                    continue

            # Check SFWBar
            m_sfw = get_mtime(OCWS_SETTINGS)
            if m_sfw > last_mtimes["sfwbar"]:
                last_mtimes["sfwbar"] = m_sfw
                s_apps = get_sfwbar()
                if s_apps is not None and s_apps != last_apps:
                    log(f"SFWBar changed: {len(s_apps)} apps")
                    sync_all(s_apps, last_apps)
                    last_apps = s_apps
                    last_mtimes = refresh_mtimes()
                    continue

    except KeyboardInterrupt:
        log("Stopped.")
    finally:
        lock.release()


def get_mtime(path):
    return os.path.getmtime(path) if os.path.exists(path) else 0


def refresh_mtimes():
    return {
        "noctalia": get_mtime(NOCTALIA_CONFIG),
        "crystal": get_mtime(CRYSTAL_CONFIG),
        "sfwbar": get_mtime(OCWS_SETTINGS)
    }


# === Main ===

if __name__ == "__main__":
    os.makedirs(STATE_DIR, exist_ok=True)

    if "--restore" in sys.argv:
        restore_from_backup()
    elif "--backup" in sys.argv:
        apps = read_state_from_any_dock()
        if apps:
            save_backup(apps)
            log(f"Saved backup: {len(apps)} apps")
        else:
            log("No dock apps found to backup")
    elif "--status" in sys.argv:
        show_status()
    elif "--once" in sys.argv:
        apps = read_state_from_any_dock()
        if apps:
            sync_all(apps)
            log(f"Synced {len(apps)} apps")
        else:
            restore_from_backup()
    else:
        run_daemon()
