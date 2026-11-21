#!/bin/sh
set -eu

cd /opt/monitor

# shellcheck source=manifest.env
. ./manifest.env

INPUTS=/inputs
CACHE=/cache
OUT=${OUT:-/out}
img=$OUT/$BOARD.img

if [ -t 1 ]; then
	esc=$(printf '\033')
	tag_error="[${esc}[31m!${esc}[0m]"
	tag_done="[${esc}[32m\$${esc}[0m]"
	tag_note="[${esc}[36m*${esc}[0m]"
else
	tag_error="[!]"
	tag_done="[$]"
	tag_note="[*]"
fi

try() {
	msg=$1
	shift
	if ! "$@"; then
		echo "$tag_error $msg" >&2
		exit 1
	fi
}

cleanup() {
	rm -rf "$work"
}

try "Needs root" test "$(id -u)" = 0
try "Missing $INPUTS/$BASE_IMG" test -f "$INPUTS/$BASE_IMG"
try "Missing $INPUTS/base.txz" test -f "$INPUTS/base.txz"
try "Missing $INPUTS/kernel.txz" test -f "$INPUTS/kernel.txz"

mkdir -p "$OUT"

work=$(mktemp -d)

trap cleanup EXIT

# Prepare boot and root staging trees
mkdir -p "$work/fat" "$work/root"

# Check if the base image has the same structure as it had when the script
# was written (FAT at s1)
echo "drive b: file=\"$INPUTS/$BASE_IMG\" partition=1" >"$work/mtoolsrc"
export MTOOLSRC="$work/mtoolsrc"
try "Base image has no FAT at s1" mcopy -s -p -m b: "$work/fat"

# Install the system from the release dists
tar -xf "$INPUTS/base.txz" -C "$work/root" --no-fflags
tar -xf "$INPUTS/kernel.txz" -C "$work/root" --no-fflags

# Apply the latest patches
mkdir -p "$work/update" "$CACHE/freebsd-update"
ln -s "$CACHE/freebsd-update" "$work/update/files"
cp "$work/root/etc/freebsd-update.conf" "$work/update.conf"
echo "BackupKernel no" >>"$work/update.conf"
UNAME_m=arm64 UNAME_i=GENERIC PAGER=cat freebsd-update -f "$work/update.conf" \
    -b "$work/root" -d "$work/update" --currently-running "$FREEBSD_VERSION" \
    --not-running-from-cron fetch install
version=$(sh "$work/root/bin/freebsd-version" -u)
echo "$tag_note Patched to $version"

# Clean up the FAT boot partition
find "$work/fat" -maxdepth 1 -name '*.dtb' ! -name "$DTB" -delete

# Patch the DTB so that the "fixed-clock" warning during boot disappears
dtc -I dtb -O dts -o "$work/d.dts" "$work/fat/$DTB"
n=$(python3 dtb.py "$work/d.dts" "$work/d.dts2")
try "DTB needed no patch" test "$n" -gt 0
dtc -I dts -O dtb -o "$work/fat/$DTB" "$work/d.dts2"
echo "$tag_note Patched $n fixed-clock nodes in $DTB"
rm -f "$work/d.dts" "$work/d.dts2"

# Copy our root overlay into a staging tree and replace placeholders there
overlay=$work/overlay
mkdir -p "$overlay"
cp -Rp root/. "$overlay/"

# shellcheck disable=SC3028
find "$overlay" -type f -exec sed -i '' \
	-e "s|@POOL@|$POOL|g" \
	-e "s|@BOOT_ENV@|$BOOT_ENV|g" \
	-e "s|@HOSTNAME@|$HOSTNAME|g" {} +

cp -Rp "$overlay/." "$work/root/"

find "$work/root" -name '*.append' | while read -r f; do
	cat "$f" >>"${f%.append}"
	rm "$f"
done

# Test the staging trees
try "loader.conf must be name-free" test "$(grep -c 'vfs\.root\.mountfrom' "$work/root/boot/loader.conf")" -eq 0

# Create the boot partition and the pool with its datasets
makefs -t msdos -s "$((FAT_SECTORS * 512))" \
	-o fat_type=32,sectors_per_cluster=4,volume_label=BOOT \
	"$work/fat.img" "$work/fat" >/dev/null

mkdir -p "$work/root/data" "$work/root/jails" "$work/root/var/log.persist"
makefs -t zfs -s "$((IMAGE_SIZE_MB * 1024 * 1024 - POOL_START * 512))" \
	-o poolname="$POOL" -o bootfs="$POOL/$BOOT_ENV" -o rootpath=/ \
	-o fs="$POOL;compression=lz4;atime=off;mountpoint=none" \
	-o fs="$POOL/ROOT;mountpoint=none;canmount=off" \
	-o fs="$POOL/$BOOT_ENV;mountpoint=/;canmount=noauto" \
	-o fs="$POOL/data;mountpoint=/data" \
	-o fs="$POOL/jails;mountpoint=/jails" \
	-o fs="$POOL/log;mountpoint=/var/log.persist" \
	"$work/zfs.img" "$work/root"

mkimg -s mbr \
	-p "fat32lba:=$work/fat.img:$((FAT_START * 512))" \
	-p "freebsd:=$work/zfs.img:$((POOL_START * 512))" \
	-o "$img"

try "FAT inconsistent" fsck_msdosfs -n "$work/fat.img"
echo "$version" >"$OUT/$BOARD.version"
echo "$tag_done Wrote $img"
