#!/bin/bash
#
# Flash Yocto into eMMC for DART-MX6
#

# Partitions sizes in MiB
BOOTLOAD_RESERVE=4
BOOT_ROM_SIZE=8
SPARE_SIZE=0


if [ `dmesg | grep VAR-DART | wc -l` = 1 ] ; then
	echo "      Variscite Flash DART-MX6 eMMC utility      "
	echo "================================================="
else
	echo "================================================="
	echo " yocto-dart.sh is compatible with DART-MX6 only. "
	echo " Please use nand-recovery or:                    "
	echo " android_emmc.sh, yocto_emmc.sh, yocto_nand.sh   "
	echo "================================================="
	read -p "Press any key to continue... " -n1
	exit 1
fi

cd /opt/images/Yocto
if [ ! -f SPL.mmc ]
then
	echo "SPL does not exist! exit."
	exit 1
fi	
if [ ! -f u-boot.img.mmc ]
then
	echo "u-boot.img does not exist! exit."
	exit 1
fi	


help() {

bn=`basename $0`
cat << EOF
usage $bn <option> device_node

options:
  -h			displays this help message
  -s			only get partition size
EOF

}

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run with super-user privileges" 
	exit 1
fi

# Parse command line
moreoptions=1
node="/dev/mmcblk2"
part=p
cal_only=0

if [ ! -e ${node} ]; then
	help
	exit
fi

function format_yocto
{
	echo "Formating Yocto partitions"
	echo "=========================="
	umount /run/media/mmcblk2p1 2>/dev/null
	umount /run/media/mmcblk2p2 2>/dev/null
	mkfs.vfat /dev/mmcblk2p1 -nBOOT-VARSOM
	mkfs.ext4 /dev/mmcblk2p2 -Lrootfs
	sync
}

function flash_yocto
{
	echo "Flashing Yocto "
	echo "==============="

	echo "Flashing U-Boot"
	sudo dd if=u-boot.img.mmc of=${node} bs=1K seek=69; sync
	sudo dd if=SPL.mmc of=${node} bs=1K seek=1; sync

	echo "Flashing Yocto BOOT partition"
	mkdir -p /tmp/media/mmcblk2p1
	mkdir -p /tmp/media/mmcblk2p2
	mount -t vfat /dev/mmcblk2p1  /tmp/media/mmcblk2p1
	mount /dev/mmcblk2p2  /tmp/media/mmcblk2p2
	cp uImage-imx6q-var-dart.dtb /tmp/media/mmcblk2p1/imx6q-var-dart.dtb
	cp uImage /tmp/media/mmcblk2p1/uImage

	echo "Flashing Yocto Root File System"
	rm -rf /tmp/media/mmcblk2p2/*
	tar xvpf rootfs.tar.bz2 -C /tmp/media/mmcblk2p2/ 2>&1 |
	while read line; do
		x=$((x+1))
		echo -en "$x extracted\r"
	done
}


umount /run/media/mmcblk2p* 2>/dev/null

echo
echo "Deleting the current partitions"

for ((i=0; i<10; i++))
do
	if [ `ls ${node}${part}$i 2> /dev/null | grep -c ${node}${part}$i` -ne 0 ]; then
		dd if=/dev/zero of=${node}${part}$i bs=512 count=1024
	fi
done
sync

((echo d; echo 1; echo d; echo 2; echo d; echo 3; echo d; echo w) | fdisk ${node} &> /dev/null) || true
sync

dd if=/dev/zero of=${node} bs=1M count=4
sync

echo
echo "Creating new partitions"
# Create a new partition table
fdisk ${node} <<EOF 
n
p
1
8192
24575
t
c
n
p
2
24576

p
w
EOF

# Get total card size
total_size=`sfdisk -s ${node}`
total_size=`expr ${total_size} / 1024`
boot_rom_sizeb=`expr ${BOOT_ROM_SIZE} + ${BOOTLOAD_RESERVE}`
rootfs_size=`expr ${total_size} - ${boot_rom_sizeb} - ${SPARE_SIZE}`

echo "ROOT SIZE=${rootfs_size} TOTAl SIZE=${total_size} BOOTROM SIZE=${boot_rom_sizeb}"
echo "======================================================"
# create partitions 
#if [ "${cal_only}" -eq "1" ]; then
#cat << EOF
#BOOT   : ${boot_rom_sizeb}MiB
#ROOT   : ${rootfs_size}MiB
#EOF
#exit
#fi

#sfdisk --force -uM ${node} << EOF
#,${boot_rom_sizeb},c
#,${rootfs_size},83
#EOF

# adjust the partition reserve for bootloader.
# if you don't put the uboot on same device, you can remove the BOOTLOADER_ERSERVE
# to have 8M space.
# the minimal sylinder for some card is 4M, maybe some was 8M
# just 8M for some big eMMC 's sylinder
#sfdisk --force -uM ${node} -N1 << EOF
#${BOOTLOAD_RESERVE},${BOOT_ROM_SIZE},c
#EOF

sync
sleep 2

format_yocto
flash_yocto

echo "syncing"
sync
umount /tmp/media/mmcblk2p1
umount /tmp/media/mmcblk2p2

read -p "Yocto Flashed. Press any key to continue... " -n1
