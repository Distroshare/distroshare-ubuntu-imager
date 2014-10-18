#!/bin/bash

#Distroshare Ubuntu Imager - https://www.distroshare.com
#
#Makes a Live cd that is installable from your current installation
#This is intended to work on Ubuntu and its derivatives
#
#Based on this tutorial: 
#https://help.ubuntu.com/community/MakeALiveCD/DVD/BootableFlashFromHarddiskInstall

#GPL2 License

VERSION="1.0.5"

echo "
################################################
######                                    ######
######                                    ######
###### Distroshare Ubuntu Imager $VERSION    ######
######                                    ######
######                                    ######
###### Brought to you by distroshare.com  ######
######                                    ######
######                                    ######
################################################


"

#Configuration file name and path
CONFIG_FILE="./distroshare-ubuntu-imager.config"

#Current directory
CURRENT_DIR=`pwd`

#Convience function to unmount filesystems
unmount_filesystems() {
    echo "Unmounting filesystems"
    umount "${WORK}"/rootfs/proc > /dev/null 2>&1
    umount "${WORK}"/rootfs/sys > /dev/null 2>&1
    umount -l "${WORK}"/rootfs/dev/pts > /dev/null 2>&1
    umount -l "${WORK}"/rootfs/dev > /dev/null 2>&1
}

#Starting the process

#We depend on the umask being 022
umask 022

