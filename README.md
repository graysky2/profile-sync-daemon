#Profile-sync-daemon
Profile-sync-daemon (psd) is a tiny pseudo-daemon designed to manage your browser's profile in tmpfs and to periodically sync it back to your physical disc (HDD/SSD). This is accomplished via a symlinking step and an innovative use of rsync to maintain back-up and synchronization between the two. One of the major design goals of psd is a completely transparent user experience.

##Links to Distro-Provided Packages
* ![logo](http://www.monitorix.org/imgs/archlinux.png "arch logo")Arch Linux via AUR Package: https://aur.archlinux.org/packages/profile-sync-daemon
* ![logo](http://chakra-linux.org/img/icon/chakra-kde_32.png "chakra logo")Chakra Linux via CCR Package: http://chakra-linux.org/ccr/packages.php?ID=5007
* ![logo](http://www.monitorix.org/imgs/gentoo.png "gentoo logo")Gentoo via Ebuild: http://packages.gentoo.org/package/www-misc/profile-sync-daemon
* ![logo](http://www.monitorix.org/imgs/debian.png "debian logo")![logo](http://www.monitorix.org/imgs/ubuntu.png "ubuntu logo")Debian/Ubuntu: https://launchpad.net/~graysky/+archive/utils

To add the PPA (personal package archive) to your Ubuntu system, follow these steps:
 $ sudo add-apt-repository ppa:graysky/utils
 $ sudo apt-get update

If you are interested in packaging psd for your favorite distro, please contact me and I will add the link here.

##Documentation
Consult the man page or the wiki page: https://wiki.archlinux.org/index.php/Profile-sync-daemon
