#!/bin/bash

#Distroshare Ubuntu Imager - https://www.distroshare.com
#
#Makes a Live cd that is installable from your current installation
#This is intended to work on Ubuntu and its derivatives
#
#Based on this tutorial: 
#https://help.ubuntu.com/community/MakeALiveCD/DVD/BootableFlashFromHarddiskInstall

#GPL2 License

VERSION="1.0.15"

echo "
################################################
######                                    ######
######                                    ######
###### Distroshare Ubuntu Imager $VERSION   ######
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
mkdir -p "${CD}"/casper
mkdir -p "${CD}"/boot/grub
mkdir -p "${WORK}"/rootfs

#Install essential tools
echo "Installing the essential tools"
apt-get -q=2 update
apt-get -q=2 install xorriso squashfs-tools dmraid lvm2 samba-common

GRUB2_INSTALLED=`apt-cache policy grub-pc | grep Installed | grep -v none`
#EFI support requires a different grub version. 
if [ "$EFI" == "YES" ]
then
    ARCH=`/usr/bin/arch`
    if [ "$ARCH" == "x86_64" ]
    then 
	apt-get -q=2 install grub-efi-amd64
    else
	apt-get -q=2 install grub-efi-ia32
    fi
else
    apt-get -q=2 install grub-pc
fi


echo "Installing Ubiquity"
apt-get -q=2 install casper lupin-casper
if [ "$GTK" == "YES" ]; then
   apt-get -q=2 install ubiquity-frontend-gtk
else
   apt-get -q=2 install ubiquity-frontend-kde
fi

if [ -n "$EXTRA_PKGS" ]; then
   echo "Adding extra packages to installed system"
   apt-get -q=2 install "$EXTRA_PKGS"
fi

echo "Patching Ubiquity to fix a possible installer crash"
cp /usr/share/ubiquity/plugininstall.py .
patch < plugininstall.patch
cp plugininstall.py /usr/share/ubiquity/plugininstall.py
rm -f plugininstall.py

echo "Patching Ubiquity to stop it from freaking out if zram is enabled"
cp /usr/bin/ubiquity .
patch < ubiquity.patch
cp ubiquity /usr/bin/
rm -f ubiquity

if [ "$GTK" == "YES" ]
then
    echo "Patching Ubiquity Gtk Frontend to make the dialogs smaller"
    cp /usr/lib/ubiquity/ubiquity/frontend/gtk_ui.py .
    patch < ubiquity_frontend_gtk_dialog_size.patch
    cp gtk_ui.py /usr/lib/ubiquity/ubiquity/frontend/gtk_ui.py
    rm -f gtk_ui.py
fi

if [ "$DISTROSHARE_UPDATER" == "YES" ]
then
   echo "Patching Ubiquity to rsync skel files from distroshare updater"
   cp /usr/lib/ubiquity/user-setup/user-setup-apply .
   patch < user-setup-apply.patch
   cp user-setup-apply /usr/lib/ubiquity/user-setup/user-setup-apply
   rm -f user-setup-apply

   echo "Patching user-setup to rsync skel files from distroshare updater"
   cp /usr/lib/user-setup/user-setup-apply .
   patch < user-setup-apply.patch
   cp user-setup-apply /usr/lib/user-setup/user-setup-apply
   rm -f user-setup-apply
fi

