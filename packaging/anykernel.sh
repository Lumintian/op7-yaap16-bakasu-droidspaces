### YAAP16 OnePlus 7 AnyKernel3 script
### Replaces only the kernel Image; preserves the installed ramdisk and boot metadata.

properties() { '
kernel.string=YAAP16 Droidspaces + BakaSU for OnePlus 7
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=1
device.name1=guacamoleb
supported.versions=16
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=boot;
IS_SLOT_DEVICE=1;
SLOT_SELECT=active;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=0;

. tools/ak3-core.sh;

read_rom_prop() {
  local prop="$1" value file;
  for file in /system/build.prop /system/system/build.prop; do
    if [ -f "$file" ]; then
      value=$(file_getprop "$file" "$prop");
      [ "$value" ] && { echo "$value"; return; }
    fi;
  done;
  getprop "$prop" 2>/dev/null;
}

expected_fingerprint='OnePlus/yaap_guacamoleb/guacamoleb:16/BP4A.251205.006/eng.androi.20260522.192638:user/release-keys';
expected_incremental='eng.androi.20260522.192638';
actual_fingerprint=$(read_rom_prop ro.build.fingerprint);
actual_incremental=$(read_rom_prop ro.build.version.incremental);

[ "$actual_fingerprint" = "$expected_fingerprint" ] \
  || abort " " "Unsupported YAAP build fingerprint. Aborting without flashing...";
[ "$actual_incremental" = "$expected_incremental" ] \
  || abort " " "Unsupported YAAP incremental build. Aborting without flashing...";

ui_print " " "Verified YAAP16 20260522 for guacamoleb";
ui_print "Preserving active-slot ramdisk, DTB metadata, and AVB flags...";
split_boot;
flash_boot;
