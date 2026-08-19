# Android Phone Linux Server Setup

Turns one or more old Android phones into Termux + proot-distro Debian
"servers," managed with Ansible from a laptop. GitHub SSH keys for
**johanbrandhorst** are used for admin access throughout.

**Devices involved:**
- **Control device**: your laptop — runs Ansible, initiates every remote step.
- **Target device(s)**: one or more Android phones (e.g. a Pixel 2 XL,
  a Pixel 3a) — assumed freshly factory reset.

**Files referenced below** (all live on the laptop except where a transfer
step says otherwise): `termux-bootstrap.sh`, `termux-bootstrap.yml`,
`proot-bootstrap.yml`, `termux-data-setup.yml`, `termux-auto-upgrade.yml`.

Repeat Part 1 and Part 3 once per phone. Part 2 runs once per phone too,
but from the laptop, so no physical repetition is needed — just re-target
each command at the next phone's IP.

---

## Part 1 — On each phone

### 1.1 Install Termux
- Do **not** use the Play Store version (outdated/unmaintained).
- Install via F-Droid (`f-droid.org` → install F-Droid → search Termux), or
  download the APK directly from `github.com/termux/termux-app/releases`.

### 1.2 Transfer `termux-bootstrap.sh` onto the phone
Termux has no SSH access yet at this point, so this transfer has to use
something other than `scp`. Pick whichever is easiest for you:

- **USB + adb** (if you have Android platform-tools / USB debugging set up):
  ```bash
  adb push termux-bootstrap.sh /sdcard/Download/
  ```
  Then in Termux: `cp /sdcard/Download/termux-bootstrap.sh ~/`
- **Cloud storage / email**: upload the file from the laptop, download it
  to the phone through any app, then move it into Termux's storage the
  same way as above.
- **Nearby Share / Bluetooth**: send the file directly from laptop to
  phone, then move it into Termux's storage.

### 1.3 Run the bootstrap script
```bash
cd ~
bash termux-bootstrap.sh
```
This installs proot-distro, Debian, and openssh; starts sshd; and prompts
you twice — once for the Android storage-access permission, once to set a
temporary SSH password. At the end it prints the phone's username and IP
address — **note these down**, you'll need them for Part 2. It also
reminds you of two manual steps (battery optimization, Termux:Boot) that
can't be scripted.

At this point, stop and switch to Part 2 on the laptop for this phone.
Repeat Parts 1.1–1.3 now for any additional phones, or come back to them
later — order doesn't matter, each phone is independent.

---

## Part 2 — On the laptop (control device)

Everything here runs from the laptop's terminal. Repeat the whole part
once per phone, substituting that phone's IP and username from step 1.3.

### 2.1 Install Ansible (once, not per phone)
```bash
# macOS
brew install ansible
# Debian/Ubuntu
sudo apt install ansible
# or via pip
pip install ansible --user
```
```bash
ansible-galaxy collection install ansible.posix
```

### 2.2 Get the playbook files onto the laptop (once, not per phone)
Save `termux-bootstrap.yml`, `proot-bootstrap.yml`, `termux-data-setup.yml`,
and `termux-auto-upgrade.yml` into a working directory, e.g. `~/phone-setup/`.

### 2.3 Secure Termux SSH access
Uses the temporary password from step 1.3. This is the only step that
needs `-k` — it's the last time that password is used, since the
playbook authorizes your GitHub key and disables password auth by the
time it finishes:
```bash
cd ~/phone-setup
ansible-playbook -i "<phone-ip>," -u <username> -k -e ansible_port=8022 \
  termux-bootstrap.yml
```
If a later step still prompts for a password instead of using your key,
check that the matching private key is loaded (`ssh-add -l`) and that
the public half is listed at `https://github.com/johanbrandhorst.keys`.

### 2.4 Set up persistent data storage
Now that step 2.3 has authorized your GitHub key and disabled password
auth, drop `-k` — Ansible connects with your SSH key from here on:
```bash
ansible-playbook -i "<phone-ip>," -u <username> -e ansible_port=8022 \
  termux-data-setup.yml
```
This creates `~/storage/shared/phone-data` on the phone (outside the
container) and login/sshd wrapper scripts that bind-mount it into Debian
at `/data`.

### 2.5 Schedule weekly in-place security updates
```bash
ansible-playbook -i "<phone-ip>," -u <username> -e ansible_port=8022 \
  termux-auto-upgrade.yml -e ntfy_topic=<your-ntfy-topic>
```
Generate a hard-to-guess topic name if you don't have one yet:
`openssl rand -hex 8`.
Defaults to Sunday 3am, posting results to `ntfy.sh/<your-ntfy-topic>`.
Override with `-e cron_schedule="min hour * * weekday"` and
`-e ntfy_server=https://your-instance` if self-hosting ntfy.

### 2.6 Transfer `proot-bootstrap.yml` onto the phone
Unlike the playbooks above, this one runs locally *inside* the proot
Debian container (Part 3), not from the laptop over SSH — so it needs to
physically land on the phone first. Now that SSH and the persistent data
directory both exist, `scp` it straight into `/data/configs`, which is
bind-mounted into the container and survives container rebuilds:
```bash
scp -P 8022 proot-bootstrap.yml <username>@<phone-ip>:~/storage/shared/phone-data/configs/
```

---

## Part 3 — Back on each phone, once (bootstraps the container itself)

The proot Debian container isn't network-reachable until sshd is running
inside it, so this step runs locally on the phone, not from the laptop
over SSH.

### 3.1 Enter the container via the data-mount wrapper
```bash
~/proot-debian-login.sh
```
(Not a bare `proot-distro login debian` — that skips the `/data`
bind-mount set up in step 2.4.)

### 3.2 Install Ansible inside the container and run the bootstrap
The playbook is already sitting at `/data/configs/proot-bootstrap.yml`
from step 2.6:
```bash
apt update && apt install -y ansible sudo
cd /data/configs
ansible-playbook -c local -i localhost, proot-bootstrap.yml \
  -e target_user=johan -e ssh_port=8023 \
  -e config_repo=git@github.com:johanbrandhorst/phone-configs.git
```
Omit `-e config_repo=...` if you don't have a configs repo yet.

This creates user `johan` with GitHub-key SSH access and passwordless
sudo, and starts sshd inside the container on **port 8023** (Termux keeps
8022, so both are reachable side by side on the same phone IP).

### 3.3 Verify direct SSH access to the container
From the laptop:
```bash
ssh -p 8023 johan@<phone-ip>
```

---

## Result

Per phone, two independently reachable SSH endpoints on the same IP:

| Port | What it reaches       | Auth              |
|------|------------------------|-------------------|
| 8022 | Termux (Android layer) | GitHub SSH key    |
| 8023 | Debian (proot guest)   | GitHub SSH key    |

## Ongoing maintenance

- **Weekly** (automated): in-place `apt upgrade` inside the container,
  results pushed to ntfy — no action needed unless a run fails.
- **Monthly-ish** (manual): destroy and rebuild the container to catch
  base-image drift:
  ```bash
  proot-distro remove debian
  proot-distro install debian
  # then repeat Part 3 on that phone — proot-bootstrap.yml is still at
  # /data/configs, no re-transfer needed
  ```
  Data in `/data` (bind-mounted from `~/storage/shared/phone-data`)
  survives this untouched.
- **Kernel-level updates**: not covered by any of the above — old phones
  are typically past their Android update lifespan, so the underlying
  kernel is frozen. Acceptable for a LAN-only hobby server; a reason to
  consider postmarketOS instead if that ever changes.
