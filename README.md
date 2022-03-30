Distroshare Ubuntu Imager
=========================

This project is brought to you by [distroshare.com](distroshare.com).  Distroshare.com is 
a new site for sharing customized open source operating system distributions.  
Too often do users need to customize open source operating systems, 
such as Ubuntu, to work correctly on their machines.  By distributing 
a custom Ubuntu distro with the kinks worked out for your machine, you 
would be helping others to run Ubuntu if they have the same machine.



Distroshare Ubuntu Imager creates an installable Live ISO from an installed 
Ubuntu or derivative distribution.

It is a bash script, similar to Remastersys and its forks.  The script is 
based on this tutorial: https://help.ubuntu.com/community/MakeALiveCD/DVD/BootableFlashFromHarddiskInstall. 

To run the script, run it from the directory where it is located.  For example:


```
cd ~/distroshare-ubuntu-imager-1.0 && ./distroshare-ubuntu-imager.sh
```

To boot the ISO from a USB stick, you can use the dd command like this:

```
dd if=isoimage.iso of=/dev/sdb bs=1M
```
where sdb is your USB drive.  You should be able something similar on Mac OS X.
You can also use UNetbootin: http://unetbootin.sourceforge.net/ to create a 
bootable USB drive.

Ubuntu Startup Disk creator won't be able to turn the iso into a bootable 
usb drive since Distroshare Ubuntu Imager uses grub2 as the bootloader.
