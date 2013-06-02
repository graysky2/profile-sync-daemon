VERSION = 5.35.2
PN = profile-sync-daemon

PREFIX ?= /usr
CONFDIR = /etc
CONFDIR_OPENRC = /etc/conf.d
CRONDIR = /etc/cron.hourly
INITDIR_SYSTEMD = /usr/lib/systemd/system
INITDIR_OPENRC = /etc/init.d
INITDIR_UPSTART = /etc/init.d
BINDIR = $(PREFIX)/bin
DOCDIR = $(PREFIX)/share/doc/$(PN)-$(VERSION)
MANDIR = $(PREFIX)/share/man/man1

# set to anything except 0 to enable manpage compression
COMPRESS_MAN = 1

RM = rm
SED = sed
INSTALL = install
INSTALL_PROGRAM = $(INSTALL) -m755
INSTALL_SCRIPT = $(INSTALL) -m755
INSTALL_DATA = $(INSTALL) -m644
INSTALL_DIR = $(INSTALL) -d

Q = @

common/$(PN): common/$(PN).in
	$(Q)echo -e '\033[1;32mSetting version\033[0m'
	$(Q)$(SED) 's/@VERSION@/'$(VERSION)'/' common/$(PN).in > common/$(PN)

help: install

install-bin: common/$(PN)
	$(Q)echo -e '\033[1;32mInstalling main script...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(BINDIR)"
	$(INSTALL_PROGRAM) common/$(PN) "$(DESTDIR)$(BINDIR)/$(PN)"
	ln -s $(PN) "$(DESTDIR)$(BINDIR)/psd"

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

install-cron:
	$(Q)echo -e '\033[1;32mInstalling cronjob...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(CRONDIR)"
	$(INSTALL_SCRIPT) common/psd.cron.hourly "$(DESTDIR)$(CRONDIR)/psd-update"

install-cron-openrc:
	$(Q)echo -e '\033[1;32mInstalling cronjob (openrc)...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(CRONDIR)"
	$(INSTALL_SCRIPT) common/psd.cron.hourly.openrc "$(DESTDIR)$(CRONDIR)/psd-update"

install-openrc:
	$(Q)echo -e '\033[1;32mInstalling openrc files...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(INITDIR_OPENRC)"
	$(INSTALL_DIR) "$(DESTDIR)$(CONFDIR_OPENRC)"
	$(INSTALL_SCRIPT) init/psd.openrc "$(DESTDIR)$(INITDIR_OPENRC)/psd"
	$(INSTALL_DATA) common/psd.conf "$(DESTDIR)$(CONFDIR_OPENRC)/psd"

install-systemd:
	$(Q)echo -e '\033[1;32mInstalling systemd files...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(CONFDIR)"
	$(INSTALL_DIR) "$(DESTDIR)$(INITDIR_SYSTEMD)"
	$(INSTALL_DATA) common/psd.conf "$(DESTDIR)$(CONFDIR)/psd.conf"
	$(INSTALL_DATA) init/psd.service "$(DESTDIR)$(INITDIR_SYSTEMD)/psd.service"
	$(INSTALL_DATA) init/psd-resync.service "$(DESTDIR)$(INITDIR_SYSTEMD)/psd-resync.service"
	$(INSTALL_DATA) init/psd-resync.timer "$(DESTDIR)$(INITDIR_SYSTEMD)/psd-resync.timer"

install-upstart:
	$(Q)echo -e '\033[1;32mInstalling upstart files...\033[0m'
	$(INSTALL_DIR) "$(DESTDIR)$(CONFDIR)"
	$(INSTALL_DIR) "$(DESTDIR)$(INITDIR_UPSTART)"
	$(INSTALL_DATA) common/psd.conf "$(DESTDIR)$(CONFDIR)/psd.conf"
	$(SED) -i -e 's/#DAEMON_FILE="\/run\/psd"/DAEMON_FILE="\/var\/run\/psd"/' \
		-i -e 's/#VOLATILE="\/tmp"/VOLATILE="\/run\/shm"/' "$(DESTDIR)$(CONFDIR)/psd.conf"
	$(INSTALL_SCRIPT) init/psd.upstart "$(DESTDIR)$(INITDIR_UPSTART)/psd"

install-openrc-all: install-bin install-man install-cron-openrc install-openrc

install-systemd-all: install-bin install-man install-systemd

install-upstart-all: install-bin install-man install-cron install-upstart

install:
	$(Q)echo "run one of the following:"
	$(Q)echo "  make install-openrc-all (openrc based systems)"
	$(Q)echo "  make install-systemd-all (systemd based systems)"
	$(Q)echo "  make install-upstart-all (upstart based systems)"
	$(Q)echo
	$(Q)echo "or check out the Makefile for specific rules"

uninstall-bin:
	$(RM) "$(DESTDIR)$(BINDIR)/$(PN)"
	$(RM) "$(DESTDIR)$(BINDIR)/psd"

uninstall-man:
	$(RM) -f "$(DESTDIR)$(MANDIR)/$(PN).1.gz"
	$(RM) -f "$(DESTDIR)$(MANDIR)/psd.1.gz"
	$(RM) -f "$(DESTDIR)$(MANDIR)/$(PN).1"
	$(RM) -f "$(DESTDIR)$(MANDIR)/psd.1"

uninstall-cron:
	$(RM) "$(DESTDIR)$(CRONDIR)/psd-update"

uninstall-openrc:
	$(RM) "$(DESTDIR)$(INITDIR_OPENRC)/psd"
	$(RM) "$(DESTDIR)$(CONFDIR_OPENRC)/psd"

uninstall-systemd:
	$(RM) "$(DESTDIR)$(CONFDIR)/psd.conf"
	$(RM) "$(DESTDIR)$(INITDIR_SYSTEMD)/psd.service"
	$(RM) "$(DESTDIR)$(INITDIR_SYSTEMD)/psd-resync.service"
	$(RM) "$(DESTDIR)$(INITDIR_SYSTEMD)/psd-resync.timer"

uninstall-upstart:
	$(RM) "$(DESTDIR)$(CONFDIR)/psd.conf"
	$(RM) "$(DESTDIR)$(INITDIR)/psd"

uninstall-openrc-all: uninstall-bin uninstall-man uninstall-cron uninstall-openrc

uninstall-systemd-all: uninstall-bin uninstall-man uninstall-systemd

uninstall-upstart-all: uninstall-bin uninstall-man uninstall-cron uninstall-upstart

uninstall:
	$(Q)echo "run one of the following:"
	$(Q)echo "  make uninstall-openrc-all (openrc based systems)"
	$(Q)echo "  make uninstall-systemd-all (systemd based systems)"
	$(Q)echo "  make uninstall-upstart-all (upstart based systems)"
	$(Q)echo
	$(Q)echo "or check out the Makefile for specific rules"

clean:
	$(RM) common/$(PN)

.PHONY: help install-bin install-man install-cron install-cron-openrc install-openrc install-systemd install-upstart install-openrc-all install-systemd-all install-upstart-all install uninstall-bin uninstall-man uninstall-cron uninstall-openrc uninstall-systemd uninstall-upstart uninstall-openrc-all uninstall-systemd-all uninstall-upstart-all uninstall clean
