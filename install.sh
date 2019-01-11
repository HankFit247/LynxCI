#!/bin/bash

environment="mainnet"
lynxbranch="master"
explorerbranch="master"

detect_os () {

	if [ "$environment" = "mainnet" ]; then

		port="22566"
		rpcport="9332"

	else

		port="44566"
		rpcport="19335"

	fi

	# We are inspecting the local operating system and extracting the full name so we know the
	# unique flavor. In the rest of the script we have various changes that are dedicated to
	# certain operating system versions.

	version_id=`cat /etc/os-release | egrep '^VERSION_ID=' | cut -d= -f2 -d'"'`

	pretty_name=`cat /etc/os-release | egrep '^PRETTY_NAME=' | cut -d= -f2 -d'"'`

	checkForRaspbian=$(cat /proc/cpuinfo | grep 'Revision')

	echo "Build environment is '$environment'."

	# Since we are starting the install of LynxCI, let's remove the crontab that started this
	# process so we don't accidently run it twice simultaneously. That could get ugly. Now this 
	# script can run as long as it needs without concern another crontab might start and withdraw
	# reseources.

	crontab -r &> /dev/null

}

install_packages () {

	apt-get -qq update -y

	apt-get -qq install -y autoconf automake build-essential bzip2 curl fail2ban g++ gcc git git-core htop libboost-all-dev libcurl4-openssl-dev libevent-dev libgmp-dev libjansson-dev libminiupnpc-dev libncurses5-dev libssl-dev libtool libz-dev make nano pkg-config software-properties-common

	apt-get -qq autoremove -y

}

manage_swap () {

	# Some vendors already have swap set up, so only create it if it's not already there.

	exists="$(swapon --show | grep 'partition')"

	if [ -z "$exists" ]; then

		# https://www.2daygeek.com/shell-script-create-add-extend-swap-space-linux/#

		newswapsize=1024

		grep -q "swapfile" /etc/fstab

		if [ $? -ne 0 ]; then

			fallocate -l ${newswapsize}M /swapfile

			chmod 600 /swapfile

			mkswap /swapfile

			swapon /swapfile

			echo '/swapfile none swap defaults 0 0' >> /etc/fstab

		fi

	fi

	# On a Raspberry Pi 3, the default swap is 100MB. This is a little restrictive, so we are
	# expanding it to a full 1GB of swap.

	sed -i 's/CONF_SWAPSIZE=100/CONF_SWAPSIZE=1024/' /etc/dphys-swapfile

}

reduce_gpu_mem () {

	# On the Pi, the default amount of gpu memory is set to be used with the GUI build. Instead
	# we are going to set the amount of gpu memmory to a minimum due to the use of the Command
	# Line Interface (CLI) that we are using in this build. This means we don't have a GUI here,
	# we only use the CLI. So no need to allocate GPU ram to something that isn't being used. Let's
	# assign the param below to the minimum value in the /boot/config.txt file.

	if [ ! -z "$checkForRaspbian" ]; then

		# First, lets not assume that an entry doesn't already exist, so let's purge and preexisting
		# gpu_mem variables from the respective file.

		sed -i '/gpu_mem/d' /boot/config.txt

		# Now, let's append the variable and value to the end of the file.

		echo "gpu_mem=16" >> /boot/config.txt

		echo "GPU memory was reduced to 16MB on reboot."

	fi

}

disable_bluetooth () {

	if [ ! -z "$checkForRaspbian" ]; then

		# First, lets not assume that an entry doesn't already exist, so let's purge any preexisting
		# bluetooth variables from the respective file.

		sed -i '/pi3-disable-bt/d' /boot/config.txt

		# Now, let's append the variable and value to the end of the file.

		echo "dtoverlay=pi3-disable-bt" >> /boot/config.txt

		# Next, we remove the bluetooth package that was previously installed.

		apt-get -qq remove pi-bluetooth -y

		echo "Bluetooth was uninstalled."

	fi

}

set_network () {

	ipaddr=$(ip route get 1 | awk '{print $NF;exit}')

	hhostname="lynx$(shuf -i 100000000-999999999 -n 1)"

	fqdn="$hhostname.getlynx.io"

	echo $hhostname > /etc/hostname && hostname -F /etc/hostname

	echo $ipaddr $fqdn $hhostname >> /etc/hosts

}

