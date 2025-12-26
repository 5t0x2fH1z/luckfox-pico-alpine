#!/bin/sh

# Install base
apk update
apk add openrc
rc-update add devfs boot
rc-update add procfs boot
rc-update add sysfs boot

# sshd permissions fix
chmod +x /etc/init.d/fix-permissions
rc-update add fix-permissions default

rc-update add networking default
rc-update add local default

# Install TTY
apk add agetty

# Setting up shell
apk add shadow
apk add bash bash-completion
chsh -s /bin/bash
echo -e "luckfox\nluckfox" | passwd
apk del -r shadow

# Install SSH
apk add openssh
rc-update add sshd default

# ntp for working internet
rc-update add ntpd default
rc-service ntpd start

# Extra stuff
apk add mtd-utils-ubi
apk add bottom
apk add neofetch

# bluez
apk add bluez
rc-update add bluetooth default

# wpa_supplicant
apk add wpa_supplicant

# python3
apk add python3

# Clear apk cache
rm -rf /var/cache/apk/*

# Packaging rootfs
for d in bin etc lib sbin usr; do tar c "$d" | tar x -C /extrootfs; done
for dir in dev proc root run sys var oem userdata; do mkdir /extrootfs/${dir}; done