#Copy the filesystem
echo "Copying the current system to the new directories"
rsync -a --one-file-system --exclude=/proc/* --exclude=/dev/* \
--exclude=/sys/* --exclude=/tmp/* --exclude=/run/* \
--exclude=/home/* --exclude=/lost+found \
--exclude=/var/tmp/* --exclude=/boot --exclude=/root/* \
--exclude=/var/mail/* --exclude=/var/spool/* --exclude=/media/* \
--exclude=/etc/hosts --exclude=/etc/default/locale \
--exclude=/etc/timezone --exclude=/etc/shadow* --exclude=/etc/gshadow* \
--exclude=/etc/X11/xorg.conf* --exclude=/etc/gdm/custom.conf --exclude=/etc/mdm/mdm.conf \
--exclude=/etc/lightdm/lightdm.conf --exclude="${WORK}"/rootfs \
--exclude=/etc/default/du-firstrun --delete / "${WORK}"/rootfs

#Copy boot partition
echo "Copying the boot dir/partition"
rsync -a --one-file-system /boot/ "${WORK}"/rootfs/boot

#Unmount the filesystems in case the script failed before
unmount_filesystems

#Create devices in /dev
echo "Creating some links and dirs in /dev"
mkdir "${WORK}"/rootfs/dev/mapper > /dev/null 2>&1
mkdir "${WORK}"/rootfs/dev/pts > /dev/null 2>&1
ln -s /proc/kcore "${WORK}"/rootfs/dev/core > /dev/null 2>&1
ln -s /proc/self/fd "${WORK}"/rootfs/dev/fd > /dev/null 2>&1
cd "${WORK}"/rootfs/dev
ln -s fd/2 stderr > /dev/null 2>&1
ln -s fd/0 stdin > /dev/null 2>&1
ln -s fd/1 stdout > /dev/null 2>&1
ln -s ram1 ram > /dev/null 2>&1
ln -s shm /run/shm > /dev/null 2>&1

mknod agpgart c 10 175
chown root:video agpgart
chmod 660 agpgart

mknod audio c 14 4
mknod audio1 c 14 20
mknod audio2 c 14 36
mknod audio3 c 14 52
mknod audioctl c 14 7
chown root:audio audio*
chmod 660 audio*

mknod console c 5 1
chown root:tty console
chmod 600 console

mknod dsp c 14 3
mknod dsp1 c 14 19
mknod dsp2 c 14 35
mknod dsp3 c 14 51
chown root:audio dsp*
chmod 660 dsp*

mknod full c 1 7
chown root:root full
chmod 666 full

mknod fuse c 10 229
chown root:messagebus fuse
chmod 660 fuse

mknod kmem c 1 2
chown root:kmem kmem
chmod 640 kmem

mknod loop0 b 7 0
mknod loop1 b 7 1
mknod loop2 b 7 2
mknod loop3 b 7 3
mknod loop4 b 7 4
mknod loop5 b 7 5
mknod loop6 b 7 6
mknod loop7 b 7 7
chown root:disk loop*
chmod 660 loop*

cd mapper
mknod control c 10 236
chown root:root control
chmod 600 control
cd ..

mknod mem c 1 1
chown root:kmem mem
chmod 640 mem

mknod midi0 c 35 0
mknod midi00 c 14 2
mknod midi01 c 14 18
mknod midi02 c 14 34
mknod midi03 c 14 50
mknod midi1 c 35 1
mknod midi2 c 35 2
mknod midi3 c 35 3
chown root:audio midi*
chmod 660 midi*

mknod mixer c 14 0
mknod mixer1 c 14 16
mknod mixer2 c 14 32
mknod mixer3 c 14 48
chown root:audio mixer*
chmod 660 mixer*

mknod mpu401data c 31 0
mknod mpu401stat c 31 1
chown root:audio mpu401*
chmod 660 mpu401*

mknod null c 1 3
chown root:root null
chmod 666 null

mknod port c 1 4
chown root:kmem port
chmod 640 port

mknod ptmx c 5 2
chown root:tty ptmx
chmod 666 ptmx

mknod ram0 b 1 0
mknod ram1 b 1 1
mknod ram2 b 1 2
mknod ram3 b 1 3
mknod ram4 b 1 4
mknod ram5 b 1 5
mknod ram6 b 1 6
mknod ram7 b 1 7
mknod ram8 b 1 8
mknod ram9 b 1 9
mknod ram10 b 1 10
mknod ram11 b 1 11
mknod ram12 b 1 12
mknod ram13 b 1 13
mknod ram14 b 1 14
mknod ram15 b 1 15
mknod ram16 b 1 16
chown root:disk ram*
chmod 660 ram*

mknod random c 1 8
chown root:root random
chmod 666 random

mknod rmidi0 c 35 64
mknod rmidi1 c 35 65
mknod rmidi2 c 35 66
mknod rmidi3 c 35 67
chown root:audio rmidi*
chmod 660 rmidi*

mknod sequencer c 14 1
chown root:audio sequencer
chmod 660 sequencer

mknod smpte0 c 35 128
mknod smpte1 c 35 129
mknod smpte2 c 35 130
mknod smpte3 c 35 131
chown root:audio smpte*
chmod 660 smpte*

mknod sndstat c 14 6
chown root:audio sndstat
chmod 660 sndstat

mknod tty c 5 0
mknod tty0 c 4 0
mknod tty1 c 4 1
mknod tty2 c 4 2
mknod tty3 c 4 3
mknod tty4 c 4 4
mknod tty5 c 4 5
mknod tty6 c 4 6
mknod tty7 c 4 7
mknod tty8 c 4 8
mknod tty9 c 4 9
chown root:tty tty*
chmod 600 tty*

mknod urandom c 1 9
chown root:root urandom
chmod 666 urandom

mknod zero c 1 5
chown root:root zero
chmod 666 zero

cd "${CURRENT_DIR}"
#Copy the resolv.conf file - needed for newer Ubuntus
echo "Copying resolv.conf"
mv "${WORK}"/rootfs/etc/resolv.conf "${WORK}"/rootfs/etc/resolv.conf.old
cp /etc/resolv.conf "${WORK}"/rootfs/etc/resolv.conf

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

echo "Setting up display manager for autologin if needed"
#Testing for MDM and applying specific changes for it
if [ "${DM}" == "MDM" ]; then
    sed -i 's/gdm\/custom.conf/mdm\/mdm.conf/' \
/usr/share/initramfs-tools/scripts/casper-bottom/15autologin
    mkdir -p /etc/mdm
    echo "[daemon]
#AutomaticLoginEnable = false
#AutomaticLogin = none
#TimedLoginEnable = false
" > /etc/mdm/mdm.conf
    #Copy /etc/apt/sources.list to /etc/apt/sources.list.new
    cp /etc/apt/sources.list /etc/apt/sources.list.new
fi

#Testing for GDM and applying specific changes for it
if [ "${DM}" == "GDM" ]; then
    mkdir -p /etc/gdm
    echo "[daemon]
#AutomaticLoginEnable = false
#AutomaticLogin = none
#TimedLoginEnable = false
" > /etc/gdm/custom.conf
fi

if [ "${DM}" == "KDM" ]; then
    mkdir -p /etc/kde4/kdm
    echo "[X-:0-Core]
AutoLoginEnable=false
AutoLoginUser=none
AutoReLogin=false
" > /etc/kde4/kdm/kdmrc
fi

if [ "${DM}" == "LIGHTDM_UBUNTU_MATE" ]; then
 sed -i 's/\/etc\/lightdm\/lightdm.conf/\/usr\/share\/lightdm\/lightdm.conf.d\/60-lightdm-gtk-greeter.conf/' \
/usr/share/initramfs-tools/scripts/casper-bottom/15autologin

 sed -i 's/autologin-session=lightdm-autologin/user-session=mate/' \
/usr/share/initramfs-tools/scripts/casper-bottom/15autologin
fi

if [ "${DM}" == "LIGHTDM_ZORIN" ]; then
 echo "[SeatDefaults]
user-session=zorin_desktop
" > /etc/lightdm/lightdm.conf

 sed -i 's/autologin-session=lightdm-autologin/user-session=zorin_desktop/' \
/usr/share/initramfs-tools/scripts/casper-bottom/15autologin
fi

if [ "${DM}" == "LIGHTDM_KODIBUNTU" ]; then
 echo "[SeatDefaults]
xserver-command=/usr/bin/X -bs -nolisten tcp
user-session=kodi
allow-guest=false
greeter-session=lightdm-gtk-greeter
" > /etc/lightdm/lightdm.conf

 sed -i 's/autologin-session=lightdm-autologin/user-session=kodi/' \
/usr/share/initramfs-tools/scripts/casper-bottom/15autologin
fi

if [ "${DM}" == "LIGHTDM_DEEPIN" ]; then
 echo "[SeatDefaults]
greeter-session=lightdm-deepin-greeter
user-session=deepin
" > /etc/lightdm/lightdm.conf

 sed -i 's/autologin-session=lightdm-autologin/user-session=deepin/' \
/usr/share/initramfs-tools/scripts/casper-bottom/15autologin

 #Fix for installer icon on desktop 
 sed -i 's/ubiquity.desktop/ubiquity-gtkui.desktop/' \
/usr/share/initramfs-tools/scripts/casper-bottom/25adduser
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
rm -f /etc/hosts
rm -f /etc/hostname
rm -f /etc/mtab*
rm -f /etc/fstab
rm -f /etc/udev/rules.d/70-persistent*
rm -f /etc/cups/ssl/server.crt
rm -f /etc/cups/ssl/server.key
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
cp -p "${WORK}"/rootfs/boot/vmlinuz-"${KERNEL_VERSION}" "${CASPER}"/vmlinuz
cp -p "${WORK}"/rootfs/boot/initrd.img-"${KERNEL_VERSION}" "${CASPER}"/initrd.img
cp -p "${WORK}"/rootfs/boot/memtest86+.bin "${CD}"/boot

echo "Creating filesystem.manifest"
dpkg-query -W --showformat='${Package} ${Version}\n' > "${CASPER}"/filesystem.manifest

cp "${CASPER}"/filesystem.manifest "${CASPER}"/filesystem.manifest-desktop
REMOVE='ubiquity ubiquity-frontend-gtk ubiquity-frontend-kde casper user-setup os-prober libdebian-installer4 apt-clone archdetect-deb dpkg-repack gir1.2-json-1.0 gir1.2-timezonemap-1.0 gir1.2-xkl-1.0 libdebian-installer4 libparted-fs-resize0 libtimezonemap-data libtimezonemap1 python3-icu python3-pam rdate sbsigntool ubiquity-casper ubiquity-ubuntu-artwork localechooser-data cifs-utils  gir1.2-appindicator3-0.1 gir1.2-javascriptcoregtk-3.0 gir1.2-vte-2.90 gir1.2-webkit-3.0' 
for i in $REMOVE
do
   sed -i "/${i}/d" "${CASPER}"/filesystem.manifest-desktop
done

#Remove the extra script created to prevent an error message
rm -f "$CASPER_EXTRA_SCRIPT"

echo "Uninstalling Ubiquity"
apt-get -q=2 remove casper lupin-casper ubiquity user-setup

if [ -n "$EXTRA_PKGS" ]; then
   echo "Removing extra packages from installed system"
   apt-get -q=2 remove "$EXTRA_PKGS"
fi

if [ -n "$GRUB2_INSTALLED" -a "$EFI" == "YES" ]
then
    sudo apt-get install grub-pc
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
grub-mkrescue -iso-level 3 -o "${WORK}"/live-cd.iso "${CD}"

echo "We are done."
echo "Is your distro interesting or customized for a specific machine?"
echo "How about sharing it at https://www.distroshare.com?"
echo "You will help others and you could receive donations for your work."
echo ""
