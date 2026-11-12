#!/usr/bin/env bash
# Rotate the Wayland display; run as the normal kiosk user, including over SSH.
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo 'Run without sudo, as your kiosk user.'; exit 1; }
[[ -x "$HOME/.local/bin/signage-kiosk" ]] || { echo 'Run setup-signage.sh first.'; exit 1; }
echo '90 = portrait; 270 = opposite portrait; 180 = upside down; 0 = landscape.'
read -r -p 'Rotation [90]: ' angle
angle=${angle:-90}
case "$angle" in 0|90|180|270) ;; *) echo 'Choose 0, 90, 180, or 270.'; exit 1;; esac
if ! command -v wlr-randr >/dev/null; then sudo apt-get update; sudo apt-get install -y wlr-randr; fi
mkdir -p "$HOME/.config/signage" "$HOME/.config/labwc" "$HOME/.local/bin"
[[ ! -f "$HOME/.config/signage/rotation" ]] || cp -p "$HOME/.config/signage/rotation" "$HOME/.config/signage/rotation.previous"
printf '%s\n' "$angle" > "$HOME/.config/signage/rotation"
if [[ -f "$HOME/.local/bin/signage-rotate" ]]; then cp -p "$HOME/.local/bin/signage-rotate" "$HOME/.config/signage/signage-rotate.previous"; fi
cat > "$HOME/.local/bin/signage-rotate" <<'ROTATE'
#!/usr/bin/env python3
import json, subprocess, sys, time
from pathlib import Path
angle = (Path.home() / '.config/signage/rotation').read_text().strip()
if angle not in ('0', '90', '180', '270'): sys.exit('Invalid saved rotation.')
transform = 'normal' if angle == '0' else angle
for attempt in range(10):
    try:
        outputs = json.loads(subprocess.check_output(['wlr-randr', '--json'], stderr=subprocess.DEVNULL, text=True))
        enabled = [output for output in outputs if output.get('enabled')]
        if not enabled: raise RuntimeError('No active display')
        for output in enabled:
            subprocess.run(['wlr-randr', '--output', output['name'], '--transform', transform], check=True)
        sys.exit(0)
    except (subprocess.SubprocessError, OSError, ValueError, RuntimeError):
        time.sleep(1)
sys.exit('Could not apply rotation to an active Wayland display.')
ROTATE
chmod +x "$HOME/.local/bin/signage-rotate"
python3 <<'PY'
from pathlib import Path
import shutil
p = Path.home() / '.config/labwc/autostart'
if p.exists(): shutil.copy2(p, Path.home() / '.config/signage/autostart.before-rotation')
text = p.read_text() if p.exists() else ''
lines = [line for line in text.splitlines() if '.local/bin/signage-rotate' not in line]
p.write_text('\n'.join(lines).rstrip() + '\n(sleep 5; "$HOME/.local/bin/signage-rotate") &\n')
PY
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
    if [[ -S "$socket" ]]; then export WAYLAND_DISPLAY="${socket##*/}"; break; fi
  done
fi
if [[ -n "${WAYLAND_DISPLAY:-}" ]] && "$HOME/.local/bin/signage-rotate"; then
  echo "Applied ${angle} degrees and saved for future boots."
else
  echo "Saved ${angle} degrees. Reboot to apply it to the kiosk desktop."
fi
