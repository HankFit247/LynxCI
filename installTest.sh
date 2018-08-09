#!/bin/bash

# Our first required argument to run this script is to specify the environment to run Lynx. The two
# accepted options are 'mainnet' or 'testnet'.

if [ "$1" = "mainnet" ]; then

	environment="mainnet"
	port="22566"
	rpcport="9332"
	lynxbranch="master"
	explorerbranch="master"
	lynxconfig=""
	explorer="https://explorer.getlynx.io/api/getblockcount"
	addresses="miner-addresses.txt"

else

	environment="testnet"
	port="44566"
	rpcport="19335"
	lynxbranch="new_validation_rules"
	explorerbranch="new-ui"
	lynxconfig="testnet=1"
	explorer="https://test-explorer.getlynx.io/api/getblockcount"
	addresses="miner-addresses-testnet.txt"

fi

BLUE='\033[94m'
GREEN='\033[32;1m'
YELLOW='\033[33;1m'
RED='\033[91;1m'
RESET='\033[0m'

print_info () {

	printf "$BLUE$1$RESET\n"
	sleep 1

}

print_success () {

	printf "$GREEN$1$RESET\n"
	sleep 1

}

print_warning () {

	printf "$YELLOW$1$RESET\n"
	sleep 1

}

print_error () {

	printf "$RED$1$RESET\n"
	sleep 1

}

detect_os () {

	# We are inspecting the local operating system and extracting the full name so we know the 
	# unique flavor. In the rest of the script we have various changes that are dedicated to
	# certain operating system versions.

	version_id=`cat /etc/os-release | egrep '^VERSION_ID=' | cut -d= -f2 -d'"'`

	pretty_name=`cat /etc/os-release | egrep '^PRETTY_NAME=' | cut -d= -f2 -d'"'`

	checkForRaspbian=$(cat /proc/cpuinfo | grep 'Revision')

	print_success "Build environment is '$environment'."

}

