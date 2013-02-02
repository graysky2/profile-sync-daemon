#Profile-sync-daemon
Profile-sync-daemon (psd) is a tiny pseudo-daemon designed to manage your browser's profile in tmpfs and to periodically sync it back to your physical disc (HDD/SSD). This is accomplished via a symlinking step and an innovative use of rsync to maintain back-up and synchronization between the two. One of the major design goals of psd is a completely transparent user experience.

##Links to Distro-Provided Packages
* Arch Linux via AUR Package: https://aur.archlinux.org/packages/profile-sync-daemon
* Chakra Linux via CCR Package: http://chakra-linux.org/ccr/packages.php?ID=3388
* Gentoo via Ebuild: http://packages.gentoo.org/package/www-misc/profile-sync-daemon

If you are interested in packaging psd for your favorite distro, please contact me and I will add the link here.

##Documentation
Consult the man page or the wiki page: https://wiki.archlinux.org/index.php/Profile-sync-daemon

##File Descriptions

<table>
<tr>
<th>File</th><th>Description</th><th>Importance</th>
</tr>
<tr>
<td>CHANGELOG</td><td>Project changelog.</td><td>Optional</td>
</tr>
<tr>
<td>README-for_other_distros</td><td>Information to run psd distros that are not Arch Linux.</td><td>Optional</td>
</tr>
<tr>
<td>VERSION_4_WARNING</td><td>Manual steps to follow if users are running psd version before version 4 and wish to update.</td><td>Must read</td>
</tr>
<tr>
<td>profile-sync-daemon</td><td>Main script. Place it in /usr/bin</td><td>Required</td>
</tr>
<tr>
<td>psd.conf</td><td>Config file. Place it in /etc</td><td>Required</td>
</tr>
<tr>
<td>psd.cron.hourly</td><td>Default cronjob. Place it in /etc/cron.hourly</td><td>Optional</td>
</tr>
<tr>
<td>psd.debian.init.example</td><td>An example init script for Debian users.</td><td>Optional</td>
</tr>
<tr>
<td>psd.manpage</td><td>Example manpage for psd. Place it in /usr/share/man/man1</td><td>Optional</td>
</tr>
<tr>
<td>psd.service</td><td>Example systemd service file. Place it in /usr/lib/systemd/system</td><td>Optional</td>
</tr>
</table>