set_accounts () {

	# We don't always know the condition of the host OS, so let's look for several possibilities. 
	# This will disable the ability to log in directly as root.

	sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

	sed -i 's/PermitRootLogin without-password/PermitRootLogin no/' /etc/ssh/sshd_config

	# The new LynxCI username and default password.

	ssuser="lynx"

	sspassword="lynx"

	adduser $ssuser --disabled-password --gecos ""

	echo "$ssuser:$sspassword" | chpasswd

	adduser $ssuser sudo

	# We only need to lock the Pi account if this is a Raspberry Pi. Otherwise, ignore this step.

	if [ ! -z "$checkForRaspbian" ]; then

		# Let's lock the pi user account, no need to delete it.

		usermod -L -e 1 pi

		echo "The 'pi' login was locked. Please log in with '$ssuser'. The default password is '$sspassword'."

		sleep 5

	fi
}

install_portcheck () {

	rm -rf /etc/profile.d/portcheck.sh

	rm -rf /etc/profile.d/logo.txt

	cp -rf /root/LynxCI/logo.txt /etc/profile.d/logo.txt

	echo "	#!/bin/bash

	# When the build script runs, we know the lynxd port, but we don't know if after the node is
	# built. So we are hardcoding the value here, so it can be checked in the future.

	echo \"\"
	echo \"\"
	echo \"\"

	# This file really should not be downloaded over and over again. Instead, just copy the local
	# file in root to a dir in /home/lynx/ for self indexing.

	cat /etc/profile.d/logo.txt

	echo \"
 | To set up wifi, edit the '/etc/wpa_supplicant/wpa_supplicant.conf' file.    |
 '-----------------------------------------------------------------------------'
 | For local tools to play and learn, type 'sudo /root/lynx/src/lynx-cli help'.|
 '-----------------------------------------------------------------------------'
 | For LYNX RPC credentials, type 'sudo nano /root/.lynx/lynx.conf'.           |
 '-----------------------------------------------------------------------------'\"

        if [ ! -z \"\$(curl -s http://127.0.0.1/api/getblockcount)\" ]; then

        echo \" | The current block height on this LynxCI node is \$(curl -s http://127.0.0.1/api/getblockcount).                    |
 '-----------------------------------------------------------------------------'\"

        fi

        echo \" | The unique identifier for this LynxCI node is $hhostname.                |
 '-----------------------------------------------------------------------------'\"

 	port=\"$port\"

	if [ \"\$port\" = \"44566\" ]; then

        echo \" | This is a non-production 'testnet' environment of Lynx.                     |
 '-----------------------------------------------------------------------------'\"

	fi

    echo \" | Visit https://help.getlynx.io/ for more information.                        |
 '-----------------------------------------------------------------------------'\"

" > /etc/profile.d/portcheck.sh

	chmod 755 /etc/profile.d/portcheck.sh

	chmod 755 /etc/profile.d/logo.txt

	chown root:root /etc/profile.d/portcheck.sh

	chown root:root /etc/profile.d/logo.txt

}

install_nginx () {

	apt-get -qq update -y

    apt-get -qq purge apache postfix -y

    apt-get -qq autoremove -y

    apt-get -qq install ca-certificates apt-transport-https -y

    wget https://packages.sury.org/php/apt.gpg -O- | sudo apt-key add -

    echo "deb https://packages.sury.org/php/ stretch main" | sudo tee /etc/apt/sources.list.d/php.list

    apt-get -qq update -y

    apt-get -qq install unzip nginx php7.2 php7.2-common php7.2-bcmath php7.2-fpm php7.2-opcache php7.2-xml php7.2-curl php7.2-mbstring php7.2-zip -y

	echo "Nginx was installed."

	echo "PHP 7.2 was installed."

}

setup_nginx () {

    rm -rf /etc/nginx/sites-enabled/default

    rm -rf /etc/nginx/sites-available/default

    echo "

    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;
        root /var/www/html;
        index index.php;

        location = /favicon.ico { access_log off; log_not_found off; }
        location = /robots.txt  { access_log off; log_not_found off; }

        location / {
            try_files \$uri \$uri/ =404;
        }

        location ~ \.php\$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/run/php/php7.2-fpm.sock;
        }
    }

    " > /etc/nginx/sites-available/default

    ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/

    sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/7.2/fpm/php.ini

	echo "Nginx is configured."

	rm -rf /var/www/html/

	git clone https://github.com/getlynx/LynxBlockCrawler.git /var/www/html/

	chmod 755 -R /var/www/html/
	chown www-data:www-data -R /var/www/html/
	
	sed -i "s/8332/${rpcport}/g" /var/www/html/bc_daemon.php
	sed -i "s/username/${rrpcuser}/g" /var/www/html/bc_daemon.php
	sed -i "s/password/${rrpcpassword}/g" /var/www/html/bc_daemon.php

	echo "Block Crawler is installed."

}

