#!/usr/bin/env bash
# Raspberry Pi OS Desktop (64-bit), labwc/Wayland. Run as the kiosk user.
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo 'Run as your normal kiosk user, without sudo.'; exit 1; }
command -v raspi-config >/dev/null || { echo 'This setup requires Raspberry Pi OS Desktop with raspi-config.'; exit 1; }
command -v labwc >/dev/null || { echo 'Install Raspberry Pi OS Desktop (labwc) first.'; exit 1; }
# Prompt only on first installation; keep runtime settings outside this checkout.
if [[ ! -s "$HOME/.config/signage/url" ]]; then
  read -r -p 'Initial signage URL (https://...): ' initial_url
  export SIGNAGE_INITIAL_URL="$initial_url"
  python3 <<'VALIDATE'
import os, sys
from urllib.parse import urlsplit
url = os.environ['SIGNAGE_INITIAL_URL']
try:
    parsed = urlsplit(url)
    valid = parsed.scheme in ('http', 'https') and bool(parsed.hostname)
except ValueError:
    valid = False
if not valid or any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in url):
    sys.exit('Enter a complete http:// or https:// URL without spaces.')
VALIDATE
fi
sudo -v
config="$HOME/.config/signage"
mkdir -p "$config" "$HOME/.config/labwc" "$HOME/.local/bin" "$HOME/.local/share/signage"
backup="$config/backup-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$backup"
for item in .config/labwc/autostart .config/labwc/rc.xml .config/signage/url .local/bin/signage-kiosk; do
  if [[ -f "$HOME/$item" ]]; then mkdir -p "$backup/$(dirname "$item")"; cp -p "$HOME/$item" "$backup/$item"; fi
done
sudo apt-get update
sudo apt-get install -y chromium wtype swayidle python3 util-linux lightdm
# Run blanking configuration before adding our cursor-hiding swayidle command.
sudo raspi-config nonint do_boot_behaviour B4
sudo raspi-config nonint do_blanking 1
sudo systemctl enable lightdm
if [[ ! -s "$config/url" ]]; then
  printf '%s\n' "${initial_url}" > "$config/url"
  chmod 600 "$config/url"
fi
cat > "$HOME/.local/bin/signage-kiosk" <<'KIOSK'
#!/usr/bin/env bash
set -u
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/signage-kiosk-$(id -u).lock"
flock -n 9 || exit 0
child=''
stop() { [[ -z "$child" ]] || kill "$child" 2>/dev/null || true; exit 0; }
trap stop TERM INT HUP
mkdir -p "$HOME/.local/share/signage"
while true; do
  url=$(head -n 1 "$HOME/.config/signage/url")
  chromium --ozone-platform=wayland \
    --user-data-dir="$HOME/.local/share/signage/chromium" \
    --kiosk --no-first-run --no-default-browser-check --noerrdialogs "$url" \
    > "$HOME/.local/share/signage/browser.log" 2>&1 &
  child=$!
  wait "$child" || true
  child=''
  sleep 3
done
KIOSK
chmod +x "$HOME/.local/bin/signage-kiosk"
python3 <<'PY'
import re, shutil
from pathlib import Path
import xml.etree.ElementTree as ET
home = Path.home()
folder = home / '.config/labwc'
rc = folder / 'rc.xml'
source = rc if rc.exists() else Path('/etc/xdg/labwc/rc.xml')
tree = ET.parse(source) if source.exists() else ET.ElementTree(ET.Element('labwc_config'))
root = tree.getroot()
namespace = root.tag.split('}')[0][1:] if root.tag.startswith('{') else ''
if namespace: ET.register_namespace('', namespace)
def tag(name): return '{' + namespace + '}' + name if namespace else name
keyboard = root.find(tag('keyboard'))
if keyboard is None: keyboard = ET.SubElement(root, tag('keyboard'))
for bind in list(keyboard):
    if bind.tag == tag('keybind') and bind.get('key') == 'W-A-F12': keyboard.remove(bind)
bind = ET.SubElement(keyboard, tag('keybind'), {'key': 'W-A-F12'})
ET.SubElement(bind, tag('action'), {'name': 'HideCursor'})
ET.indent(tree, space='  ')
tree.write(rc, encoding='UTF-8', xml_declaration=True)
autostart = folder / 'autostart'
if not autostart.exists():
    system = Path('/etc/xdg/labwc/autostart')
    if system.exists(): shutil.copy2(system, autostart)
text = autostart.read_text() if autostart.exists() else ''
text = re.sub(r'(?ms)^# BEGIN [A-Z]+ SIGNAGE\n.*?^# END [A-Z]+ SIGNAGE\n?', '', text)
# Migrate the commands supplied earlier, preserving rotation and unrelated startup items.
lines = [line for line in text.splitlines()
         if '.local/bin/signage-kiosk' not in line
         and line.strip() != '# signage-cursor-hide'
         and not ('swayidle' in line and 'wtype' in line and 'F12' in line)]
block = '''# BEGIN PI SIGNAGE
"$HOME/.local/bin/signage-kiosk" &
swayidle -w timeout 3 'wtype -M logo -M alt -P F12 -p F12 -m alt -m logo' &
# END PI SIGNAGE
'''
autostart.write_text('\n'.join(lines).rstrip() + '\n\n' + block)
PY
printf '\nSetup complete. URL: %s\nBackup: %s\n' "$(cat "$config/url")" "$backup"
echo 'Reboot to start the kiosk. Rotation is left unchanged.'
read -r -p 'Reboot now? [y/N] ' answer || answer=n
if [[ "$answer" =~ ^[Yy]$ ]]; then sudo reboot; fi
