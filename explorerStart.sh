#!/bin/bash

# The first command starts nginx and the second makes sure it starts after a reboot.

systemctl start nginx && systemctl enable nginx

# The first command starts PHP-FPM and the second makes sure it starts after a reboot.

systemctl start php7.2-fpm && systemctl enable php7.2-fpm

# The following line is a search and replace for the string in the firewall script that enabled (or
# disables) access to the node via port 80. If the Block Explorer isn't running, we might as well
# close port 80 and remove that as a possible attack vector.

sed -i 's/80 -j DROP/80 -j ACCEPT/' /root/firewall.sh

# If the crawler is running, it needs the disablewallet param of lynxd to be enabled. 

sed -i 's/disablewallet=1/disablewallet=0/' /root/.lynx/lynx.conf

# For the built in Block Crawler. Since it is not being used, let's purge the lynx.conf file copy
# if it still exists.

rm -rf /var/www/crawler.conf

# Time to recreate the lynx.conf file in a working dir that PHP can access. Be sure to NEVER edit
# this file as it is overwritten regularly. Only ever edit the /root/.lynx/lynx.conf version.

cp /root/.lynx/lynx.conf /var/www/crawler.conf

/root/firewall.sh # Clear and reset the firewall state to the default state with recent changes.

crontab -r # In the event that any other crontabs exist, let's purge them all.

crontab -l | { cat; echo "0 */3 * * *		/root/LynxCI/explorerStart.sh"; } | crontab -

# We found that after a few weeks, the debug log would grow rather large. It's not really needed
# after a certain size, so let's truncate that log down to a reasonable size every day.

crontab -l | { cat; echo "*/30 * * * *		truncate -s 10KB /root/.lynx/debug.log"; } | crontab -

# Evey 15 days we will reboot the device. This is for a few reasons. Since the device is often
# not actively managed by it's owner, we can't assume it is always running perfectly so an
# occasional reboot won't cause harm. This crontab means to reboot EVERY 15 days, NOT on the
# 15th day of the month. An important distinction.

crontab -l | { cat; echo "0 0 $(shuf -i 16-28 -n 1) * *		/sbin/shutdown -r now"; } | crontab -