# The MiniUPnP project offers software which supports the UPnP Internet Gateway Device (IGD)
# specifications. You can read more about it here --> http://miniupnp.free.fr
# We use this code because most folks don't know how to configure their home cable modem or wifi
# router to allow outside access to the Lynx node. While this Lynx node can talk to others, the
# others on the network can't always talk to this device, especially if it's behind a router at
# home. Currently, this library is only installed if the device is a Raspberry Pi.

install_miniupnpc () {

	if [ ! -z "$checkForRaspbian" ]; then

		echo "$pretty_name detected. Installing Miniupnpc."

		apt-get -qq install libminiupnpc-dev -y

		echo "Miniupnpc was installed."

	fi

}

install_lynx () {

	echo "$pretty_name detected. Installing Lynx."

	apt-get -qq install autoconf automake bzip2 curl nano htop g++ gcc git git-core pkg-config build-essential libtool libncurses5-dev software-properties-common libssl-dev libboost-all-dev libminiupnpc-dev libevent-dev -y

	rrpcuser="$(shuf -i 1000000000-3999999999 -n 1)$(shuf -i 1000000000-3999999999 -n 1)$(shuf -i 1000000000-3999999999 -n 1)"

	rrpcpassword="$(shuf -i 1000000000-3999999999 -n 1)$(shuf -i 1000000000-3999999999 -n 1)$(shuf -i 1000000000-3999999999 -n 1)"

	rm -rf /root/lynx/

	git clone -b "$lynxbranch" https://github.com/getlynx/Lynx.git /root/lynx/

	# We will need this db4 directory soon so let's delete and create it.

	rm -rf /root/lynx/db4 && mkdir -p /root/lynx/db4

	# We need a very specific version of the Berkeley DB for the wallet to function properly.

	cd /root/lynx/

	wget http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz

	# Now that we have the tarbar file, lets unpack it and jump to a sub directory within it.

	tar -xzf db-4.8.30.NC.tar.gz

	cd db-4.8.30.NC/build_unix/

	# Configure and run the make file to compile the Berkeley DB source.

	../dist/configure --enable-cxx --disable-shared --with-pic --prefix=/root/lynx/db4

	make --quiet install

	# Now that the Berkeley DB is installed, let's jump to the lynx directory and finish the
	# configure statement WITH the Berkeley DB parameters included.

	cd /root/lynx/

	./autogen.sh

	# If it's a Pi device then set up the uPNP arguments.

	if [ ! -z "$checkForRaspbian" ]; then

		cd /root/lynx/

		./configure LDFLAGS="-L/root/lynx/db4/lib/" CPPFLAGS="-I/root/lynx/db4/include/ -O2" --enable-cxx --without-gui --disable-shared --with-miniupnpc --enable-upnp-default --disable-tests --disable-bench

		make --quiet

	else

		cd /root/lynx/

		./configure LDFLAGS="-L/root/lynx/db4/lib/" CPPFLAGS="-I/root/lynx/db4/include/ -O2" --enable-cxx --without-gui --disable-shared --disable-tests --disable-bench

		make --quiet

	fi

	# The .lynx dir must exist for the bootstrap and lynx.conf to be placed in it.

	cd ~/ && rm -rf .lynx && mkdir .lynx

	# Some VPS vendors are struggling with cryptocurrency daemons and miners running on their 
	# platforms. These applications and mining platforms waste resources on those platforms so it's 
	# understandable why they block those daemons from running. Testing has found that lynxd is 
	# killed occasionally on some VPS platforms, even though the avg server load for a LynxCI built
	# is about 0.3 with 1 CPU and 1 GB of RAM. By copying the lynxd daemon and using the randomly 
	# generated name, we escape the daemon getting killed by some vendors. Of course, it is a cat
	# and mouse game so this will be upgraded sometime in the future.

	cp /root/lynx/src/lynxd /root/lynx/src/$hhostname

	sed -i "s/lynxd/${hhostname}/g" /root/LynxCI/explorerStop.sh
	sed -i "s/lynxd/${hhostname}/g" /root/LynxCI/explorerStart.sh

	# Below we are creating the default lynx.conf file. This file is created with the dynamically
	# created RPC credentials and it sets up the networking with settings that testing has found to
	# work well in the LynxCI build. Of course, you can edit it further if you like, but this
	# default file is the recommended start point.

	echo "

	# The following RPC credentials are created at build time and are unique to this host. If you
	# like, you can change them, but you are encouraged to keep very complex values for each. If an
	# attacker gains RPC access to this host they might be able to steal your Lynx. Understanding
	# that, the wallet is disabled by default so the risk of loss is zero.

	rpcuser=$rrpcuser
	rpcpassword=$rrpcpassword
	rpcport=$rpcport

	# The following settings will allow a connection from any external host. The two entries
	# define that any IPv4 or IPv6 address will be allowed to connect. The default firewall settings
	# also allow the traffic because the RPC port is open by default. If you are setting up a remote
	# connection, all you will need is the above RPC credentials. No further network configuration
	# is needed. To secure the node from repeated connetion attempts or to restrict connections to
	# your IP's only, change the following values as needed.

	rpcallowip=0.0.0.0/24
	rpcallowip=::/0

	# The debug log (/root/.lynx/debug.log) is capable of outputing a massive amount of data. If you
	# are chasing a bug, set the argument to 'debug=1'. It isn't recommended to leave that log level
	# intact though. The default state of this build is to output the BuiltinMiner info, so if you
	# don't want to see it, you can change the argument to 'debug=0'. We think the BuiltinMiner info
	# is fun though, but on a Pi, to reduce SD card writes, it might be most efficient to go with
	# the least amount of debug info, so change it to 'debug=0'.

	debug=miner

	# By default, wallet functions in LynxCI are disabled. This is for security reasons. If you
	# would like to enable your wallet functions, change the value from '1' to '0' in the
	# 'disablewallet' parameter. Then restart lynxd to enact the change. Of course, you can do the
	# reverse action to disable wallet functions on this node. You can always check to see if
	# wallet functions are enabled with '$ /root/lynx/src/lynx-cli help', looking for the
	# '== Wallet ==' section at the bottom of the help file.

	disablewallet=1

	# The following list of nodes are maintained for faster detection of peers and network sync.

	addnode=node01.getlynx.io
	addnode=node02.getlynx.io
	addnode=node03.getlynx.io
	addnode=node04.getlynx.io
	addnode=node05.getlynx.io

	# The following addresses are known to pass the validation requirements for HPoW. If you would
	# like to earn your own mining rewards, you can add/edit/delete this list with your own
	# addresses (more is better). You must have a balance of between 1,000 and 100,000,000 Lynx in
	# each of the Lynx addresses in order to win the block reward. Alternatively, you can enable
	# wallet functions on this node, deposit Lynx to the local wallet (again, between 1,000 and
	# 100,000,000 Lynx) and the miner will ignore the following miner address values.

	mineraddress=KKMeTYLM6LrhFc8Gq1uYSua4BLgmFPaZrX
	mineraddress=KVKrkxGcUo9wii59ashrbqKub5CpggiFQz
	mineraddress=KMPxdPMwJb3rn1dLx9L2xxxUgiZiGRC8Um
	mineraddress=KERgGnd5vCMkdFbGynrGeqhBnitz1zrg22
	mineraddress=KWJfZ9qQ4aAiieB9jh8iJk5ttxhWV566RU
	mineraddress=KVaeY15ikttZM2rwBh694LPC1qZHgKvTsg
	mineraddress=KA8VJVzqy7xo6AEYRxAa8WHLqqScwGHmGx
	mineraddress=KJhTW2s2q1gvpaWLWSdmwLa9dvvqmAcnzj
	mineraddress=KTT3d4obtRGdkyLeUQQk75VKkBavXcXcFn
	mineraddress=KH5Lkvw511qAgUeoqxNa9BSGdZuok7q6ow
	mineraddress=KJErWXjc4ycq436Tonf5dy8RFhF1SiuSM2
	mineraddress=KRJf4FQB6GAk2E6dXeJ5osbd1GsHjW6mWf
	mineraddress=KDjfv9bUfyfFfuVgyhTazreESRfHpYnMi3
	mineraddress=KBywa5qcAZTB3CC7vCzxVeU8eYW6PBdSfJ
	mineraddress=KU7tLLoa1geou57GWoEY7MXUpQNetRbuNy
	mineraddress=K7XNmz2h2PgyGC8aYhXHJ8W58WnjZgrU85
	mineraddress=KT4nWz8PEAyAiBQTXu6T9z7TZCe5h2pUep
	mineraddress=KG5unFERmH6Qsvt3muci4ZeKgtmUaw7TdQ
	mineraddress=KRgVAxFgfjkYKovizRG1DfkLKd59rpEHxe
	mineraddress=KMoRtp69iMVVSWUPVwdota6HSCkP2yChFH
	mineraddress=KNcAXmZY9CKUesky2dRbKWJM5PZwQmUNYk
	mineraddress=KSX55i4ef1y1kYtHu6E7EUt7Fx4GAg9yzm
	mineraddress=K8QGUNxc86Ahr9CSW1NyT2LGDC8BAUk6iM
	mineraddress=KRgVAxFgfjkYKovizRG1DfkLKd59rpEHxe
	mineraddress=KMoRtp69iMVVSWUPVwdota6HSCkP2yChFH
	mineraddress=KNcAXmZY9CKUesky2dRbKWJM5PZwQmUNYk
	mineraddress=KR9QTmep2LYt53oS9Ypn7Qo6mjd9jNMvw5
	mineraddress=KKpNgtMs8kjpxB9EHmLVyhsdfcA6tyZ2g8
	mineraddress=K7GMcJ4idxwhbusn8sTBotJbsRZ8FU22cu
	mineraddress=KFgo4RmUiFX8FAg3sk8ZRptqmTD9Nk8u2w
	mineraddress=KV3fxxtbb1gwY69tAsqkq8rBHzMczia7To
	mineraddress=KHHHfhcethqahpN7aAeJ9JiBDGtjsW89oM
	mineraddress=KVgBWE4xibFrRzN1X7Cv3nVymTg3EcnePm
	mineraddress=KPhTE61wshvyiDHFLLLvZ3rBhrGjWruWdh
	mineraddress=KLpTz6JbUEkrxNTs24gftPxsgyGG53qKsD
	mineraddress=KBw3LHq6TNDLTL35QFTfwyGvDA1YA4xwq7
	mineraddress=KDWbrVGdb9M5MuH3q8XP9SuNQweX4g1w7C
	mineraddress=KGDFGZuwCnT9kcBNWPtQVuZdZ1AoiaGYUy
	mineraddress=KFaLZ37WgSXeUUpQZAXamMDfDkS96Fpp6W
	mineraddress=KSbtHFRoaj8Vb5EespmCEbtNJGG7UtM2U2
	mineraddress=KUn12PLFXUaVwneQMNp6kiZ2c9rUVPkDjp
	mineraddress=KHXGt1Pn1yVXvYQmLTuG8pYqYH29t6p8pL
	mineraddress=K85WRcMbcuWi9T3JsH7NhZp8Tb3nNmcYVS
	mineraddress=KMzbPq5YvdCpNiVtECk9VVVGbnxhP6V7ch
	mineraddress=K8fQpFnHWw2iBHycR1B1NWJBCGSojEhjst
	mineraddress=K8yBpqfkP2gg7buhNhWM7s3PqBsCA7PW9r
	mineraddress=KSGe8xZbM9NfeQnjX9fyMbqLaGQTRUS5Jh
	mineraddress=KBw2p51RrrbcceRoSbvb6ZkX437kuQM99F
	mineraddress=KDv7VKpixza5u51L5gmPNtUyRWpkaJBYg3
	mineraddress=KTHz2RJrt8SoDXbzwVJ3Znybn3mZNJwscs
	mineraddress=KB7SVrCBjKTSZSxqNhX7zfpNK68MPRG95k
	mineraddress=K95nM1gWhRMRvgLZTyi61tceYjfp5Ys71u
	mineraddress=KJevkjENSeBzVp5MnSvyNqnemF9rn6unYo
	mineraddress=KQqL8U2vD5QpZg8MJ47cVj2sRbo7gV4tu5
	mineraddress=KQpa4GDG5GcwrinjpDmUgpAaYgRbfNGUMK
	mineraddress=KGFx9JD1dFY4dtFdLqw1d3ZQnWL6ws6nLy
	mineraddress=KNoWE13FPBDUuqyK1DUT7qnJx9jVfqkeGc
	mineraddress=KMqkxAmFYpMDEyEA5QmbZZrwXtu6pwuv61
	mineraddress=KS2Gg8MvcJmLNPK7mQdoG6DJJaZxQ4neej
	mineraddress=KBmLgzVMiKbcMuaoJeoPNs5R98tAHYM515
	mineraddress=KCtFzP3fGn1ZxRiNVFeCnGuwiy7qsSvB22
	mineraddress=K9WR6ZTB5X4hoWvTUK1xR4ddWUSX9qMeS4
	mineraddress=KSXLSbsoovJepb9x1sczDRNyTvDYEfZZ2k
	mineraddress=KNv9XbCfshP4vV9GN7p6KYGEPqYFc4Ei6c
	mineraddress=KRUrR4beUxL5AsyVduL5KT7BNHsbkA9Mh2
	mineraddress=K9URJRCsL6nrYMXVA6kPBVq5Db8gW5iVEQ
	mineraddress=KNYnVkhaQehdbKSqy4a3AiZGBAYQkqemPF
	mineraddress=KExtMudoDex2bckdwhoi2jJxpPMTwpvoSd
	mineraddress=KHCqKmt8B3zgQ6z3XWGhhPLuLWvsJiwy3Q
	mineraddress=KNZLV7CcBgXR87xi7NCyhGojaJrWHg63FC
	mineraddress=K8cckpj6R5yBPNHfBpfP3mm9Joo2VgRWSd
	mineraddress=KAQuZ4eTzTQ9AR6kgHXay6DbVXBACwfJpK
	mineraddress=KQ69GDCDVcd1ar6gFqUHhLzUCa1eG6QK2u
	mineraddress=KFj36awh9AaAK3pxKW8E7RmMQf1P17VNdr

	# It is highly unlikely you need to change any of the following values unless you are tinkering
	# with the node. If you do decide to tinker, make a backup of this file first.

	listen=1
	daemon=1
	port=$port
	rpcbind=127.0.0.1
	rpcbind=::1
	rpcworkqueue=64
	listenonion=0
	upnp=1
	dbcache=100
	txindex=1
	host=$hhostname

	" > /root/.lynx/lynx.conf

	if [ "$environment" = "testnet" ]; then

	echo "
	
	testnet=1

	" >> /root/.lynx/lynx.conf

	fi

	# We are gonna create a backup of the initially created lynx.conf file. This file does not ever
	# run, it is just created for backup purposes. Please leave it intact so you can refer to it in
	# the future in case you need to restore a parameter or value you have previously edited.

	cp /root/.lynx/lynx.conf /root/.lynx/lynx.default

	# For a faster sync time, we are pulling for a copy of the chainstate and blocks from a seed
	# node and inserting them into the install. The blocks were created with txindex=1 so a full 
	# network sync and rescan should not be needed.

	wget http://cdn.getlynx.io/chainstate.tar.gz

	tar -xzvf /root/chainstate.tar.gz -C /root/.lynx/

	wget http://cdn.getlynx.io/blocks.tar.gz

	tar -xzvf /root/blocks.tar.gz -C /root/.lynx/

	# Be sure to reset the ownership of all files in the .lynx dir to root in case any process run
	# previously changed the default ownership setting. More of a precautionary measure.

	chown -R root:root /root/.lynx/*

	echo "Lynx was installed."

}

setup_crontabs () {

	/root/LynxCI/explorerStop.sh

	crontab -l | { cat; echo "@reboot		MALLOC_ARENA_MAX=1 /root/lynx/src/${hhostname} -reindex"; } | crontab -

}

set_firewall () {

	# To make sure we don't create any problems, let's truly make sure the firewall instructions
	# we are about to create haven't already been created. So we delete the file we are going to
	# create in the next step. This is just a step to insure stability and reduce risk in the
	# execution of this build script.

	rm -rf /root/firewall.sh

	echo "

	#!/bin/bash

	IsRestricted=Y

	# Let's flush any pre existing iptables rules that might exist and start with a clean slate.

	/sbin/iptables -F

	# We should always allow loopback traffic.

	/sbin/iptables -I INPUT 1 -i lo -j ACCEPT

	# This line of the script tells iptables that if we are already authenticated, then to ACCEPT
	# further traffic from that IP address. No need to recheck every packet if we are sure they
	# aren't a bad guy.

	/sbin/iptables -I INPUT 2 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

	# If the script has IsRestricted set to Y, then let's open up port 22 for any IP address. But if
	# the script has IsRestricted set to N, let's only open up port 22 for local LAN access. This means
	# you have to be physically connected (or via Wifi) to SSH to this computer. It isn't perfectly
	# secure, but it removes the possibility for an SSH attack from a public IP address. If you
	# wanted to completely remove the possibility of an SSH attack and will only ever work on this
	# computer with your own physically attached KVM (keyboard, video & mouse), then you can comment
	# the following 6 lines. Be careful, if you don't understand what you are doing here, you might
	# lock yourself from being able to access this computer. If so, just go through the build
	# process again and start over.

	if [ \"\$IsRestricted\" = \"N\" ]; then

		/sbin/iptables -A INPUT -p tcp --dport 22 -j ACCEPT

	else

		/sbin/iptables -A INPUT -p tcp -s 10.0.0.0/8 --dport 22 -j ACCEPT

		/sbin/iptables -A INPUT -p tcp -s 192.168.0.0/16 --dport 22 -j ACCEPT

		# VPN service https://www.vpnsecure.me [Germany]

		/sbin/iptables -A INPUT -p tcp -s 185.216.33.82 --dport 22 -j ACCEPT

		# VPN service https://www.vpnsecure.me [Austria]

		/sbin/iptables -A INPUT -p tcp -s 146.255.57.28 --dport 22 -j ACCEPT

		# VPN service https://www.vpnsecure.me [Canada TCP]

		/sbin/iptables -A INPUT -p tcp -s 67.215.7.186 --dport 22 -j ACCEPT

		# VPN service https://www.vpnsecure.me [Australia 2 TCP]

		/sbin/iptables -A INPUT -p tcp -s 168.1.53.196 --dport 22 -j ACCEPT

		# VPN service https://www.vpnsecure.me [Belgium 1 TCP]

		/sbin/iptables -A INPUT -p tcp -s 82.102.19.178 --dport 22 -j ACCEPT

		# VPN service https://www.vpnsecure.me [United States 10 - N-West]

		/sbin/iptables -A INPUT -p tcp -s 162.210.250.170 --dport 22 -j ACCEPT

		# VPN service https://www.vpnsecure.me [United States 3 - East]

		/sbin/iptables -A INPUT -p tcp -s 64.20.43.202 --dport 22 -j ACCEPT

		# VPN service https://www.vpnsecure.me [Vietnam TCP]

		/sbin/iptables -A INPUT -p tcp -s 125.212.251.87 --dport 22 -j ACCEPT

		# VPN service https://www.vpnsecure.me [Netherlands TCP]

		/sbin/iptables -A INPUT -p tcp -s 89.39.105.120 --dport 22 -j ACCEPT

	fi

	# Becuase the Block Explorer or Block Crawler are available via port 80 (standard website port)
	# we must open up port 80 for that traffic.

	/sbin/iptables -A INPUT -p tcp --dport 80 -j DROP

	# This Lynx node listens for other Lynx nodes on port $port, so we need to open that port. The
	# whole Lynx network listens on that port so we always want to make sure this port is available.

	/sbin/iptables -A INPUT -p tcp --dport $port -j ACCEPT

	# Known addresses of other coin projects that operate on the same port and have the same version
	# number. This will remove a good number of 'connection refused' errors in the debug log.

	/sbin/iptables -A INPUT -p tcp -s 95.54.82.161 -j DROP #ExperiencecoinCore:3.0.0.1
	/sbin/iptables -A INPUT -p tcp -s 95.222.46.126 -j DROP #ExperiencecoinCore:3.0.0.1
	/sbin/iptables -A INPUT -p tcp -s 165.227.211.179 -j DROP #ExperiencecoinCore:3.0.0.1
	/sbin/iptables -A INPUT -p tcp -s 76.102.131.12 -j DROP #NewYorkCoin-seeder:0.01
	/sbin/iptables -A INPUT -p tcp -s 62.213.218.8 -j DROP #NewYorkCoin-seeder:0.01

	# By default, the RPC port 9223 is opened to the public. This is so the node can both listen
	# for and discover other nodes. It is preferred to have a node that is not just a leecher but
	# also a seeder.

	/sbin/iptables -A INPUT -p tcp --dport $rpcport -j ACCEPT

	# We add this last line to drop any other traffic that comes to this computer that doesn't
	# comply with the earlier rules. If previous iptables rules don't match, then drop'em!

	/sbin/iptables -A INPUT -j DROP

	#
	# Metus est Plenus Tyrannis
	#" > /root/firewall.sh

	echo "Firewall rules are set in /root/firewall.sh"

	chmod 700 /root/firewall.sh

}

config_fail2ban () {

	#
	# The default ban time for abusers on port 22 (SSH) is 10 minutes. Lets make this a full 24
	# hours that we will ban the IP address of the attacker. This is the tuning of the fail2ban
	# jail that was documented earlier in this file. The number 86400 is the number of seconds in
	# a 24 hour term. Set the bantime for lynxd on port 22566/44566 banned regex matches to 24
	# hours as well.

	echo "

	[sshd]
	enabled	= true
	bantime = 86400

	" > /etc/fail2ban/jail.d/defaults-debian.conf

	# Configure the fail2ban jail for lynxd and set the frequency to 20 min and 3 polls.

	echo "

	#
	# SSH
	#

	[sshd]
	port		= ssh
	logpath		= %(sshd_log)s

	" > /etc/fail2ban/jail.local

	service fail2ban start

}

restart () {

	# We now write this empty file to the /boot dir. This file will persist after reboot so if
	# this script were to run again, it would abort because it would know it already ran sometime
	# in the past. This is another way to prevent a loop if something bad happens during the install
	# process. At least it will fail and the machine won't be looping a reboot/install over and
	# over. This helps if we have to debug a problem in the future.

	/usr/bin/touch /boot/ssh

	/usr/bin/touch /boot/lynxci

	/bin/rm -rf /root/setup.sh
	/bin/rm -rf /root/LynxCI/setup.sh
	/bin/rm -rf /root/LynxCI/init.sh
	/bin/rm -rf /root/LynxCI/README.md
	/bin/rm -rf /root/LynxCI/install.sh
	/bin/rm -rf /root/blocks.tar.gz
	/bin/rm -rf /root/chainstate.tar.gz

	echo "LynxCI was installed."

	echo "A reboot will occur 10 seconds."

	sleep 10

	reboot

}

# First thing, we check to see if this script already ran in the past. If the file "/boot/ssh"
# exists, we know it previously ran.

if [ -f /boot/lynxci ]; then

	echo "Previous LynxCI detected. Install aborted."

else

	echo "Starting installation of LynxCI."

	detect_os
	install_packages
	set_network
	manage_swap
	reduce_gpu_mem
	disable_bluetooth
	set_accounts
	install_portcheck
	install_miniupnpc
	install_lynx
	install_nginx
	setup_nginx
	set_firewall
	config_fail2ban
	setup_crontabs
	restart

fi
