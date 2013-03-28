#Profile-sync-daemon
Profile-sync-daemon (psd) is a tiny pseudo-daemon designed to manage your browser's profile in tmpfs and to periodically sync it back to your physical disc (HDD/SSD). This is accomplished via a symlinking step and an innovative use of rsync to maintain back-up and synchronization between the two. One of the major design goals of psd is a completely transparent user experience.

##Supported Browsers
Currently, the following browsers are auto-detected and managed:
* Chromium
* Conkeror
* Firefox (stable,beta,aurora)
* Firefox-trunk (this is an Ubuntu-only browser: http://www.webupd8.org/2011/05/install-firefox-nightly-from-ubuntu-ppa.html)
* Google-chrome
* Heftig's version of Aurora (this is an Arch Linux-only browser: https://bbs.archlinux.org/viewtopic.php?id=117157)
* Midori
* Opera
* Opera-Next
* QupZilla
* Rekonq
* Seamonkey

##Packages by Distro
* ![logo](http://www.monitorix.org/imgs/archlinux.png "arch logo")Arch via AUR: https://aur.archlinux.org/packages/profile-sync-daemon
* ![logo](http://chakra-linux.org/img/icon/chakra-kde_32.png "chakra logo")Chakra via CCR: http://chakra-linux.org/ccr/packages.php?ID=5008
* ![logo](http://freedos-32.sourceforge.net/lean/debian_logo.png "debian logo")Debian: See instruction below.
* ![logo](http://cloud.ohloh.net/attachments/14589/me_small.png "exherbo logo")Exherbo via exheres: http://git.exherbo.org/summer/packages/net-www/profile-sync-daemon
* ![logo](http://sec-wall.gefira.pl/media/gfx/logo-fedora.png "fedora logo")Fedora: See instruction below.
* ![logo](http://www.monitorix.org/imgs/gentoo.png "gentoo logo")Gentoo via Ebuild: http://packages.gentoo.org/package/www-misc/profile-sync-daemon
* ![logo](http://www.haskell.org/platform/icons/mint.png "mint logo")Mint: See instruction below.
* ![logo](http://gitorious.org/system/group_avatars/opensuse-developers/thumb/Geeko_head_simple.png?1259921566 "open suse")OpenSUSE via user maintained package:  http://download.opensuse.org/repositories/home:/Overman79:/Laptop/openSUSE_12.3/noarch/
* ![logo](http://www.monitorix.org/imgs/ubuntu.png "ubuntu logo")Ubuntu: See instruction below.

###Debian Users
To add the PPA (personal package archive) to your Debian (tested on squeeze) system, and to install psd, do the following as the root user:

    echo "deb http://ppa.launchpad.net/graysky/utils/ubuntu quantal main" > /etc/apt/sources.list.d/graysky.list
    echo "deb-src http://ppa.launchpad.net/graysky/utils/ubuntu quantal main" >> /etc/apt/sources.list.d/graysky.list
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys FF7F9516
    gpg --keyserver wwwkeys.pgp.net --recv-keys C1C5C63BF0E0B4E7
    gpg --armor --export C1C5C63BF0E0B4E7 | apt-key add -
    apt-get update
    apt-get install profile-sync-daemon

###Fedora Users
RPM package available: http://repo-ck.com/fedora_rpms

###Mint Users
To add the PPA (personal package archive) to your Mint system (tested on 14.1), and to install psd:

    sudo add-apt-repository ppa:graysky/utils
    sudo apt-get update
    sudo apt-get install profile-sync-daemon

###Ubuntu Users
To add the PPA (personal package archive) to your Ubuntu system (packages available for Lucid and newer), and to install psd:

    sudo add-apt-repository ppa:graysky/utils
    sudo apt-get update
    sudo apt-get install profile-sync-daemon

###Other Distros
If you are interested in packaging psd for your favorite distro, please contact me.

##Documentation
Consult the man page or the wiki page: https://wiki.archlinux.org/index.php/Profile-sync-daemon
