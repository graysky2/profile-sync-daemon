# Profile-sync-daemon
Profile-sync-daemon (psd) is a tiny pseudo-daemon designed to manage your browser's profile in tmpfs and to periodically sync it back to your physical disc (HDD/SSD). This is accomplished via a symlinking step and an innovative use of rsync to maintain back-up and synchronization between the two. One of the major design goals of psd is a completely transparent user experience.

## Good Advice
Always backup your browser profile(s) before using psd for the first time.

## Users of eCryptFS
User of eCryptFS are encouraged not to use psd unless willing to help troubleshoot suspected browser corruption. See [#158](https://github.com/graysky2/profile-sync-daemon/issues/158).

## Supported Browsers
* Chromium
* Conkeror
* Epiphany
* Firefox (stable, beta, and aurora)
* Firefox-trunk (this is an Ubuntu-only browser: http://www.webupd8.org/2011/05/install-firefox-nightly-from-ubuntu-ppa.html)
* Google Chrome (stable, beta, and dev)
* Heftig's version of Aurora (this is an Arch Linux-only browser: https://bbs.archlinux.org/viewtopic.php?id=117157)
* Icecat (GNU version of Firefox)
* Iceweasel (Debian version of Firefox)
* Inox (https://bbs.archlinux.org/viewtopic.php?id=198763)
* Luakit
* Midori
* Opera, Opera-Beta, Opera-Developer, and Opera-Legacy
* Otter-browser
* Palemoon
* QupZilla
* Qutebrowser
* Rekonq
* Seamonkey
* Surf (http://surf.suckless.org/)
* Vivaldi-browser and Vivaldi-browser-snapshot
* Waterfox (https://www.waterfoxproject.org/)

## Documentation
Consult the man page or the wiki page: https://wiki.archlinux.org/index.php/Profile-sync-daemon

## Installation from Source
To build from source, see the included INSTALL text document.

## Installation from Distro Packages
### Officially Packaged
* ![logo](http://gnulinuxvagos.es/public/style_extra/downloads_traffic_images/os_Antergos.png "antergos logo")Antergos: in the official [repos](http://build.antergos.com/package/profile-sync-daemon).
* ![logo](http://freedos-32.sourceforge.net/lean/debian_logo.png "debian logo")Debian jesse+: in the official [repos](https://packages.debian.org/unstable/profile-sync-daemon).
* ![logo](https://s19.postimg.org/sjwaizg8j/zebrapig_head.png "exherbo logo")Exherbo: in the official [repos](http://git.exherbo.org/summer/packages/net-www/profile-sync-daemon).
* ![logo](http://s9.postimg.org/p5f1tscxn/fedora.jpg "fedora logo")Fedora: in the official [repos](http://koji.fedoraproject.org/koji/packageinfo?packageID=16307).
* ![logo](http://www.monitorix.org/imgs/gentoo.png "gentoo logo")Gentoo: in the official [repos](http://packages.gentoo.org/package/www-misc/profile-sync-daemon).
* ![logo](http://s23.postimg.org/5pabe2o5z/void_logo_transparent.png "void logo")Void: in the official [repos](https://github.com/xtraeme/xbps-packages/tree/master/srcpkgs/profile-sync-daemon).
* ![logo](http://www.monitorix.org/imgs/ubuntu.png "ubuntu logo")Ubuntu 16.10+: in the universe [repo](http://packages.ubuntu.com/yakkety/profile-sync-daemon).

### User Packaged
* ![logo](http://www.monitorix.org/imgs/archlinux.png "arch logo")Arch: in the [AUR](https://aur.archlinux.org/packages/profile-sync-daemon).

* ![logo](http://s18.postimg.org/w5jvz71mt/chakra.jpg "chakra logo")Chakra: in the [CCR](http://chakraos.org/ccr/packages.php?ID=5008).
* ![logo](http://wiki.codeblocks.org/images/8/8b/Slackware-logo_32.png "slack logo")Slackware: on [slackbuilds](http://slackbuilds.org/apps/profile-sync-daemon/).
* ![logo](http://www.monitorix.org/imgs/ubuntu.png "ubuntu logo")Ubuntu: in [graysky's PPA](https://github.com/graysky2/profile-sync-daemon#ubuntu-users).

### Debian Users
Since June of 2016, Profile-sync-daemon is in the official repos for Users of jesse+! [Reference](https://tracker.debian.org/pkg/profile-sync-daemon).

    sudo apt-get install profile-sync-daemon

### Fedora Users
Since June of 2013, Profile-sync-daemon is in the official repos! [Reference](https://bugzilla.redhat.com/show_bug.cgi?id=968253).

    sudo yum install profile-sync-daemon

### Ubuntu Users
Since June of 2016, Profile-sync-daemon is in the official repos for users of Yakkety+ (16.10+)! [Reference](https://launchpad.net/ubuntu/+source/profile-sync-daemon).

Others must be using AT LEAST Ubuntu 15.04 (Vivid) or have systemd as your init system to use these packages!
To add the PPA (personal package archive) to your Ubuntu system (packages available for Vivid and newer), and to install psd:

    sudo add-apt-repository ppa:graysky/utils
    sudo apt-get update
    sudo apt-get install profile-sync-daemon

### Other Distros
If you are interested in packaging psd for your favorite distro, please contact me.

## NOTE FOR VERSION 6
My desktop distro (Arch) switched to systemd a while ago and other big ones (Fedora, Debian, Ubuntu) have followed suite. With the release of psd version 6.x I will no longer be supporting alternative init systems such as upstart and openrc. It is too complex for me to maintain and test multiple configurations on non-native init systems for me.

Also of note for version 6.x is that no longer does psd run in as a system service. It now runs as a user service.
This is much more simple and means that:
* There is no more need for `/etc/psd.conf` and the USERS array therein.
* Different users can have their own config files that THEY own (`~/.psd/psd.conf`).
* Encrypted $HOME should be supported under this model (NOT yet implemented).

Update instructions from version 5.x:
* Stop psd v5.7x and close your browsers.
* Build the package linked above and install it.
* Run psd to create your `~/.config/psd/psd.conf` and then edit it as you normally would.
* Check it in parse mode `psd p` and if happy with the output, run it via systemd usermode: `systemctl --user start psd` (and optionally enable it).

Note that if you're using overlayfs mode, your user needs to have sudo right to /usr/bin/psd-overlay-helper or else psd will refuse to run in overlayfs mode.


