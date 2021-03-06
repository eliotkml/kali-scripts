# kali-scripts reborn to Makefile
#
PROJECT := kali-scripts
CC      := gcc
EUID    := $(shell id -u -r)
DESTDIR ?=/usr
PREFIX ?= $(DESTDIR)
TMPDIR=/tmp/kali-scripts
CRDADIR=/lib/crda
CRDADB=${CRDADIR}/regulatory.bin
TOP ?= $(shell pwd)
# THIS := $(dir $(lastword $(MAKEFILE_LIST)))
THIS := ${TOP}/Makefile
ROOT_DIR := ${CURDIR}
# ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
# KERNEL=4.2-1	# Release of drivers for kernel 4.2	a year ago
KERNEL=4.4-1
# KERNEL=4.7.4-experimental-1	#Add experimental release for 4.7.y kernels	2 months ago
MODWIFI_RELEASE=modwifi-${KERNEL}.tar.gz
MODWIFI_URL=https://github.com/vanhoefm/modwifi/raw/master/releases/${MODWIFI_RELEASE}
.DEFAULT_GOAL := help
.PHONY: help clean archivers 32bit common-tools deps wifi wireless-db reaver
.PHONY: pixiewps wifite lorcon pyrit horst penetrator aircrack-ng radius-wpe hotspotd
.PHONY: sshd-root sshd-keys sshd-forwarding sshd install-zsh configure-zsh
.PHONY: bluetooth ism signal firmware crossdev openwrt hardware

