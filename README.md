# Pi Signage Setup

Interactive Chromium kiosk setup for Raspberry Pi OS Desktop (64-bit), using labwc/Wayland. Suitable for Raspberry Pi 5 and Compute Module 5 running that desktop environment.

## Install

From an SSH session or terminal on the Pi, as the normal desktop user:

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/cyberhuff/pi-signage-setup.git
cd pi-signage-setup
bash setup-signage.sh
```

On first installation, setup asks for your complete webpage URL. There is no default URL. It then installs dependencies, enables desktop automatic login, disables screen blanking, starts Chromium in kiosk mode, and hides the cursor after three idle seconds. Mouse movement temporarily reveals the cursor. Chromium restarts if it exits. Setup prompts to reboot when complete.

Run scripts as your normal desktop user, **without `sudo` before `bash`**. They request administrative privileges internally when needed. Use the same account for setup and subsequent changes. Raspberry Pi OS Desktop with `raspi-config`, labwc, and LightDM is required; these scripts do not install the OS or convert Ubuntu Server into a desktop.

## Change the webpage

```bash
cd ~/pi-signage-setup
bash set-signage-url.sh
```

Enter a complete HTTP or HTTPS URL when prompted. This updates the local configuration and restarts only the browser using the dedicated kiosk profile. If the kiosk is not running, the new URL is used on its next launch.

## Rotate the screen

```bash
cd ~/pi-signage-setup
bash set-signage-rotation.sh
```

Choose 90 or 270 for portrait, 180 for upside down, or 0 for landscape. The script saves the angle and attempts to apply it immediately, including when run over SSH. If the desktop cannot be reached, reboot to apply it. Rotation applies to all enabled displays.

## Update

```bash
cd ~/pi-signage-setup
git pull --ff-only && bash setup-signage.sh
```

Pulling alone downloads source changes. Rerun setup to install changes to the launcher and desktop configuration. Setup preserves the saved URL and existing rotation. After an update to the rotation script, rerun `bash set-signage-rotation.sh` to refresh its installed helper. Reboot when prompted to activate updated startup settings.

## Local configuration

The webpage URL is stored in `~/.config/signage/url`, outside the Git checkout. Rotation is stored in `~/.config/signage/rotation`. Browser data and the latest browser launch log are in `~/.local/share/signage/`. Setup configuration backups are stored in `~/.config/signage/backup-*`; change scripts retain prior settings in that same local configuration directory.

No deployment URL, organization name, device hostname, credentials, or browser profile is included in this repository. Keep local configuration, backups, and logs out of commits. The configured webpage URL is visible locally in the browser process arguments, so avoid putting secrets in URLs.

The scripts preserve unrelated labwc startup entries and XML settings. They replace their own launcher, startup entries, and `W-A-F12` cursor binding. Review any custom kiosk startup commands from other installations to avoid duplicate browsers. These scripts configure a dedicated display account with automatic login; they do not configure network connectivity, heating, fan control, or physical keyboard lockdown.

## Validation

Bash and embedded Python syntax, repeated startup configuration, URL validation, and preservation of unrelated desktop settings have been checked in an isolated environment. Actual display operation must be verified on the target Pi.
