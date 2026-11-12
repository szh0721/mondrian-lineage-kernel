### AnyKernel3 Ramdisk Mod Script
## LineageOS 24 / Redmi K60 (mondrian) configuration

properties() { '
kernel.string=LineageOS 24 BakaSU kernel for Redmi K60 (mondrian)
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=0
do.cleanuponabort=0
device.name1=mondrian
device.name2=23013RK75C
device.name3=Redmi K60
device.name4=POCO F5 Pro
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

dump_boot;
write_boot;