# Macros
.CLEAR=\x1b[0m
.BOLD=\x1b[01m
.RED=\x1b[31;01m
.GREEN=\x1b[32;01m
.YELLOW=\x1b[33;01m

# Check for root
check:
ifneq ($(EUID),0)
	@echo "Please run as root user"
	@exit 1
endif

# Re-usable target for yes no prompt. Usage: make .prompt-yesno message="Is it yes or no?"
# Will exit with error if not yes
.prompt-yesno2:
	@exec 9<&0 0</dev/tty
	echo "$(message) [Y]:"
	[[ -z $$FOUNDATION_NO_WAIT ]] && read -rs -t5 -n 1 yn;
	exec 0<&9 9<&-
	[[ -z $$yn ]] || [[ $$yn == [yY] ]] && echo Y >&2 || (echo N >&2 && exit 1)

# Re-usable target for yes no prompt. Usage: make .prompt-yesno message="Is it yes or no?"
# Will exit with error if not yes
.prompt-yesno:
	@exec 8<&0 0</dev/tty
	@case "$(shell [[ ! -z $$FOUNDATION_NO_WAIT ]] && echo "Y" \
	        || (read -t5 -n1 -p "    > $(message) [Y]:" && echo $$REPLY))" in \
	   [nN]) echo -e "\n    > $(.YELLOW)[ABORTED]$(.CLEAR)" && exit 1 ;; \
  esac && echo -e ""
	([[ ! -z $$FOUNDATION_NO_WAIT ]] && \
		echo -e "    > $(.GREEN)[AUTO CONTINUING]$(.CLEAR)" || \
		echo -e "    > $(.GREEN)[CONTINUING]$(.CLEAR)")

define gitclone
	$(eval repo := $(TMPDIR)/$(shell basename $(1)))
	@if [ ! -d $(repo) ]; then git clone --recursive $(1) $(repo); fi;
endef


default: help;

##: list - list available make targets
list:
	@grep -v "#" Makefile|grep '^[^#.]*:$$'  | awk -F: '{ print $$1 }'

##: sshd - Regenerate SSH keys and allow password access
#sshd: sshd-root sshd-keys sshd-forwarding

##: deps - install dependecies                                 *
deps:	archivers common-tools

#: dev - install ALL development tools                         *
dev: archivers deps common-tools dev-vcs dev-python dev-net

#: wifi - install tools for Wi-Fi hacking                      *
wifi: wireless-db wireless-lorcon wireless-pyrit wireless-wifite wireless-penetrator

#: hardware - install hardware hacking tools                   *
hardware: dev hardware-generic hardware-signal

#: firmware - install firmware RE/DEBUG/MOD tools              *
firmware:	dev firmware-reverse firmware-crossdev firmware-avatar firmware-openwrt

#: wireless - install tools for ISM, WiFi, Bluetooth, NRF24XX  *
wireless: wifi bluetooth ism nrf24

#: wired - install everything for wired interfaces             *
wired: hardware firmware

#: all - install EVERYTHING                                    *
all: clean upgrade wireless wired

#: help - display callable targets                             *
help:
	@echo "\n\t`printf "\033[32m"`\t    .:[Kali Scripts reb0rn to Makefile]:.`printf "\033[0m"`"
	@echo "\t+--------------------------------------------------------------+"
		@egrep -o "^#: (.+)" [Mm]akefile  |sort| sed "s/#: /	*  `printf "\033[32m"`/"| sed "s/ - /`printf "\033[0m"` - /"
	@echo "\t+--------------------------------------------------------------+"
	@echo "\t\t`printf "\033[32m"`      greetz fly to all DC7499 community`printf "\033[0m"`"
	@echo "\t\t`printf "\033[32m"`           ~~-<  @090h 2016  >-~~`printf "\033[0m"`\n"

#: clean - cleanup source code and unused packages             *
clean:
	@echo "Cleaning packages"
	apt-get -y autoremove && apt-get -y clean
	@echo "Cleaning temp directory: $(TMPDIR)"
	@rm -rf $(TMPDIR)

#: upgrade - update and upgrade current system                 *
upgrade:
	apt-get update && apt-get upgrade -y

##: archivers - install archivers
archivers:
	@echo "installing archivers.."
	@apt-get -y install gzip bzip2 tar lzma arj lhasa p7zip-full cabextract unace  unrar zip unzip \
	sharutils uudeview mpack cabextract file-roller zlib1g zlib1g-dev liblzma-dev liblzo2-dev

##: 32bit - install 32 bit tools and libraries
32bit:
	@if [ `getconf LONG_BIT` != "64" ] ; then exit 1; fi
	@echo "64-bit OS detected. installing 32-bit libs..."
	dpkg --add-architecture i386
	apt-get update -y
	apt-get install -y libstdc++6:i386 libgcc1:i386 zlib1g:i386 libncurses5:i386

##: common-tools - install common tools
common-tools:
	@echo "installing common tools.."
	apt-get install -y terminator tmux htop iftop iotop mc screen curl wget


##: sshd - Configure SSHD                                      *
sshd:
	@echo "Configuring SSHD"
	make .prompt-yesno message="Enable root login via SSHD with password?" && make sshd-root
	make .prompt-yesno message="Do you want to install fresh sshd/ssh keys?" && make sshd-keys
	make .prompt-yesno message="Enable TCP/IP, X11 forwarding support" && make sshd-forwarding
	make .prompt-yesno message="Enable SSHD to start on boot?" && systemctl enable ssh
	systemctl restart ssh

##: sshd-root - Enable root login via SSHD with password auth
sshd-root:
	@echo "Enabling root login with password"
	sed -i 's/prohibit-password/yes/' /etc/ssh/sshd_config && systemctl restart ssh

##: sshd-keys - Regenerate SSH keys
sshd-keys:
	@echo "Removing old host keys.."
	rm -rf /etc/ssh/ssh_host_*
	@echo "Regenerating host keys.."
	dpkg-reconfigure openssh-server
	mkdir /etc/ssh/default_kali_keys
	mv /etc/ssh/ssh_host* /etc/ssh/default_kali_keys/
	dpkg-reconfigure openssh-server
	@echo "please make sure that those keys differ"
	md5sum /etc/ssh/default_kali_keys/*
	md5sum /etc/ssh/ssh_host*
	service ssh try-restart
	ssh-keygen -t rsa -b 2048

##: sshd-forwarding - Allow TCP/IP, X11 forwarding.
sshd-forwarding:
	sed -i -e 's/\#X11Forwarding no/X11Forwarding yes/' /etc/ssh/sshd_config
	sed -i -e 's/\#X11DisplayOffset/X11DisplayOffset/' /etc/ssh/sshd_config
	sed -i -e 's/\#X11UseLocalhost/X11UseLocalhost/' /etc/ssh/sshd_config
	sed -i -e 's/\#AllowTcpForwarding/AllowTcpForwarding/' /etc/ssh/sshd_config

##: zsh - install  ZSH
install-zsh:
	@echo "installing ZSH.."
	apt-get install -y zsh

# .ONESHELL:
# SHELL = $(which zsh)
# .SHELLFLAGS = -c
##: configure-zsh - Configure ZSH
# https://www.gnu.org/software/make/manual/html_node/One-Shell.html
configure-zsh: install-zsh
	@echo "Configuring ZSH.."
	# git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
	# setopt EXTENDED_GLOB
	# for rcfile in "${ZDOTDIR:-$HOME}"/.zprezto/runcoms/^README.md(.N); do \
	# ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}" \
	# done
	# @echo "Set Zsh as your default shell"
	# chsh -s /bin/zsh
	# wget "https://wiki.thc.org/BlueMaho?action=AttachFile&do=get&target=bluemaho_v090417.tgz"

##: dev-vcs - install VCS (git, hg,cvs)
dev-vcs:
	apt-get install -y git subversion mercurial

##: dev-build - install build tools and environment
dev-build:
	@echo "installing development tools and environment"
	@apt-get install -y cmake cmake-data module-assistant build-essential patch g++ pkg-config automake autoconf \
	gcc gcc-multilib dkms patchutils strace wdiff libtool bison gawk flex gettext \
	linux-headers-`uname -r` kernel-package  linux-source \
	libbz2-dev zlib1g-dev fakeroot ncurses-dev libncurses5-dev libreadline6 libreadline6-dev \
	libyaml-dev libxslt1-dev libxml2-dev libxslt-dev libc6-dev libmagickcore-dev libmagick++-dev libmagickwand-dev

##: dev-net - install tools for network development
dev-net:
	@echo "installing network libs"
	apt-get install -y python-scapy libpcap-dev libpcap0.8 libpcap0.8-dev \
	libnetfilter-queue-dev libnl-genl-3-dev libssh2-1-dev

##: dev-crypto - install libs for crypto
dev-crypto:
	@echo "installing crypto libs"
	apt-get install -y openssl libssl-dev python-m2crypto libgcrypt20 libgcrypt20-dev cracklib-runtime

##: dev-crypto - install libs for DB
dev-db:
	@echo "installing db libs"
	apt-get install -y libsqlite3-dev sqlite3 libmysqlclient-dev

#: python - install python developer environment               *
python: dev-python
dev-python:	dev-vcs dev-db dev-crypto
	@echo "installing pyenv, pip and other python modules"
	apt-get install -y python-dev bpython python-pip python-twisted python-shodan  \
	python-virtualenv python-pygments python-tornado python-sqlalchemy python-lxml python-pymongo \
	python-gnuplot python-matplotlib python-scipy python-requests python-gevent \
	python-numpy python-gi-dev python-psycopg2 swig doxygen python-lzma \
	python-opengl python-qt4 python-qt4-gl libqt4-opengl python-pyqtgraph python-pyside \
	python3 python3-pip
	pip install cookiecutter
	@if [ ! -d ~/.pyenv ]; then \
		curl -L https://raw.githubusercontent.com/yyuu/pyenv-installer/master/bin/pyenv-installer | bash ; \
	else \
		echo "PyEnv already installed"; \
	fi;

##: wireless-generic - install generic WiFi hacking tools
wireless-generic:
	@echo "installing WiFi tools and dependecies"
	apt-get install -y kali-linux-wireless aircrack-ng kismet kismet-plugins giskismet horst wavemon rfkill \
	hostapd dnsmasq iw tshark horst linssid cupid-wpasupplicant cupid-hostapd

#: wireless-db - install patched wireless-db                   *
wireless-db: dev wireless-generic
	@echo "Cloning repos wireless-db repos."
	$(call gitclone,https://github.com/0x90/crda-ct)
	$(call gitclone,https://github.com/0x90/wireless-regdb)
	@echo "Building and installing deps for building wireless-db"
	$(MAKE) -C $(repo) && install ${TMPDIR}/wireless-regdb/regulatory.bin ${CRDADB}
	@echo "Copying certs.."
	install ${TMPDIR}/wireless-regdb/root.key.pub.pem ${TMPDIR}/crda-ct/pubkeys/
	install ${CRDADIR}/pubkeys/benh@debian.org.key.pub.pem ${TMPDIR}/crda-ct/pubkeys/
	@echo "Building and installing CRDA"
	cd ${TMPDIR}/crda-ct && export REG_BIN=${CRDADB} && make && make install

##: reaver - install fresh version of reaver
wireless-reaver:
	$(call gitclone,https://github.com/t6x/reaver-wps-fork-t6x)
	cd $(repo)/src/ && ./configure --prefix=$(PREFIX) && make && make install

##: pixiewps - install fresh version of reaver
wireless-pixiewps:
	$(call gitclone,https://github.com/wiire/pixiewps)
	cd $(repo)/src/ && make && make install

#: wifite - install correct version of wifite                  *
wifite: wireless-wifite
wireless-wifite:	deps reaver pixiewps
	$(call gitclone,https://github.com/derv82/wifite)
	install -m 755 $(repo)/wifite.py /usr/bin/wifite-old
	$(call gitclone,https://github.com/aanarchyy/wifite-mod-pixiewps)
	install -m 755 $(repo)/wifite-ng /usr/bin/wifite-ng

#: lorcon - install Lorcon library with python bindings        *
lorcon:	wireless-lorcon
wireless-lorcon:
	$(call gitclone,https://github.com/0x90/lorcon)
	@echo "installing Lorcon from $(repo)"
	@cd $(repo) && ./configure --prefix=$(PREFIX) && make && make install
	@echo "installing pylorcon2 bindings"
	@cd $(repo)/pylorcon2 && python setup.py build && python setup.py install

#: pyrit - install latest version of Pyrit from sources        *
wireless-pyrit:	deps
	@echo "installing Pyrit"
	$(call gitclone,https://github.com/JPaulMora/Pyrit)
	cd $(repo) && python setup.py clean && python setup.py build && python setup.py install

##: horst - install horst from source
wireless-horst:
	$(call gitclone,git://br1.einfach.org/horst)
	cd $(repo) && make && install -m 755 horst /usr/bin/horst # cp horst /usr/bin

#: penetrator - install penetrator-wps from source             *
penetrator: wireless-penetrator
wireless-penetrator:
	$(call gitclone,https://github.com/xXx-stalin-666-money-xXx/penetrator-wps)
	cd $(repo) && ./install.sh;

#: modwifi - install modwifi drivers and firmware
modwifi:	wireless-modwifi-drivers
wireless-modwifi-drivers:
	mkdir -p ${TMPDIR}/modwifi
	cd ${TMPDIR}/modwifi && wget ${MODWIFI_URL} && tar -xf modwifi-*.tar.gz
	# tar -xf ${MODWIFI_RELEASE}	#tar -xf modwifi-*.tar.gz
	cd ${TMPDIR}/modwifi/drivers && make defconfig-ath9k-debug && make && make install && cd ..
	# Note: the location and name of firmware files on your machine may be different
	compgen -G /lib/firmware/ath9k_htc/*backup || for FILE in /lib/firmware/ath9k_htc/*; do sudo cp $FILE ${FILE}_backup; done
	sudo cp target_firmware/htc_7010.fw /lib/firmware/ath9k_htc/htc_7010-1.4.0.fw
	sudo cp target_firmware/htc_9271.fw /lib/firmware/ath9k_htc/htc_9271-1.4.0.fw

	sudo apt-get install g++ libssl-dev libnl-3-dev libnl-genl-3-dev
	cd tools && make all

##: wireless-radius-wpe - install Radius-WPE
wireless-radius-wpe:
	@echo hostapd-WPE

#: hotspotd - install hotspotd to easy AP configuration        *
hotspotd: wireless-hotspotd
wireless-hotspotd:
	$(call gitclone,https://github.com/0x90/hotspotd)
	cd $(repo) && sudo python2 setup.py install

#: bluetooth - install bluetooth hacking tools                 *
bluetooth:
	@echo "installing deps for bluetooth hacking"
	apt-get install -y anyremote redfang spooftooph python-bluez obexfs bluewho btscanner \
	bluelog libbluetooth-dev spectools libncurses-dev libpcre3-dev \
	spooftooph sakis3g ubertooth gpsd  bluesnarfer bluez-tools bluewho \
	wireshark wireshark-dev libwireshark-dev
	# apt-get install -y libopenobex1:i386 libopenobex1-dev:i386 libbluetooth-dev:i386

ism-deps:
	@echo "installing ISM dependencies"
	apt-get install -y sdcc binutils make

#: ism - install ISM hacking tools                             *
ism: ism-deps
	@echo "installing ISM hacking tools for 433/866/915Mhz"
	apt-get install rfcat libusb-1.0-0 python-usb
	# @echo "installing ISM hacking tools for 433/866/915Mhz"
	# $(call gitclone,https://github.com/0x90/ism-arsenal)
	@echo "RFCat"
	hg clone https://bitbucket.org/atlas0fd00m/rfcat ${TMPDIR}/ism-arsenal/rfcat
	sudo cp ${TMPDIR}/ism-arsenal/rfcat/etc/udev/rules.d/20-rfcat.rules /etc/udev/rules.d && sudo udevadm control --reload-rules
	cd ${TMPDIR}/ism-arsenal/rfcat/firmware && ./build
	# "make testgoodfet" will read info from your dongle using the GoodFET. you should see something like:
	#
	# SmartRF not found for this chip. Ident CC1111/r1103/ps0x0400 Freq 0.000 MHz RSSI 00
	# "make backupdongle" will read the current firmware from your dongle to the file .../bins/original-dongle-hex.backup. ("make restoredongle") to revert to the original firmware.
	#
	# "make clean installRfCatChronosDongle" will clean, build, and install the RfCat (appFHSSNIC.c) firmware for a Chronos dongle.
	#
	# "make clean installRfCatDonsDongle" will clean, build, and install the RfCat (appFHSSNIC.c) firmware for a cc1111emk.
	# for EMK/DONSDONGLE:
	# make installdonsbootloader
	# for CHRONOS:
	# make installchronosbootloader
	# for YARDSTICKONE:
	# make installys1bootloader

nrf24-deps:
	@echo "Cloning NRF24 arsenal"
	$(call gitclone,https://github.com/0x90/nrf24-arsenal)
	@echo "installing NRF24 dependencies"
	apt-get install -y sdcc binutils
	pip install -U pip
	pip install -U -I pyusb
	pip install -U platformio

nrf24-firmware:
	# https://github.com/BastilleResearch/nrf-research-firmware
	@echo "Build research firmware for nRF24LU1+"
	$(MAKE) -C ${TMPDIR}/nrf24-arsenal/mousejack/nrf-research-firmware
	@echo "Build firmware for Crazyradio"
	$(MAKE) -C ${TMPDIR}/nrf24-arsenal/crazyradio-firmware
	# TODO: add support for Crazyradio PA via make CRPA=1

## Flashing the Firmware
nrf24-flash:
	@if $(MAKE) -s -f $(THIS) .prompt-yesno message="Do you want to flash Research firmware over USB? "; then \
	  $(MAKE) -C ${TMPDIR}/nrf24-arsenal/mousejack/nrf-research-firmware install; \
	fi;
	@if make .prompt-yesno message="Do you want to flash Crazyradio firmware over USB? "; then \
	  cd ${TMPDIR}/nrf24-arsenal/crazyradio-firmware/usbtools ; \
		python ../usbtools/launchBootloader.py; \
		python ../usbtools/nrfbootload.py flash bin/cradio.bin; \
	fi;

nrf24-flash-research:
	$(MAKE) -C ${TMPDIR}/nrf24-arsenal/mousejack/nrf-research-firmware install

nrf24-flash-logitech:
	$(MAKE) -C ${TMPDIR}/nrf24-arsenal/mousejack/nrf-research-firmware logitech_install

nrf24-flash-crazyradio:
	cd ${TMPDIR}/nrf24-arsenal/crazyradio-firmware/usbtools && \
	python launchBootloader.py && \
	python nrfbootload.py flash bin/cradio.bin

#: nrf24 - Nordic Semiconductor NRF24XXX hacking tools         *
nrf24:	nrf24-deps
	@make nrf24-firmware
	@echo "Use make nrf24-flash-research to flash proper firmware"

##: firmware-reverse - install firmware RE/MOD tools
firmware-reverse:	dev
	apt-get install firmware-mod-kit
	@echo "install sasquatch to extract non-standard SquashFS images"
	$(call gitclone,https://github.com/devttys0/sasquatch)
	cd $(repo) && ./build.sh  # make && sudo make install
	@echo "installing binwalk"
	$(call gitclone,https://github.com/devttys0/binwalk)
	cd $(repo) && ./deps.sh && pip install .
	@echo "installing firmadyne"
	$(call gitclone,https://github.com/firmadyne/firmadyne)
	@echo "installing firmwalker"
	$(call gitclone,https://github.com/craigz28/firmwalker)

##: avatar - install Avatar symbol execution
firmware-avatar:	deps dev
	@echo "install all build-deps"
	apt-get build-dep qemu llvm
	apt-get install liblua5.1-dev libsdl1.2-dev libsigc++-2.0-dev binutils-dev python-docutils python-pygments nasm
	@echo "Get the source code from github"
	$(call gitclone,https://github.com/eurecom-s3/s2e)
	@echo "It will take some time to build..."
	cd $(repo) && mkdir build && cd build && make -j -f ../s2e/Makefile
	@echo "installing Avatar module from github"
	# http://llvm.org/devmtg/2014-02/slides/bruno-avatar.pdf
	pip3 install git+https://github.com/eurecom-s3/avatar-python.git#egg=avatar
	# install all build-deps
	apt-get build-dep openocd
	git clone --recursive git://git.code.sf.net/p/openocd/code $(TMPDIR)/openocd
	cd $(TMPDIR)/openocd && autoreconf -i && ./configure --prefix=$(PREFIX) && make -j && make install

##: crossdev - install cross platfrorm dev tools
firmware-crossdev:	deps
	# http://www.emdebian.org/crosstools.html
	@echo "installing Emdebian, xapt"
	apt-get install emdebian-archive-keyring xapt -y
	# sudo apt-get install gcc-msp430 binutils-msp430 msp430-libc msp430mcu mspdebug

	# apt_add_source emdebian
	# cp -f "files/etc/emdebian.list" /etc/apt/sources.list.d/emdebian.list && apt-get update -y
	echo "deb http://ftp.us.debian.org/debian/ squeeze main" > /etc/apt/sources.list.d/emdebian.list
	echo "deb http://www.emdebian.org/debian/ squeeze main" >> /etc/apt/sources.list.d/emdebian.list
	echo "deb http://www.emdebian.org/debian/ oldstable main" >> /etc/apt/sources.list/emdebian.list
	apt-get update -y
	@echo "installing GCC-4.4 for mips, mipsel"
	apt-get install -y linux-libc-dev-mipsel-cross libc6-mipsel-cross libc6-dev-mipsel-cross \
	binutils-mipsel-linux-gnu gcc-4.4-mipsel-linux-gnu g++-4.4-mipsel-linux-gnu
	apt-get install -y linux-libc-dev-mips-cross libc6-mips-cross libc6-dev-mips-cross \
	binutils-mips-linux-gnu gcc-4.4-mips-linux-gnu g++-4.4-mips-linux-gnu -y

##: openwrt - install openwrt hacking tools
firmware-openwrt:	deps
	@echo "installing OpenWRT"


##: hardware - install generic hardware hacking tools
hardware-generic:	deps dev
	@echo "installing hardware hacking tools"
	apt-get install -y ftdi-eeprom libftdi1 python-ftdi1 python3-ftdi1 minicom \
	python-serial cutecom libftdi-dev skyeye flashrom libusb-1.0-0-dev \
	arduino esptool # openocd

##: hardware-signal - install signal analysis tools
hardware-signal:
	# TODO: OLS install
	apt-get install -y libsigrok0-dev sigrok-cli libsigrokdecode0-dev autoconf-archive \
	libglib2.0-dev libglibmm-2.4-dev libzip-dev check default-jdk libqt4-dev libboost-dev \
	libboost-system-dev libglib2.0-dev libqt4-dev libboost-test-dev libboost-thread-dev \
	libboost-filesystem-dev
	$(call gitclone,git://sigrok.org/libserialport)
	cd $(repo) && ./autogen.sh && ./configure && make && make install
	$(call gitclone,git://sigrok.org/libsigrok)
	cd $(repo) && ./autogen.sh && ./configure && make && make install
	$(call gitclone,git://sigrok.org/pulseview)
	cd $(repo) && cmake . && make && make install
