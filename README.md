#Profile-sync-daemon
Profile-sync-daemon (psd) is a tiny pseudo-daemon designed to manage your browser's profile in tmpfs and to periodically sync it back to your physical disc (HDD/SSD). This is accomplished via a symlinking step and an innovative use of rsync to maintain back-up and synchronization between the two. One of the major design goals of psd is a completely transparent user experience.

##Documentation
Consult the man page or the wiki page: https://wiki.archlinux.org/index.php/Profile-sync-daemon

##Packages by Distro
* ![logo](http://www.monitorix.org/imgs/archlinux.png "arch logo")Arch Linux via AUR Package: https://aur.archlinux.org/packages/profile-sync-daemon
* ![logo](http://chakra-linux.org/img/icon/chakra-kde_32.png "chakra logo")Chakra Linux via CCR Package: http://chakra-linux.org/ccr/packages.php?ID=5007
* ![logo](http://freedos-32.sourceforge.net/lean/debian_logo.png "debian logo")Debian: https://launchpad.net/~graysky/+archive/utils
* ![logo](http://www.repo-ck.com/fedora.png "fedora logo")Fedora: https://repo-ck.com/fedora_rpms
* ![logo](http://www.monitorix.org/imgs/gentoo.png "gentoo logo")Gentoo via Ebuild: http://packages.gentoo.org/package/www-misc/profile-sync-daemon
* ![logo](http://www.monitorix.org/imgs/ubuntu.png "ubuntu logo")Ubuntu: https://launchpad.net/~graysky/+archive/utils

###Debian Users
To add the PPA (personal package archive) to your Debian (tested on squeeze) system, and to install psd, do the following as the root user:

    echo "deb http://ppa.launchpad.net/graysky/utils/ubuntu quantal main" > /etc/apt/sources.list.d/graysky.list
    echo "deb-src http://ppa.launchpad.net/graysky/utils/ubuntu quantal main" >> /etc/apt/sources.list.d/graysky.list
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys FF7F9516
    apt-get update
    apt-get install profile-sync-daemon

###Ubuntu Users
To add the PPA (personal package archive) to your Ubuntu (packages available for Lucid and newer) system, and to install psd:

    sudo add-apt-repository ppa:graysky/utils
    sudo apt-get update
    sudo apt-get install profile-sync-daemon

###Other Distros
If you are interested in packaging psd for your favorite distro, please contact me.
