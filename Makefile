VERSION = 6.55
PN = profile-sync-daemon

PREFIX ?= /usr
INITDIR_SYSTEMD = /usr/lib/systemd/user
BINDIR = $(PREFIX)/bin
SHAREDIR = $(PREFIX)/share/psd
MANDIR = $(PREFIX)/share/man/man1
ZSHDIR = $(PREFIX)/share/zsh/site-functions
CONTRIBDIR = $(SHAREDIR)/contrib

RM = rm
SED = sed
INSTALL = install -p
INSTALL_PROGRAM = $(INSTALL) -m755
INSTALL_SCRIPT = $(INSTALL) -m755
INSTALL_DATA = $(INSTALL) -m644
INSTALL_DIR = $(INSTALL) -d
RSYNC = rsync -a
Q = @

common/$(PN): common/$(PN).in
	$(Q)echo -e '\033[1;32mSetting version\033[0m'
	$(Q)$(SED) 's/@VERSION@/'$(VERSION)'/' common/$(PN).in > common/$(PN)

install-bin: common/$(PN)
	$(Q)echo -e '\033[1;32mInstalling main script...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(BINDIR)"
	$(INSTALL_PROGRAM) common/$(PN) "$(DESTDIR)$(BINDIR)/$(PN)"
	$(INSTALL_PROGRAM) common/psd-overlay-helper "$(DESTDIR)$(BINDIR)/psd-overlay-helper"
	$(INSTALL_PROGRAM) common/psd-suspend-sync "$(DESTDIR)$(BINDIR)/psd-suspend-sync"
	ln -sf $(PN) "$(DESTDIR)$(BINDIR)/psd"
	$(INSTALL_DIR) "$(DESTDIR)$(ZSHDIR)"
	$(INSTALL_DATA) common/zsh-completion "$(DESTDIR)/$(ZSHDIR)/_psd"
	$(INSTALL_DIR) "$(DESTDIR)$(SHAREDIR)/browsers"
	$(INSTALL_DATA) common/psd.conf "$(DESTDIR)$(SHAREDIR)/psd.conf"
	$(INSTALL_DATA) common/browsers/* "$(DESTDIR)$(SHAREDIR)/browsers"
	$(INSTALL_DIR) "$(DESTDIR)$(SHAREDIR)/contrib"
	$(INSTALL_DATA) contrib/* "$(DESTDIR)$(SHAREDIR)/contrib"

install-man:
	$(Q)echo -e '\033[1;32mInstalling manpage...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(MANDIR)"
	$(INSTALL_DATA) doc/psd.1 "$(DESTDIR)$(MANDIR)/psd.1"
	$(INSTALL_DATA) doc/psd-overlay-helper.1 "$(DESTDIR)$(MANDIR)/psd-overlay-helper.1"
	ln -sf psd.1 "$(DESTDIR)$(MANDIR)/$(PN).1"

install-systemd:
	$(Q)echo -e '\033[1;32mInstalling systemd files...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(INITDIR_SYSTEMD)"
	$(INSTALL_DATA) init/psd.service "$(DESTDIR)$(INITDIR_SYSTEMD)/psd.service"
	$(INSTALL_DATA) init/psd-resync.service "$(DESTDIR)$(INITDIR_SYSTEMD)/psd-resync.service"
	$(INSTALL_DATA) init/psd-resync.timer "$(DESTDIR)$(INITDIR_SYSTEMD)/psd-resync.timer"

install: install-bin install-man install-systemd

uninstall-bin:
	$(RM) "$(DESTDIR)$(BINDIR)/$(PN)"
	$(RM) "$(DESTDIR)$(BINDIR)/psd"
	$(RM) "$(DESTDIR)$(ZSHDIR)/_psd"
	$(RM) "$(DESTDIR)$(BINDIR)/psd-overlay-helper"
	$(RM) "$(DESTDIR)$(BINDIR)/psd-suspend-sync"
	$(RM) "$(DESTDIR)$(SHAREDIR)/psd.conf"
	$(RM) -rf "$(DESTDIR)$(SHAREDIR)/browsers"
	$(RM) -rf "$(DESTDIR)$(SHAREDIR)/contrib"
	rmdir "$(DESTDIR)$(SHAREDIR)"

uninstall-man:
	$(RM) -f "$(DESTDIR)$(MANDIR)/$(PN).1"
	$(RM) -f "$(DESTDIR)$(MANDIR)/psd.1"
	$(RM) -f "$(DESTDIR)$(MANDIR)/psd-overlay-helper.1"

uninstall-systemd:
	$(RM) "$(DESTDIR)$(INITDIR_SYSTEMD)/psd.service"
	$(RM) "$(DESTDIR)$(INITDIR_SYSTEMD)/psd-resync.service"
	$(RM) "$(DESTDIR)$(INITDIR_SYSTEMD)/psd-resync.timer"

uninstall: uninstall-bin uninstall-man uninstall-systemd

clean:
	$(RM) -f common/$(PN)

.PHONY: install-bin install-man install-systemd install uninstall-bin uninstall-man uninstall-systemd uninstall clean
