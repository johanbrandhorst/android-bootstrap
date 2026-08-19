#!/data/data/com.termux/files/usr/bin/bash
# termux-bootstrap.sh
# Run this once inside Termux on a freshly installed phone. Sets up
# storage access, installs proot-distro + Debian + openssh, starts
# sshd, and prints what you need for the Ansible steps on the laptop.
#
# This is interactive in two places (both required, can't be scripted
# around): the storage permission prompt, and setting a temporary SSH
# password. Just follow the prompts as they appear.

set -e

echo "== Step 1/5: Storage access =="
echo "Accept the Android permission prompt that appears."
termux-setup-storage
sleep 2   # give the prompt a moment before continuing

echo ""
echo "== Step 2/5: Updating packages =="
pkg update -y && pkg upgrade -y

echo ""
echo "== Step 3/5: Installing proot-distro and openssh =="
pkg install -y proot-distro openssh

echo ""
echo "== Step 4/5: Installing Debian userspace (this takes a while) =="
proot-distro install debian

echo ""
echo "== Step 5/5: Starting SSH access =="
echo "Set a temporary password — you'll use it exactly once, from the"
echo "laptop, to run termux-bootstrap.yml. Ansible disables password"
echo "auth as soon as your SSH key is authorized."
passwd
sshd

echo ""
echo "================================================================"
echo " Setup complete. Note these down for the laptop-side Ansible steps:"
echo ""
echo "   Username: $(whoami)"
echo "   IP address(es):"
ifconfig 2>/dev/null | grep -A1 'wlan0' | grep inet | awk '{print "     " $2}'
echo "   SSH port: 8022 (Termux default)"
echo "================================================================"
echo ""
echo "Two things left to do by hand (can't be scripted):"
echo "  1. Android Settings -> Apps -> Termux -> Battery -> Unrestricted"
echo "  2. Install Termux:Boot from F-Droid (needed later for auto-start"
echo "     of sshd and the weekly upgrade cron job)"
