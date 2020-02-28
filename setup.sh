#!/bin/bash

# This script will setup the host OS, install all dependencies for Lynx and then execute the install
# script after a short wait time of 15 minutes. Some hosting vendors might require a manual reboot
# after the whole installation is complete.

# To get started, log into your VPS or Pi, and as root copy and paste the following line.

# wget -qO - https://getlynx.io/setup.sh | bash
#
# OR
#
# wget -O - https://getlynx.io/setup.sh | bash -s "[mainnet|testnet]" "[master|0.16.3.9]"

# This will start the intallation. You can now close the session window in your termial or putty
# window. The script will run in the background without need for human interaction. Depending on the
# speed of your VPS or Pi2, Pi3, or Pi4, the process will be complete anywhere from 45 minutes to 4 hours.

# For Pi users. If you are using LynxCI, this script is already installed so simply powering on
# your Pi is enough to start the process. No further interaction is needed after flashing your Micro
# SD card with the latest version of LynxCI, plugging it into your Pi and powering it on. This
# script will support Pi 2, 3, and 4 only please.

enviro="$1" # For most rollouts, the two options are mainnet or testnet. Mainnet is the default 
branch="$2" # The master branch contains the most recent code. 0.16.3.9 is the default.

[ -z "$1" ] && enviro="mainnet"
[ -z "$2" ] && branch="0.16.3.9"

rm -rf /boot/ssh # Assume this is the first time this script is being run and purge the marker file if it exists.

crontab -r &> /dev/null # In the event that any other crontabs exist, let's purge them all.

printf "\n\n\n\n\nECO-FRIENDLY CRYPTOCURRENCY\n\n"

printf "The business rules and energy requirements of mining creates an over-reliance on fossil fuels;\nLynx does the opposite and strives to solve this problem. For cryptocurrency to be considered a\nsecure platform for exchange in today's global marketplace, it must be created with global\nsustainability in mind.\n\n"

printf "GLOBALLY SUSTAINABLE NETWORK\n\n"

printf "The Lynx code discourages high-volume mining rigs because the code purposefully lacks incentives to\nmine it for profit. As a result, the entire Lynx network is designed to operate on a collaboration\nof low power devices that anyone can run, resulting in a collective global mining cost of only\ndollars a day.\n\n"

printf "Lynx is 'CRYPTOCURRENCY WITHOUT THE CLIMATE CHANGE'\n\n\n\n\n"

printf "Need help? Visit https://github.com/getlynx/LynxCI\n\n"
printf "Read our latest FAQ! Visit https://getlynx.io/faq/\n\n"
printf "Read our latest News! Visit https://getlynx.io/news/\n\n"
printf "Follow us on Twitter! Visit https://twitter.com/GetlynxIo\n\n"
printf "Join us on Reddit! Visit https://www.reddit.com/r/lynx\n\n"
printf "Read our articles on Medium! Visit https://medium.com/lynx-blockchain\n\n"

printf "Assembling the latest code to install LynxCI.\n\n\n\n\n\n"

# Before we begin, we need to update the local repo's. For now, the update is all we need and the
# device will still function properly.

apt-get -qq update -y &> /dev/null

# Some hosting vendors already have these installed. They aren't needed, so we are removing them
# now. This list will probably get longer over time.

apt-get -qq remove -y postfix apache2 &> /dev/null

# Now that certain packages that might bring an interactive prompt are removed, let's do an upgrade.

#apt-get -qq upgrade -y &> /dev/null # Sometimes the upgrade generates an interactive prompt. This is best handled manually depending on the VPS vendor.

# We need to ensure we have git for the following step. Let's not assume we already ahve it. Also
# added a few other tools as testing has revealed that some vendors didn't have them pre-installed.

apt-get -qq install -y git git-core htop nano &> /dev/null

apt-get -qq autoremove -y &> /dev/null

# Lets not assume this is the first time the script has been attempted.

rm -rf /root/LynxCI/

# We are downloading the latest package of build instructions from github.

git clone --quiet https://github.com/getlynx/LynxCI.git /root/LynxCI/

# We cant assume the file permissions will be right, so lets reset them.

chmod 744 -R /root/LynxCI/

# Since this is the first time the script is run, we will create a crontab to run it again
# in a few minute, when a quarter of the hour rolls around.

crontab -l &> /dev/null | { cat; echo "*/15 * * * *		PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' /bin/sh /root/LynxCI/install.sh $enviro $branch >> /var/log/syslog"; } | crontab - &> /dev/null

# This file is created for the Pi. In order for SSH to work, this file must exist.

verifyssh="/boot/ssh"

while [ ! -O $verifyssh ] ; do # Only create the file if it doesn't already exist.
	/usr/bin/touch $verifyssh
done

sed -i 's|/root/init.sh|#/root/init.sh|' /etc/rc.local &> /dev/null

echo "

	 The unattended install will begin in 15 minutes or less.
	 You can log out now or watch the live install log by typing

	 $ tail -F /var/log/syslog | grep \"LynxCI:\"

	 "