#Source the config file
if [ -r "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    echo "Can't read config file.  Exiting"
    exit 1
fi

#Set some other variables based on the config file
CD="${WORK}"/CD
CASPER="${CD}"/casper

#Checking for root
if [ "$USER" != "root" ]; then
    echo "You aren't root, so I'm exiting.  Become root and try again."
    exit 1
fi

#Make the directories
echo "Making the necessary directories"
mkdir -p "${CD}"/{casper,boot/grub}
mkdir -p "${WORK}"/rootfs

#Install essential tools
echo "Installing the essential tools"
apt-get -q=2 update
apt-get -q=2 install grub2 xorriso squashfs-tools

echo "Installing Ubiquity"
apt-get -q=2 install casper lupin-casper
echo "GTK is: $GTK"
if [ "$GTK" == "YES" ]; then
   apt-get -q=2 install ubiquity-frontend-gtk
else
   apt-get -q=2 install ubiquity-frontend-qt
fi

if [ -n "$EXTRA_PKGS" ]; then
   echo "Adding extra packages to installed system"
   apt-get -q=2 install "$EXTRA_PKGS"
fi

#Copy the filesystem
echo "Copying the current system to the new directories"
rsync -a --one-file-system --exclude=/proc/* --exclude=/dev/* \
--exclude=/sys/* --exclude=/tmp/* --exclude=/run/* \
--exclude=/home/* --exclude=/lost+found \
--exclude=/var/tmp/* --exclude=/boot --exclude=/root/* \
--exclude=/var/mail/* --exclude=/var/spool/* --exclude=/media/* \
--exclude=/etc/hosts \
--exclude=/etc/timezone --exclude=/etc/shadow* --exclude=/etc/gshadow* \
--exclude=/etc/X11/xorg.conf* --exclude=/etc/gdm/custom.conf --exclude=/etc/mdm/mdm.conf \
--exclude=/etc/lightdm/lightdm.conf --exclude="${WORK}"/rootfs / "${WORK}"/rootfs

#Copy boot partition
echo "Copying the boot dir/partition"
rsync -a --one-file-system /boot/ "${WORK}"/rootfs/boot

#Create some links and dirs in /dev
echo "Creating some links and dirs in /dev"
mkdir "${WORK}"/rootfs/dev/mapper
mkdir "${WORK}"/rootfs/dev/pts
ln -s /proc/kcore "${WORK}"/rootfs/dev/core
ln -s /proc/self/fd "${WORK}"/rootfs/dev/fd
cd "${WORK}"/rootfs/dev
ln -s fd/2 stderr
ln -s fd/0 stdin
ln -s fd/1 stdout
ln -s ram ram1
rsync -a /dev/urandom urandom
cd "${CURRENT_DIR}"

#Copy the resolv.conf file - needed for newer Ubuntus
echo "Copying resolv.conf"
mv "${WORK}"/rootfs/etc/resolv.conf "${WORK}"/rootfs/etc/resolv.conf.old
cp /etc/resolv.conf "${WORK}"/rootfs/etc/resolv.conf

#Unmount the filesystems in case the script failed before
unmount_filesystems

#Mount dirs into copied distro
echo "Mounting system file dirs"
mount --bind /dev/ "${WORK}"/rootfs/dev
mount --bind /dev/pts "${WORK}"/rootfs/dev/pts
mount -t proc proc "${WORK}"/rootfs/proc
mount -t sysfs sysfs "${WORK}"/rootfs/sys

#Remove non-system users
echo "Removing non-system users"
for i in `cat "${WORK}"/rootfs/etc/passwd | awk -F":" '{print $1}'`
do
   uid=`cat "${WORK}"/rootfs/etc/passwd | grep "^${i}:" | awk -F":" '{print $3}'`
   [ "$uid" -gt "998" -a  "$uid" -ne "65534"  ] && \
       chroot "${WORK}"/rootfs /bin/bash -c "userdel --force ${i} 2> /dev/null"
done

#Source lsb-release for DISTRIB_ID
. /etc/lsb-release

#Run commands in chroot
echo "Creating script to run in chrooted env"
cat > "${WORK}"/rootfs/distroshare_imager.sh <<EOF
#!/bin/bash

umask 022

#Modify copied distro
if [ -n "$UBIQUITY_KERNEL_PARAMS" ]; then
  echo "Replacing ubiquity default extra kernel params with: $UBIQUITY_KERNEL_PARAMS"
  sed -i "s/defopt_params=\"\"/defopt_params=\"${UBIQUITY_KERNEL_PARAMS}\"/" \
/usr/share/grub-installer/grub-installer
fi

#Set flavour in /etc/casper.conf
echo "export FLAVOUR=\"${DISTRIB_ID}\"" >> /etc/casper.conf

#Checking for LinuxMint and applying specific changes for it
if [ "${DISTRIB_ID}" == "LinuxMint" ]; then
    sed -i 's/gdm\/custom.conf/mdm\/mdm.conf/' \
/usr/share/initramfs-tools/scripts/casper-bottom/15autologin
    echo "[daemon]
#AutomaticLoginEnable = false
#AutomaticLogin = none
#TimedLoginEnable = false
" > /etc/mdm/mdm.conf
    #Copy /etc/apt/sources.list to /etc/apt/sources.list.new
    cp /etc/apt/sources.list /etc/apt/sources.list.new
fi

#Update initramfs 
echo "Updating initramfs"
depmod -a $(uname -r)
update-initramfs -u -k all > /dev/null 2>&1

#Clean up downloaded packages
echo "Cleaning up files that are not needed in the new image"
apt-get clean

#Clean up files
#rm -f /etc/X11/xorg.conf*
rm -f /etc/{hosts,hostname,mtab*,fstab}
rm -f /etc/udev/rules.d/70-persistent*
rm -f /etc/cups/ssl/{server.crt,server.key}
rm -f /etc/NetworkManager/system-connections/*
rm -f /etc/ssh/*key*
rm -f /var/lib/dbus/machine-id
rm -f /etc/resolv.conf
mv /etc/resolv.conf.old /etc/resolv.conf
truncate -s 0 /etc/printcap > /dev/null 2>&1
truncate -s 0 /etc/cups/printers.conf
rm -rf /var/lib/sudo/*
rm -rf /var/lib/AccountsService/users/*
rm -rf /var/lib/kdm/*
rm -rf /var/lib/lightdm/*
rm -rf /var/lib/lightdm-data/*
rm -rf /var/lib/gdm/*
rm -rf /var/lib/gdm-data/*
rm -rf /var/lib/mdm/*
rm -rf /var/lib/mdm-data/*
rm -rf /var/run/console/*

#If /var/run is a link, then it is pointing to /run
if [ ! -L /var/run ]; then
  find /var/run/ -type f -exec rm -f {} \;
fi

#If /var/lock is a link, then it is pointing to /run/lock
if [ ! -L /var/lock ]; then
  find /var/lock/ -type f -exec rm -f {} \;
fi

#Clean up files - taken from BlackLab Imager
find /var/backups/ /var/spool/ /var/mail/ \
/var/tmp/ /var/crash/ \
/var/lib/ubiquity/ -type f -exec rm -f {} \;

#Remove archived logs
find /var/log -type f -name '*.[0-9]*' -exec rm -f {} \;

#Truncate all logs
find /var/log -type f -exec truncate -s 0 {} \;

EOF

echo "Running script in chrooted env"
chmod 700 "${WORK}"/rootfs/distroshare_imager.sh
chown root:root "${WORK}"/rootfs/distroshare_imager.sh
chroot "${WORK}"/rootfs /distroshare_imager.sh
rm -f "${WORK}"/rootfs/distroshare_imager.sh

echo "Copying over kernel and initrd"
if [ -n "${KERNEL_VERSION}" ]; then
    KERNEL_VERSION=$(uname -r)
fi

cp -p "${WORK}"/rootfs/boot/vmlinuz-${kversion} "${CASPER}"/vmlinuz
cp -p "${WORK}"/rootfs/boot/initrd.img-${kversion} "${CASPER}"/initrd.img
cp -p "${WORK}"/rootfs/boot/memtest86+.bin "${CD}"/boot

echo "Creating filesystem.manifest"
dpkg-query -W --showformat='${Package} ${Version}\n' > "${CASPER}"/filesystem.manifest

cp "${CASPER}"/filesystem.manifest{,-desktop}
REMOVE='ubiquity ubiquity-frontend-gtk ubiquity-frontend-kde casper user-setup os-prober libdebian-installer4'
for i in $REMOVE
do
   sed -i "/${i}/d" "${CASPER}"/filesystem.manifest-desktop
done

echo "Uninstalling Ubiquity"
apt-get -q=2 remove casper lupin-casper ubiquity

if [ -n "$EXTRA_PKGS" ]; then
   echo "Removing extra packages from installed system"
   apt-get -q=2 remove "$EXTRA_PKGS"
fi

echo "Removing temp files"
rm -rf "${WORK}"/rootfs/tmp/*
rm -rf "${WORK}"/rootfs/run/*

unmount_filesystems
echo "Making squashfs - this is going to take a while"
mksquashfs "${WORK}"/rootfs "${CASPER}"/filesystem.squashfs -noappend

echo "Making filesystem.size"
echo -n $(du -s --block-size=1 "${WORK}"/rootfs | \
    tail -1 | awk '{print $1}') > "${CASPER}"/filesystem.size
echo "Making md5sum"
rm -f "${CD}"/md5sum.txt
find "${CD}" -type f -print0 | xargs -0 md5sum | sed "s@${CD}@.@" | \
    grep -v md5sum.txt >> "${CD}"/md5sum.txt

echo "Creating release notes url"
mkdir "${CD}"/.disk
echo "${RELEASE_NOTES_URL}" > "${CD}"/.disk/release_notes_url

echo "Creating grub.cfg"
echo "
set default=\"0\"
set timeout=10

menuentry \"Ubuntu GUI\" {
linux /casper/vmlinuz boot=casper $KERNEL_PARAMS quiet splash --
initrd /casper/initrd.img
}

menuentry \"Ubuntu in safe mode\" {
linux /casper/vmlinuz boot=casper $KERNEL_PARAMS xforcevesa quiet splash --
initrd /casper/initrd.img
}

menuentry \"Ubuntu CLI\" {
linux /casper/vmlinuz boot=casper $KERNEL_PARAMS textonly quiet splash --
initrd /casper/initrd.img
}

menuentry \"Ubuntu GUI persistent mode\" {
linux /casper/vmlinuz boot=casper $KERNEL_PARAMS persistent quiet splash --
initrd /casper/initrd.img
}

menuentry \"Ubuntu GUI from RAM\" {
linux /casper/vmlinuz boot=casper $KERNEL_PARAMS toram quiet splash --
initrd /casper/initrd.img
}

menuentry \"Check Disk for Defects\" {
linux /casper/vmlinuz boot=casper $KERNEL_PARAMS integrity-check quiet splash --
initrd /casper/initrd.img
}

menuentry \"Memory Test\" {
linux16 /boot/memtest86+.bin --
}

menuentry \"Boot from the first hard disk\" {
set root=(hd0)
chainloader +1
}
" > "${CD}"/boot/grub/grub.cfg

echo "Creating the iso"
grub-mkrescue -o "${WORK}"/live-cd.iso "${CD}"

echo "We are done."
echo "Is your distro interesting or customized for a specific machine?"
echo "How about sharing it at https://www.distroshare.com?"
echo "You will help others and you could receive donations for your work."
echo ""
