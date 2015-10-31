VERSION = 6.16
PN = profile-sync-daemon

PREFIX ?= /usr
INITDIR_SYSTEMD = /usr/lib/systemd/user
BINDIR = $(PREFIX)/bin
SHAREDIR = $(PREFIX)/share/psd
MANDIR = $(PREFIX)/share/man/man1
ZSHDIR = $(PREFIX)/share/zsh/site-functions

# set to anything except 0 to enable manpage compression
COMPRESS_MAN = 1

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
	ln -s $(PN) "$(DESTDIR)$(BINDIR)/psd"
	$(INSTALL_DIR) "$(DESTDIR)$(ZSHDIR)"
	$(INSTALL_DATA) common/zsh-completion "$(DESTDIR)/$(ZSHDIR)/_psd"
	$(INSTALL_DIR) "$(DESTDIR)$(SHAREDIR)/browsers"
	$(INSTALL_DATA) common/psd.conf "$(DESTDIR)$(SHAREDIR)/psd.conf"
	cp common/browsers/* "$(DESTDIR)$(SHAREDIR)/browsers"

install-man:
	$(Q)echo -e '\033[1;32mInstalling manpage...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(MANDIR)"
	$(INSTALL_DATA) doc/psd.1 "$(DESTDIR)$(MANDIR)/psd.1"
ifneq ($(COMPRESS_MAN),0)
	gzip -9 "$(DESTDIR)$(MANDIR)/psd.1"
	ln -s psd.1.gz "$(DESTDIR)$(MANDIR)/$(PN).1.gz"
else
	ln -s psd.1 "$(DESTDIR)$(MANDIR)/$(PN).1"
endif

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
	$(RM) "$(DESTDIR)$(SHAREDIR)/psd.conf"
	$(RM) -rf "$(DESTDIR)$(SHAREDIR)/browsers"
	rmdir "$(DESTDIR)$(SHAREDIR)"

uninstall-man:
	$(RM) -f "$(DESTDIR)$(MANDIR)/$(PN).1.gz"
	$(RM) -f "$(DESTDIR)$(MANDIR)/psd.1.gz"
	$(RM) -f "$(DESTDIR)$(MANDIR)/$(PN).1"
	$(RM) -f "$(DESTDIR)$(MANDIR)/psd.1"

uninstall-systemd:
	$(RM) "$(DESTDIR)$(INITDIR_SYSTEMD)/psd.service"
	$(RM) "$(DESTDIR)$(INITDIR_SYSTEMD)/psd-resync.service"
	$(RM) "$(DESTDIR)$(INITDIR_SYSTEMD)/psd-resync.timer"

uninstall: uninstall-bin uninstall-man uninstall-systemd

clean:
	$(RM) -f common/$(PN)

.PHONY: install-bin install-man install-systemd install uninstall-bin uninstall-man uninstall-systemd uninstall clean