detect_ec2() {

	IsEC2="N"

    # This first, simple check will work for many older instance types.

    if [ -f /sys/hypervisor/uuid ]; then

		# File should be readable by non-root users.

		if [ `head -c 3 /sys/hypervisor/uuid` == "ec2" ]; then
			IsEC2="Y"
		fi

    # This check will work on newer m5/c5 instances, but only if you have root!

    elif [ -r /sys/devices/virtual/dmi/id/product_uuid ]; then

		# If the file exists AND is readable by us, we can rely on it.

		if [ `head -c 3 /sys/devices/virtual/dmi/id/product_uuid` == "EC2" ]; then
			IsEC2="Y"
		fi

    else

		# Fallback check of http://169.254.169.254/. If we wanted to be REALLY
		# authoritative, we could follow Amazon's suggestions for cryptographically
		# verifying their signature, see here:
		# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-identity-documents.html
		# but this is almost certainly overkill for this purpose (and the above
		# checks of "EC2" prefixes have a higher false positive potential, anyway).

		if $(curl -s -m 5 http://169.254.169.254/latest/dynamic/instance-identity/document | grep -q availabilityZone) ; then
			IsEC2="Y"
		fi
    fi

}

detect_vps () {

	detect_ec2
}

install_extras () {

	apt-get update -y &> /dev/null

	apt-get install cpulimit htop curl fail2ban automake autoconf pkg-config libcurl4-openssl-dev libjansson-dev libssl-dev libgmp-dev make g++ -y &> /dev/null

	print_success "Cpulimit was installed."

}

expand_swap () {

	# We are only modifying the swap amount for a Raspberry Pi device. In the future, other
	# environments will have their own place in the following conditional statement.

	if [ ! -z "$checkForRaspbian" ]; then

		# On a Raspberry Pi 3, the default swap is 100MB. This is a little restrictive, so we are
		# expanding it to a full 1GB of swap. We don't usually touch too much swap but during the 
		# initial compile and build process, it does consume a good bit so lets provision this.

		sed -i 's/CONF_SWAPSIZE=100/CONF_SWAPSIZE=1024/' /etc/dphys-swapfile

		print_success "Swap will be increased to 1GB on reboot."

	fi

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

		print_success "GPU memory was reduced to 16MB on reboot."

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

		apt-get remove pi-bluetooth -y &> /dev/null

		print_success "Bluetooth was uninstalled."

	fi

}

set_network () {

	ipaddr=$(ip route get 1 | awk '{print $NF;exit}')

	hhostname="lynx$(shuf -i 100000000-199999999 -n 1)"

	fqdn="$hhostname.getlynx.io"

	echo $hhostname > /etc/hostname && hostname -F /etc/hostname

	echo $ipaddr $fqdn $hhostname >> /etc/hosts

}

set_wifi () {

	# The only time we want to set up the wifi is if the script is running on a Raspberry Pi. The
	# script should just skip over this step if we are on any OS other then Raspian. 

	if [ ! -z "$checkForRaspbian" ]; then

		# Let's assume the files already exists, so we will delete them and start from scratch.

		rm -rf /boot/wpa_supplicant.conf
		rm -rf /etc/wpa_supplicant/wpa_supplicant.conf
		
		echo "

		ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
		update_config=1
		country=US

		network={
			ssid=\"Your network SSID\"
			psk=\"Your WPA/WPA2 security key\"
			key_mgmt=WPA-PSK
		}

		" >> /boot/wpa_supplicant.conf

		print_success "Wifi configuration script was installed."

	fi

}

set_accounts () {

	sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

	ssuser="lynx"
	sspassword="lynx"

	adduser $ssuser --disabled-password --gecos "" && echo "$ssuser:$sspassword" | chpasswd &> /dev/null

	adduser $ssuser sudo &> /dev/null

	# We only need to lock the Pi account if this is a Raspberry Pi. Otherwise, ignore this step.

	if [ ! -z "$checkForRaspbian" ]; then

		# Let's lock the pi user account, no need to delete it.

		usermod -L -e 1 pi &> /dev/null

		print_success "The 'pi' account was locked. Please log in with the $ssuser account."

		sleep 5

	fi
}

install_portcheck () {

	rm -rf /etc/profile.d/portcheck.sh

	echo "	#!/bin/bash

	BLUE='\033[94m'
	GREEN='\033[32;1m'
	RED='\033[91;1m'
	RESET='\033[0m'

	print_success () {

		printf \"\$GREEN\$1\$RESET\n\"

	}

	print_error () {

		printf \"\$RED\$1\$RESET\n\"

	}

	print_info () {

		printf \"\$BLUE\$1\$RESET\n\"

	}

	print_success \" Standby, checking connectivity...\"

	# When the build script runs, we know the lynxd port, but we don't know if after the node is 
	# built. So we are hardcoding the value here, so it can be checked in the future.

	port=\"$port\"
	rpcport=\"$rpcport\"

	if [ -z \"\$(ss -lntu | grep \$port | grep -i listen)\" ]; then
	  app_reachable=\"false\"
	else
	  app_reachable=\"true\"
	fi

	if [ -z \"\$(ss -lntu | grep \$rpcport | grep -i listen)\" ]; then
	  rpc_reachable=\"false\"
	else
	  rpc_reachable=\"true\"
	fi

	if ! pgrep -x \"lynxd\" > /dev/null; then

		block=\"being updated\"

	else

		if pgrep -x \"nginx\" > /dev/null; then

			block=\$(curl -s http://127.0.0.1/bc_api.php?request=getblockcount)

		else

			block=\$(curl -s http://127.0.0.1/api/getblockcount)
			
		fi

		if [ -z \"\$block\" ]; then

			block=\"being updated\"

		else

			block=\$(echo \$block | numfmt --grouping)

		fi

	fi

	print_success \"\"
	print_success \"\"
	print_success \"\"

	# This file really should not be downloaded over and over again. Instead, just copy the local
	# file in root to a dir in /home/lynx/ for self indexing.

	curl -s https://raw.githubusercontent.com/doh9Xiet7weesh9va9th/LynxNodeBuilder/master/logo.txt

	echo \"
 | To set up wifi, edit the /etc/wpa_supplicant/wpa_supplicant.conf file.      |
 '-----------------------------------------------------------------------------'
 | For local tools to play and learn, type 'sudo /root/lynx/src/lynx-cli help' |
 '-----------------------------------------------------------------------------'
 | LYNX RPC credentials for remote access are located in /root/.lynx/lynx.conf |
 '-----------------------------------------------------------------------------'\"

	if [ \"\$app_reachable\" = \"true\" ]; then

		print_success \"\"
		print_success \" Lynx port \$port is open.\"

	else

		print_success \"\"
		print_error \" Lynx port \$port is not open.\"

	fi

	if [ \"\$rpc_reachable\" = \"true\" ]; then

		print_success \"\"
		print_success \" Lynx RPC port \$rpcport is open.\"
		print_success \"\"

	else

		print_success \"\"
		print_error \" Lynx RPC port \$rpcport is not open.\"
		print_success \"\"

	fi

	if [ \"\$port\" = \"44566\" ]; then

		print_error \" This is a non-production 'testnet' environment of Lynx.\"
		print_success \"\"

	fi

	print_success \" Lot's of helpful videos about LynxCI are available at the Lynx FAQ. Visit \"
	print_success \" https://getlynx.io/faq/ for more information and help.\"
	print_success \"\"
	print_info \" The current block height on this Lynx node is \$block.\"
	print_success \"\"

	" > /etc/profile.d/portcheck.sh

	chmod 744 /etc/profile.d/portcheck.sh
	chown root:root /etc/profile.d/portcheck.sh

}

install_explorer () {

	# Let's jump pack to the root directory, since we can't assume we know where we were.

	cd ~/

	# Let's not assume this is the first time this function is run, so let's purge the directory if
	# it already exists. This way if the power goes out during install, the build process can 
	# gracefully restart.

	rm -rf ~/LynxExplorer && rm -rf ~/.npm-global

	# We might need curl and some other dependencies so let's grab those now. It is also possible 
	# these packages might be used elsewhere in this script so installing them now is no problem.
	# The apt installed is smart, if the package is already installed, it will either attempt to 
	# upgrade the package or skip over the step. No harm done.

    apt-get install curl software-properties-common gcc g++ make -y &> /dev/null

    curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
    apt-get install nodejs -y &> /dev/null
    print_success "NodeJS was installed."

	npm install pm2 -g
	print_success "PM2 was installed."

	git clone -b $explorerbranch https://github.com/doh9Xiet7weesh9va9th/LynxExplorer.git &> /dev/null
	print_success "Block Explorer was installed."
	
	cd /root/LynxExplorer/ && npm install --production &> /dev/null

	# We need to update the json file in the LynxExplorer node app with the lynxd RPC access
	# credentials for this device. Since they are created dynamically each time, we just do
	# find and replace in the json file.

	sed -i "s/9332/${rpcport}/g" /root/LynxExplorer/settings.json
	sed -i "s/__HOSTNAME__/x${fqdn}/g" /root/LynxExplorer/settings.json
	sed -i "s/__MONGO_USER__/x${rrpcuser}/g" /root/LynxExplorer/settings.json
	sed -i "s/__MONGO_PASS__/x${rrpcpassword}/g" /root/LynxExplorer/settings.json
	sed -i "s/__LYNXRPCUSER__/${rrpcuser}/g" /root/LynxExplorer/settings.json
	sed -i "s/__LYNXRPCPASS__/${rrpcpassword}/g" /root/LynxExplorer/settings.json

	# start LynxBlockExplorer process using pm2
	pm2 stop LynxBlockExplorer
	pm2 delete LynxBlockExplorer
	pm2 start npm --name LynxBlockExplorer -- start
	pm2 save
	pm2 startup ubuntu

	# Yeah, we are probably putting to many comments in this script, but I hope it proves
	# helpful to someone when they are having fun but don't know what a part of it does.

	print_success "Lynx Block Explorer was installed"
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

		apt-get install libminiupnpc-dev -y	&> /dev/null

		print_success "Miniupnpc was installed."

	fi

}

install_lynx () {

	echo "$pretty_name detected. Installing Lynx."

	apt-get install git-core build-essential autoconf libtool libssl-dev libboost-all-dev libminiupnpc-dev libevent-dev libncurses5-dev pkg-config -y &> /dev/null

	rrpcuser="$(shuf -i 1000000000-3999999999 -n 1)$(shuf -i 1000000000-3999999999 -n 1)$(shuf -i 1000000000-3999999999 -n 1)"

	rrpcpassword="$(shuf -i 1000000000-3999999999 -n 1)$(shuf -i 1000000000-3999999999 -n 1)$(shuf -i 1000000000-3999999999 -n 1)"

	rm -rf /root/lynx/

	git clone https://github.com/doh9Xiet7weesh9va9th/lynx.git /root/lynx/ &> /dev/null

	cd /root/lynx/ && ./autogen.sh &> /dev/null

	# If it's a Pi device then set up the uPNP arguments.

	if [ ! -z "$checkForRaspbian" ]; then
		./configure --enable-cxx --without-gui --disable-wallet --disable-tests --with-miniupnpc --enable-upnp-default &> /dev/null && make &> /dev/null
	else
		./configure --enable-cxx --without-gui --disable-wallet --disable-tests &> /dev/null && make &> /dev/null
	fi

	# In the past, we used a bootstrap file to get the full blockchain history to load faster. This
	# was very helpful but it did bring up a security concern. If the bootstrap file had been
	# tampered with (even though it was created by Lynx dev team) it might prove a security risk.
	# So now that the seed nodes run faster and new node discovery is much more efficient, we are
	# phasing out the use of the bootstrap file.

	# Below we are creating the default lynx.conf file. This file is created with the dynamically
	# created RPC credentials and it sets up the networking with settings that testing has found to
	# work well in the LynxCI build. Of course, you can edit it further if you like, but this
	# default file is the recommended start point.

	cd ~/ && rm -rf .lynx && mkdir .lynx

	echo "
	listen=1
	daemon=1
	rpcuser=$rrpcuser
	rpcpassword=$rrpcpassword
	rpcport=$rpcport
	port=$port
	rpcbind=127.0.0.1
	rpcbind=::1
	rpcallowip=0.0.0.0/24
	rpcallowip=::/0
	listenonion=0
	upnp=1
	txindex=1
	$lynxconfig

	addnode=seed1.getlynx.io
	addnode=seed2.getlynx.io
	addnode=seed3.getlynx.io
	addnode=seed4.getlynx.io
	addnode=seed5.getlynx.io

	" > /root/.lynx/lynx.conf

	chown -R root:root /root/.lynx/*

	print_warning "Lynx was installed without wallet functions."

}

install_miner () {

	echo "$pretty_name detected. Installing CPUMiner-Multi."

	apt-get update -y &> /dev/null

	apt-get install automake autoconf pkg-config libcurl4-openssl-dev libjansson-dev libssl-dev libgmp-dev make g++ libz-dev git -y &> /dev/null

	git clone https://github.com/tpruvot/cpuminer-multi.git /tmp/cpuminer/ &> /dev/null

	cd /tmp/cpuminer/ && ./build.sh &> /dev/null

	make install &> /dev/null

	echo "CPUMiner-Multi 1.3.5 was installed."

}

install_mongo () {

	if [ "$version_id" = "9" ]; then

		if [ -z "$checkForRaspbian" ]; then

			print_success "$pretty_name detected. Installing Mongo 4.0."

			apt-get install dirmngr -y &> /dev/null

 			apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 9DA31620334BD75D9DCB49F368818C72E52529D4 &> /dev/null

 			echo "deb http://repo.mongodb.org/apt/debian stretch/mongodb-org/4.0 main" | tee /etc/apt/sources.list.d/mongodb-org-4.0.list &> /dev/null

 			apt-get update -y &> /dev/null && apt-get install -y mongodb-org &> /dev/null

			systemctl start mongod &> /dev/null && systemctl enable mongod &> /dev/null

			sleep 5

			account="{ user: 'x${rrpcuser}', pwd: 'x${rrpcpassword}', roles: [ 'readWrite' ] }"

			mongo lynx --eval "db.createUser( ${account} )" &> /dev/null

			print_success "Mongo 4.0 was installed."

		else

			print_success "$pretty_name detected. Installing Mongo."

			apt-get install mongodb-server -y &> /dev/null

			service mongodb start &> /dev/null

			sleep 5

			account="{ user: 'x${rrpcuser}', pwd: 'x${rrpcpassword}', roles: [ 'readWrite' ] }"

			mongo lynx --eval "db.addUser( ${account} )" &> /dev/null

			print_success "Mongo 2.4 was installed."

		fi

	elif [ "$version_id" = "8" ]; then

		print_success "$pretty_name detected. Installing Mongo 4.0."

		apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 9DA31620334BD75D9DCB49F368818C72E52529D4 &> /dev/null

		echo "deb http://repo.mongodb.org/apt/debian jessie/mongodb-org/4.0 main" | tee /etc/apt/sources.list.d/mongodb-org-4.0.list &> /dev/null

		apt-get update -y &> /dev/null && apt-get install -y mongodb-org &> /dev/null &> /dev/null

		systemctl start mongod &> /dev/null && systemctl enable mongod &> /dev/null

		sleep 5

		account="{ user: 'x${rrpcuser}', pwd: 'x${rrpcpassword}', roles: [ 'readWrite' ] }"

		mongo lynx --eval "db.createUser( ${account} )" &> /dev/null

		print_success "Mongo 4.0 was installed."

	elif [ "$version_id" = "16.04" ]; then

		print_success "$pretty_name detected. Installing Mongo 4.0."

		apt-get update -y &> /dev/null

		sleep 5

		apt-get install apt-transport-https -y &> /dev/null

		apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 9DA31620334BD75D9DCB49F368818C72E52529D4 &> /dev/null

		echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/4.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-4.0.list &> /dev/null

		apt-get update -y &> /dev/null && apt-get install -y mongodb-org &> /dev/null

		echo "

		[Unit]
		Description=High-performance, schema-free document-oriented database
		After=network.target
		Documentation=https://docs.mongodb.org/manual

		[Service]
		User=mongodb
		Group=mongodb
		ExecStart=/usr/bin/mongod --quiet --config /etc/mongod.conf

		[Install]
		WantedBy=multi-user.target

		" > /lib/systemd/system/mongod.service

		systemctl daemon-reload &> /dev/null && systemctl start mongod &> /dev/null && systemctl enable mongod &> /dev/null

		sleep 5

		account="{ user: 'x${rrpcuser}', pwd: 'x${rrpcpassword}', roles: [ 'readWrite' ] }"

		mongo lynx --eval "db.createUser( ${account} )" &> /dev/null

		print_success "Mongo 4.0 was installed."

	elif [ "$version_id" = "18.04" ]; then

		print_success "$pretty_name detected. Installing Mongo 4.0."

		apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 9DA31620334BD75D9DCB49F368818C72E52529D4 &> /dev/null

		echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-4.0.list &> /dev/null

		apt-get update -y &> /dev/null && apt-get install -y mongodb-org &> /dev/null

		systemctl start mongod &> /dev/null && systemctl enable mongod &> /dev/null

		sleep 5

		account="{ user: 'x${rrpcuser}', pwd: 'x${rrpcpassword}', roles: [ 'readWrite' ] }"

		mongo lynx --eval "db.createUser( ${account} )" &> /dev/null

		print_success "Mongo 4.0 was installed."

	fi

}

set_firewall () {

	# To make sure we don't create any problems, let's truly make sure the firewall instructions
	# we are about to create haven't already been created. So we delete the file we are going to
	# create in the next step. This is just a step to insure stability and reduce risk in the 
	# execution of this build script.

	rm -rf /root/firewall.sh

	echo "

	#!/bin/bash

	IsSSH=Y

	# Let's flush any pre existing iptables rules that might exist and start with a clean slate.

	/sbin/iptables -F

	# We should always allow loopback traffic.

	/sbin/iptables -I INPUT 1 -i lo -j ACCEPT

	# This line of the script tells iptables that if we are already authenticated, then to ACCEPT
	# further traffic from that IP address. No need to recheck every packet if we are sure they
	# aren't a bad guy.

	/sbin/iptables -I INPUT 2 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

	# If the script has IsSSH set to Y, then let's open up port 22 for any IP address. But if
	# the script has IsSSH set to N, let's only open up port 22 for local LAN access. This means
	# you have to be physically connected (or via Wifi) to SSH to this computer. It isn't perfectly
	# secure, but it removes the possibility for an SSH attack from a public IP address. If you
	# wanted to completely remove the possibility of an SSH attack and will only ever work on this
	# computer with your own physically attached KVM (keyboard, video & mouse), then you can comment
	# the following 6 lines. Be careful, if you don't understand what you are doing here, you might
	# lock yourself from being able to access this computer. If so, just go through the build
	# process again and start over.

	if [ \"\$IsSSH\" = \"Y\" ]; then
		/sbin/iptables -A INPUT -p tcp --dport 22 -j ACCEPT
	else
		/sbin/iptables -A INPUT -p tcp -s 10.0.0.0/8 --dport 22 -j ACCEPT
		/sbin/iptables -A INPUT -p tcp -s 192.168.0.0/16 --dport 22 -j ACCEPT
	fi

	# Becuase the Block Explorer or Block Crawler are available via port 80 (standard website port)
	# we must open up port 80 for that traffic.

	/sbin/iptables -A INPUT -p tcp --dport 80 -j ACCEPT

	# This Lynx node listens for other Lynx nodes on port $port, so we need to open that port. The
	# whole Lynx network listens on that port so we always want to make sure this port is available.

	/sbin/iptables -A INPUT -p tcp --dport $port -j ACCEPT

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

	print_success "Firewall rules are set in /root/firewall.sh"

	chmod 700 /root/firewall.sh

}

set_miner () {

	rm -rf /root/miner.sh

	echo "
	#!/bin/bash

	# This valus is set during the initial build of this node by the LynxCI installer. You can
	# override it by changing the value. Acceptable options are Y and N. If you set the value to
	# N, this node will not mine blocks, but it will still confirm and relay transactions.

	IsMiner=Y

	# The objective of this script is to start the local miner and have it solo mine against the
	# local Lynx processes. So the first think we should do is assume a mining process is already
	# running and kill it.

	pkill -f cpuminer

	# Let's wait 2 seconds and give the task a moment to finish.

	sleep 2

	# If the flag to mine is set to Y, then lets do some mining, otherwise skip this whole
	# conditional. Seems kind of obvious, but some of us are still learning.

	if [ \"\$IsMiner\" = \"Y\" ]; then

		# Mining isnt very helpful if the process that run's Lynx isn't actually running. Why bother
		# running all this logic if Lynx isn't ready? Unfortunaately, this isnt the only check we need
		# to do. Just because Lynx might be running, it might not be in sync yet, and running the miner
		# doesnt make sense yet either. So, lets check if Lynxd is running and if it is, then we check
		# to see if the blockheight of the local node is _close_ to the known network block height. If
		# so, then we let the miner turn on.

		if pgrep -x \"lynxd\" > /dev/null; then

			# Only if the miner isn't running. We do this to ensure we don't accidently have two
			# miner processes running at the same time.

			if ! pgrep -x \"cpuminer\" > /dev/null; then

				# The Lynx network has a family of seed nodes that are publicly available. By querying
				# this single URL, the request will be randomly redirected to an active seed node. If
				# a seed node is down for whatever reason, the next query will probably select a
				# different seed node since no session management is used.

				remote=\$(curl -sL $explorer)

				# Since we know that Lynx is running, we can query our local instance for the current
				# block height.

				local=\$(/root/lynx/src/lynx-cli getblockcount)
				local=\$(expr \$local + 60)

				if [ \"\$local\" -ge \"\$remote\" ]; then

					# Just to make sure, lets purge any spaces of newlines in the file, so we don't
					# accidently pick one.

					chmod 644 /root/LynxNodeBuilder/miner-add*

					# Randomly select an address from the addresse file. You are welcome to change 
					# any value in that list.

					random_address=\"\$(shuf -n 1 /root/LynxNodeBuilder/$addresses)\"

					# With the randomly selected reward address, lets start solo mining.

					/usr/local/bin/cpuminer -o http://127.0.0.1:$rpcport -u $rrpcuser -p $rrpcpassword --no-longpoll --no-getwork --no-stratum --coinbase-addr=\"\$random_address\" -t 1 -R 15 -B -S
	
				fi

			fi

		fi

	fi

	# If the process that throttles the miner is already running, then kill it. Just to be sure.

	pkill -f cpulimit

	# Let's wait 2 seconds and give the task a moment to finish.

	sleep 2

	# If the miner flag is set to Y, the execute this conditional group.

	if [ \"\$IsMiner\" = \"Y\" ]; then

		# Only set the limiter if the miner is actually running. No need to start the process if not
		# needed.

		if pgrep -x \"cpuminer\" > /dev/null; then

			# Only if the cpulimit process isn't already running, then start it.

			if ! pgrep -x \"cpulimit\" > /dev/null; then

				# Let's set the amount of CPU that the process cpuminer can use to 5%.

				cpulimit -e cpuminer -l 5 -b
			fi

		fi

	fi

	#
	# Metus est Plenus Tyrannis
	#" > /root/miner.sh

	chmod 700 /root/miner.sh
	chown root:root /root/miner.sh

}

# This function is still under development.

install_ssl () {

	#https://calomel.org/lets_encrypt_client.html
	print_success "SSL creation scripts are still in process."

}

# This function is still under development.

install_tor () {

	apt install tor
	systemctl enable tor
	systemctl start tor

	echo "
	ControlPort 9051
	CookieAuthentication 1
	CookieAuthFileGroupReadable 1
	" >> /etc/tor/torrc

	usermod -a -G debian-tor root

}

secure_iptables () {

	iptables -F
	iptables -I INPUT 1 -i lo -j ACCEPT
	iptables -I INPUT 2 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
	iptables -A INPUT -p tcp --dport 22 -j ACCEPT
	iptables -A INPUT -j DROP

}

config_fail2ban () {
	#
	# Configure fail2ban defaults function
	#

	#
	# The default ban time for abusers on port 22 (SSH) is 10 minutes. Lets make this a full 24 hours
	# that we will ban the IP address of the attacker. This is the tuning of the fail2ban jail that
	# was documented earlier in this file. The number 86400 is the number of seconds in a 24 hour term.
	# Set the bantime for lynxd on port 22566/44566 banned regex matches to 24 hours as well.

	echo "

	[sshd]
	enabled = true
	bantime = 86400


	[lynxd]
	enabled = false
	bantime = 86400

	" > /etc/fail2ban/jail.d/defaults-debian.conf

	#
	#
	# Configure the fail2ban jail for lynxd and set the frequency to 20 min and 3 polls.

	echo "

	#
	# SSH
	#

	[sshd]
	port		= ssh
	logpath		= %(sshd_log)s

	#
	# LYNX
	#

	[lynxd]
	port		= $port
	logpath		= /root/.lynx/debug.log
	findtime	= 1200
	maxretry	= 3

	" > /etc/fail2ban/jail.local

	# Define the regex pattern for lynxd failed connections

	echo "

	#
	# Fail2Ban lynxd regex filter for at attempted exploit or inappropriate connection
	#
	# The regex matches banned and dropped connections
	# Processes the following logfile /root/.lynx/debug.log
	#

	[INCLUDES]

	# Read common prefixes. If any customizations available -- read them from
	# common.local
	before = common.conf

	[Definition]

	#_daemon = lynxd

	failregex = ^.* connection from <HOST>.*dropped \(banned\)$

	ignoreregex =

	# Author: The Lynx Core Development Team

	" > /etc/fail2ban/filter.d/lynxd.conf

	#
	#
	# With the extra jails added for monitoring lynxd, we need to touch the debug.log file for fail2ban to start without error.
	mkdir /root/.lynx/
	chmod 755 /root/.lynx/
	touch /root/.lynx/debug.log

	service fail2ban start

}

setup_crontabs () {
	
	# In the event that any other crontabs exist, let's purge them all.

	crontab -r

	# The following 3 lines set up respective crontabs to run every 15 minutes. These send a polling
	# signal to the listed URL's. The ONLY data we collect is the MAC address, public and private
	# IP address and the latest known Lynx block heigh number. This allows development to more 
	# accurately measure network usage and allows the pricing calculator and mapping code used by
	# Lynx to be more accurate. If you want to turn off particiaption in the polling service, all
	# you have to do is remove the following 3 crontabs.

	crontab -l | { cat; echo "*/15 * * * *		/root/LynxNodeBuilder/poll.sh http://seed00.getlynx.io:8080"; } | crontab -
	crontab -l | { cat; echo "*/15 * * * *		/root/LynxNodeBuilder/poll.sh http://seed01.getlynx.io:8080"; } | crontab -
	crontab -l | { cat; echo "*/15 * * * *		/root/LynxNodeBuilder/poll.sh http://seed02.getlynx.io:8080"; } | crontab -

	# Every 15 minutes we reset the firewall to it's default state. Additionally we reset the miner.
	# The lynx daemon needs to be checked too, so we restart it if it crashes (which has been been
	# known to happen on low RAM devices during blockchain indexing.)

	crontab -l | { cat; echo "*/15 * * * *		/root/firewall.sh"; } | crontab -
	crontab -l | { cat; echo "*/15 * * * *		/root/lynx/src/lynxd"; } | crontab -
	crontab -l | { cat; echo "*/15 * * * *		/root/miner.sh"; } | crontab -

	# As the update script grows with more self updating features, we will let this script run every 
	# 24 hours. This way, users don't have to rebuild the LynxCI build as often to get new updates.

	crontab -l | { cat; echo "0 0 * * *		/root/update.sh"; } | crontab -

	# We found that after a few weeks, the debug log would grow rather large. It's not really needed
	# after a certain size, so let's truncate that log down to a reasonable size every day.

	crontab -l | { cat; echo "0 0 * * *		truncate -s 1KB /root/.lynx/debug.log"; } | crontab -

	# Evey 15 days we will reboot the device. This is for a few reasons. Since the device is often
	# not actively managed by it's owner, we can't assume it is always running perfectly so an
	# occasional reboot won't cause harm. This crontab means to reboot EVERY 15 days, NOT on the
	# 15th day of the month. An important distinction.

	crontab -l | { cat; echo "0 0 */15 * *		/sbin/shutdown -r now"; } | crontab -

	# This conditional determines if the local machine has more then 1024 MB of RAM available. If it
	# does, then we assume the device can handle a little more work, so we run processes that
	# consume more RAM. If it does not evaluate positive, then we run the lightweight processes.
	# For refernence, 1,024,000 KB = 1024 MB

	if [[ "$(awk '/MemTotal/' /proc/meminfo | sed 's/[^0-9]*//g')" -gt "512000" ]]; then

		crontab -l | { cat; echo "*/2 * * * *		cd /root/LynxExplorer && scripts/check_server_status.sh"; } | crontab -
		crontab -l | { cat; echo "*/3 * * * *		cd /root/LynxExplorer && /usr/bin/nodejs scripts/sync.js index update >> /tmp/explorer.sync 2>&1"; } | crontab -
		crontab -l | { cat; echo "*/4 * * * *		cd /root/LynxExplorer && /usr/bin/nodejs scripts/sync.js market > /dev/null 2>&1"; } | crontab -
		crontab -l | { cat; echo "*/10 * * * *		cd /root/LynxExplorer && /usr/bin/nodejs scripts/peers.js > /dev/null 2>&1"; } | crontab -

	fi

}

restart () {

	# We now write this empty file to the /boot dir. This file will persist after reboot so if
	# this script were to run again, it would abort because it would know it already ran sometime
	# in the past. This is another way to prevent a loop if something bad happens during the install
	# process. At least it will fail and the machine won't be looping a reboot/install over and 
	# over. This helps if we have ot debug a problem in the future.

	/usr/bin/touch /boot/ssh

	print_success "LynxCI was installed."
	
	print_success "A reboot will occur 10 seconds."

	sleep 10

	reboot

}

# First thing, we check to see if this script already ran in the past. If the file "/boot/ssh"
# exists, we know it previously ran. 

if [ -f /boot/ssh ]; then

	print_error "Previous LynxCI detected. Install aborted."

else

	print_error "Starting installation of LynxCI."

	detect_os
	install_extras
	detect_vps
	set_network
	expand_swap
	reduce_gpu_mem
	disable_bluetooth
	set_wifi
	set_accounts
	install_portcheck
	install_miniupnpc
	#install_lynx
	install_mongo
	install_explorer
	install_miner
	set_firewall
	set_miner
	secure_iptables
	config_fail2ban
	setup_crontabs
	restart

fi

