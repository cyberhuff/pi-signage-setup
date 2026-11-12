#!/usr/bin/env bash
# Run as the same normal user who ran setup-signage.sh.
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo 'Run without sudo, as your kiosk user.'; exit 1; }
[[ -x "$HOME/.local/bin/signage-kiosk" ]] || { echo 'Run setup-signage.sh first.'; exit 1; }
read -r -p 'New signage URL (https://...): ' url
export SIGNAGE_NEW_URL="$url"
python3 <<'PY'
import os, sys
from pathlib import Path
from urllib.parse import urlsplit
url = os.environ['SIGNAGE_NEW_URL'].strip()
try:
    parsed = urlsplit(url)
    valid = parsed.scheme in ('http', 'https') and bool(parsed.hostname)
except ValueError:
    valid = False
if not valid or any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in url):
    sys.exit('Invalid URL. Use a complete http:// or https:// URL without spaces.')
folder = Path.home() / '.config/signage'
folder.mkdir(parents=True, exist_ok=True)
target = folder / 'url'
if target.exists(): (folder / 'url.previous').write_bytes(target.read_bytes())
temporary = folder / 'url.new'
temporary.write_text(url + '\n')
temporary.chmod(0o600)
temporary.replace(target)
PY
# Stop only the browser using this kiosk's dedicated profile. Its launcher restarts it.
python3 <<'PY'
import os, signal
from pathlib import Path
profile = ('--user-data-dir=' + str(Path.home() / '.local/share/signage/chromium')).encode()
count = 0
for process in Path('/proc').iterdir():
    if not process.name.isdigit(): continue
    try:
        if process.stat().st_uid != os.getuid(): continue
        args = (process / 'cmdline').read_bytes().split(b'\0')
        if profile in args and not any(arg.startswith(b'--type=') for arg in args):
            os.kill(int(process.name), signal.SIGTERM)
            count += 1
    except (OSError, ProcessLookupError): pass
print('URL saved. The kiosk will reopen within a few seconds.' if count else
      'URL saved. It will be used when the kiosk next starts; reboot if it is not running.')
PY
