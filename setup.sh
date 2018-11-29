#!/bin/bash

# This script will setup the host OS, install all dependencies for Lynx and then execute the install
# script after a short wait time of 15 minutes. Some hosting vendors might require a manual reboot
# (i.e. HostBRZ) after the whole installation is complete.

# To get started, log into your VPS or Pi, and as root copy and paste the following line.

# wget -qO - https://getlynx.io/setup.sh | bash

# This will start the intallation. You can now close the session window in your termial or putty
# window. The script will run in the background without need for human interaction. Depending on the
# speed of your VPS or Pi2 or Pi3, the process will be complete anywhere from 45 minutes to 4 hours.

# For Pi users. If you are using LynxCI, this script is already installed so simply powering on
# your Pi is enough to start the process. No further interaction is needed after flashing your Micro
# SD card with the latest version of LynxCI, plugging it into your Pi and powering it one. This
# script will support Pi 2 and 3 only please.

checkForRaspbian=$(cat /proc/cpuinfo | grep 'Revision')

rm -rf /boot/ssh # Assume this is the first time this script is being run and purge the marker file if it exists.

crontab -r &> /dev/null # In the event that any other crontabs exist, let's purge them all.

echo "Updating the local operating system. This might take a few minutes."

if [ -z "$checkForRaspbian" ]; then

	# In case the VPS vendor doesn't have the locale set up right, (I'm looking at you, HostBRZ), run
	# this command to set the following values in a non-interactive manner. It should survive a reboot.

	echo "locales locales/default_environment_locale select en_US.UTF-8" | debconf-set-selections
	echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" | debconf-set-selections
	rm -rf "/etc/locale.gen"
	dpkg-reconfigure --frontend noninteractive locales
	echo "Locale for the target host was set to en_US.UTF-8 UTF-8."

fi

# Before we begin, we need to update the local repo's. For now, the update is all we need and the
# device will still function properly.

apt-get -qq update -y

# Some hosting vendors already have these installed. They aren't needed, so we are removing them
# now. This list will probably get longer over time.

apt-get -qq remove -y postfix apache2

# Now that certain packages that might bring an interactive prompt are removed, let's do an upgrade.

apt-get -qq upgrade -y

# We need to ensure we have git for the following step. Let's not assume we already ahve it. Also
# added a few other tools as testing has revealed that some vendors didn't have them pre-installed.

apt-get -qq install -y autoconf automake build-essential bzip2 curl fail2ban g++ gcc git git-core htop libboost-all-dev libcurl4-openssl-dev libevent-dev libgmp-dev libjansson-dev libminiupnpc-dev libncurses5-dev libssl-dev libtool libz-dev make nano nodejs pkg-config software-properties-common

apt-get -qq autoremove -y

# Lets not assume this is the first time the script has been attempted.

rm -rf /root/LynxCI/

echo "Local operating system is updated."

# We are downloading the latest package of build instructions from github.

git clone https://github.com/doh9Xiet7weesh9va9th/LynxCI.git /root/LynxCI/

# We cant assume the file permissions will be right, so lets reset them.

chmod 744 -R /root/LynxCI/

# Since this is the first time the script is run, we will create a crontab to run it again
# in a few minute, when a quarter of the hour rolls around.

crontab -l &> /dev/null | { cat; echo "*/15 * * * *		PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' /bin/sh /root/LynxCI/install.sh mainnet >> /var/log/syslog"; } | crontab - &> /dev/null

# This file is created for the Pi. In order for SSH to work, this file must exist.

touch /boot/ssh

# If this is Pi install, purge the setup script so it doesn't try to install again on reboot.

sed -i '/wget -qO - https:\/\/getlynx.io\/setup.sh | bash/d' /etc/rc.local

echo "

	 The unattended install will begin in 15 minutes or less.
	 You can log out now or watch the live install log by typing

	 $ tail -F /var/log/syslog

	 "
