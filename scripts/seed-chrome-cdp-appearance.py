import json, os, shutil, sys

normal = os.path.expanduser("~/.config/google-chrome")
# Override for build-time seed (path outside /opt so volume mounts cannot wipe it).
if len(sys.argv) > 1 and sys.argv[1].strip():
    cdp = sys.argv[1].strip()
else:
    cdp = os.environ.get("CHROME_CDP_USER_DATA_DIR", "/opt/google-chrome-cdp").strip() or "/opt/google-chrome-cdp"
n_pref_path = os.path.join(normal, "Default", "Preferences")
c_pref_path = os.path.join(cdp, "Default", "Preferences")
n_ls = os.path.join(normal, "Local State")
c_ls = os.path.join(cdp, "Local State")

# Fixed download path (on /opt so empty-volume remounts keep downloads on the persist disk).
DOWNLOAD_DIR = "/opt/downloads"

def load(p):
    if not os.path.isfile(p):
        return {}
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)

def save(p, data):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))

def deep_get(d, keys, default=None):
    cur = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur

def deep_set(d, keys, value):
    cur = d
    for k in keys[:-1]:
        nxt = cur.get(k)
        if not isinstance(nxt, dict):
            nxt = {}
            cur[k] = nxt
        cur = nxt
    cur[keys[-1]] = value

def deep_del(d, keys):
    cur = d
    for k in keys[:-1]:
        if not isinstance(cur, dict) or k not in cur:
            return
        cur = cur[k]
    if isinstance(cur, dict):
        cur.pop(keys[-1], None)

def pin_download_dir(pref):
    """Force Default download / save path to DOWNLOAD_DIR. Returns True if changed."""
    changed = False
    wanted = [
        (("download", "default_directory"), DOWNLOAD_DIR),
        (("download", "directory_upgrade"), True),
        (("savefile", "default_directory"), DOWNLOAD_DIR),
    ]
    for keys, value in wanted:
        if deep_get(pref, keys, default=Ellipsis) != value:
            deep_set(pref, keys, value)
            changed = True
    return changed

os.makedirs(os.path.join(cdp, "Default"), exist_ok=True)
os.makedirs(os.path.join(normal, "Default"), exist_ok=True)
os.makedirs(DOWNLOAD_DIR, exist_ok=True)

if not os.path.isfile(c_pref_path) and os.path.isfile(n_pref_path):
    shutil.copy2(n_pref_path, c_pref_path)
if not os.path.isfile(c_ls) and os.path.isfile(n_ls):
    shutil.copy2(n_ls, c_ls)

n_pref = load(n_pref_path)
c_pref = load(c_pref_path)
changed = False

APPEARANCE_PATHS = [
    ("bookmark_bar",),
    ("side_panel",),
    ("vertical_tabs",),
    ("browser", "show_home_button"),
    ("browser", "custom_chrome_frame"),
    ("intl", "selected_languages"),
    ("intl", "accept_languages"),
    ("webkit", "webprefs", "fonts"),
    ("autofill", "profile_enabled"),
]

for path_keys in APPEARANCE_PATHS:
    src = deep_get(n_pref, path_keys, default=Ellipsis)
    if src is Ellipsis:
        before = deep_get(c_pref, path_keys, default=Ellipsis)
        if before is not Ellipsis:
            deep_del(c_pref, path_keys)
            changed = True
    else:
        if deep_get(c_pref, path_keys, default=Ellipsis) != src:
            deep_set(c_pref, path_keys, src)
            changed = True

# Theme: mirror normal when it has an explicit theme; otherwise force Classic (0).
# On Linux, absent theme defaults to GTK and Chrome persists system_theme=1.
n_theme = deep_get(n_pref, ("extensions", "theme"), default=Ellipsis)
if n_theme is not Ellipsis:
    if deep_get(c_pref, ("extensions", "theme"), default=Ellipsis) != n_theme:
        deep_set(c_pref, ("extensions", "theme"), n_theme)
        changed = True
else:
    cur = deep_get(c_pref, ("extensions", "theme"), default=None)
    if not isinstance(cur, dict) or cur.get("system_theme") != 0:
        deep_set(c_pref, ("extensions", "theme"), {"system_theme": 0})
        changed = True

# Pin download directory on both profiles (normal UI + CDP).
n_dl = pin_download_dir(n_pref)
c_dl = pin_download_dir(c_pref)
changed = changed or c_dl

save(n_pref_path, n_pref)
save(c_pref_path, c_pref)
print(
    "seeded changed=%s theme=%s download_dir=%s normal_dl=%s cdp_dl=%s"
    % (
        changed,
        deep_get(c_pref, ("extensions", "theme")),
        DOWNLOAD_DIR,
        n_dl,
        c_dl,
    )
)
