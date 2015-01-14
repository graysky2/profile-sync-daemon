#Profile-sync-daemon
Profile-sync-daemon (psd) is a tiny pseudo-daemon designed to manage your browser's profile in tmpfs and to periodically sync it back to your physical disc (HDD/SSD). This is accomplished via a symlinking step and an innovative use of rsync to maintain back-up and synchronization between the two. One of the major design goals of psd is a completely transparent user experience.

##Supported Browsers
* Chromium
* Conkeror
* Epiphany
* Firefox (stable, beta, and aurora)
* Firefox-trunk (this is an Ubuntu-only browser: http://www.webupd8.org/2011/05/install-firefox-nightly-from-ubuntu-ppa.html)
* Google Chrome (stable, beta, and dev)
* Heftig's version of Aurora (this is an Arch Linux-only browser: https://bbs.archlinux.org/viewtopic.php?id=117157)
* Icecat (GNU version of Firefox)
* Iceweasel (Debian version of Firefox)
* Luakit
* Midori
* Opera, Opera-Beta and Opera-Developer
* Otter-browser
* Palemoon
* QupZilla
* Rekonq
* Seamonkey

##Documentation
Consult the man page or the wiki page: https://wiki.archlinux.org/index.php/Profile-sync-daemon

##Installation from Source
To build from source, see the included INSTALL text document.

##Installation from Distro Packages
* ![logo](http://www.monitorix.org/imgs/archlinux.png "arch logo")Arch: in the [AUR](https://aur.archlinux.org/packages/profile-sync-daemon).
* ![logo](http://s18.postimg.org/w5jvz71mt/chakra.jpg "chakra logo")Chakra: in the [CCR](http://chakraos.org/ccr/packages.php?ID=5008).
* ![logo](http://freedos-32.sourceforge.net/lean/debian_logo.png "debian logo")Debian: in [graysky's PPA](https://github.com/graysky2/profile-sync-daemon#debian-users).
* ![logo](http://cloud.ohloh.net/attachments/14589/me_small.png "exherbo logo")Exherbo: in the Exherbo [repos](http://git.exherbo.org/summer/packages/net-www/profile-sync-daemon).
* ![logo](http://s9.postimg.org/p5f1tscxn/fedora.jpg "fedora logo")Fedora: in the official [repos](http://koji.fedoraproject.org/koji/packageinfo?packageID=16307).
* ![logo](http://www.monitorix.org/imgs/gentoo.png "gentoo logo")Gentoo: in the Gentoo [repos](http://packages.gentoo.org/package/www-misc/profile-sync-daemon).
* ![logo](http://i1-news.softpedia-static.com/images/extra/LINUX/small/slw106news5.png "mint logo")Mint: in [graysky's PPA](https://github.com/graysky2/profile-sync-daemon#mint-users).
* ![logo](http://s29.postimg.org/ofjg812er/nixos_logo_small.png "nixos logo")NixOS: Available through the [psd service](https://github.com/graysky2/profile-sync-daemon#nixos-users).
* ![logo](http://s30.postimg.org/auetslwfh/opensuse.jpg "open suse")OpenSUSE: packaged by [Overman79](https://build.opensuse.org/package/show/home:ZaWertun:utility/profile-sync-daemon).
* ![logo](http://www.monitorix.org/imgs/ubuntu.png "ubuntu logo")Ubuntu: in [graysky's PPA](https://github.com/graysky2/profile-sync-daemon#ubuntu-users).
* ![logo](http://s23.postimg.org/5pabe2o5z/void_logo_transparent.png "void logo")Void: in the Void [repos](https://github.com/xtraeme/xbps-packages/tree/master/srcpkgs/profile-sync-daemon).

###Debian Users
Tested on Debian 7.7 (wheezy) and 8.0 (jessie). To add the PPA (personal package archive) to your Debian system; do the following as the root user:

    echo "deb http://ppa.launchpad.net/graysky/utils/ubuntu trusty main" > /etc/apt/sources.list.d/graysky.list
    echo "deb-src http://ppa.launchpad.net/graysky/utils/ubuntu trusty main" >> /etc/apt/sources.list.d/graysky.list
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys F0E0B4E7
    apt-get update
    apt-get install profile-sync-daemon

###Fedora Users
Since June of 2013, Profile-sync-daemon is in the official repo. [Reference](https://bugzilla.redhat.com/show_bug.cgi?id=968253).

    sudo yum install profile-sync-daemon

###Mint Users
To add the PPA (personal package archive) to your Mint system (tested on 14.1), and to install psd:

    sudo add-apt-repository ppa:graysky/utils
    sudo apt-get update
    sudo apt-get install profile-sync-daemon

###NixOS Users
Currently, you need to be tracking `nixos-unstable`:

    nix-channel --add http://nixos.org/channels/nixos-unstable nixos
    nixos-rebuild switch --upgrade

The NixOS module looks for a `services.psd` attribute set in your
`configuration.nix` (run `nixos-help` for all options):

      services.psd = {
        enable = true;
        users = [ "user42" "other_user" ];      # At least one is required
        browsers = [ "firefox" "chromium" ];    # Leave blank to enable all
        useOverlayFS = true; # set to true to enable overlayfs or set to false to use the default sync mode
      };

Then rebuild your system configuration with `nixos-rebuild switch`.

###Ubuntu Users
To add the PPA (personal package archive) to your Ubuntu system (packages available for Lucid and newer), and to install psd:

    sudo add-apt-repository ppa:graysky/utils
    sudo apt-get update
    sudo apt-get install profile-sync-daemon

###Other Distros
If you are interested in packaging psd for your favorite distro, please contact me.
