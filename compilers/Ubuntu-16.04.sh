#!/bin/bash

CONF_DIR="/root/.lynx/"
CONF_FILE="${CONF_DIR}/lynx.conf"
GIT_URL="https://github.com/getlynx/lynx.git"
GIT_BRANCH="master"
GIT_DIR="/root/lynx"
#SSL_VERSION="1.0.0" # <-- DEBIAN
SSL_VERSION="" # <-- UBUNTU (blank)
LIBRARIES="libssl${SSL_VERSION}-dev libboost-all-dev libevent-dev libminiupnpc-dev"
DEV_TOOLS="build-essential libtool autotools-dev autoconf cmake pkg-config bsdmainutils git wget"

# Ubuntu 16.04 Requirement
add-apt-repository -y ppa:bitcoin/bitcoin
apt-get -qq update -y
apt-get -qq install -y libdb4.8-dev
apt-get -qq install -y libdb4.8++-dev

touch ${CONF_FILE}

cd /root
apt-get -qq update -y
apt-get -qq install -y ${DEV_TOOLS} ${LIBRARIES}
git clone --branch ${GIT_BRANCH} --single-branch ${GIT_URL} ${GIT_DIR}
cd ${GIT_DIR}
./autogen.sh
./configure --without-gui --disable-tests --disable-bench
make -j$(nproc)
make install

# Build the DEB
rm -Rf /root/lynxd
rm -Rf /root/lynxd/DEBIAN/postinst*
rm -Rf /root/lynxd_16.3.5-1_amd64.deb
mkdir lynxd && mkdir lynxd/DEBIAN
mkdir -p lynxd/usr/local/bin/

# Lets place all the files and dependencies we need into the package.

cp /usr/local/bin/lynx* lynxd/usr/local/bin/
cp /usr/lib/x86_64-linux-gnu/libboost_system.so.1.58.0 lynxd/usr/lib/x86_64-linux-gnu/libboost_system.so.1.58.0
cp /usr/lib/x86_64-linux-gnu/libboost_filesystem.so.1.58.0 lynxd/usr/lib/x86_64-linux-gnu/libboost_filesystem.so.1.58.0
cp /usr/lib/x86_64-linux-gnu/libboost_program_options.so.1.58.0 lynxd/usr/lib/x86_64-linux-gnu/libboost_program_options.so.1.58.0
cp /usr/lib/x86_64-linux-gnu/libboost_thread.so.1.58.0 lynxd/usr/lib/x86_64-linux-gnu/libboost_thread.so.1.58.0
cp /usr/lib/x86_64-linux-gnu/libboost_chrono.so.1.58.0 lynxd/usr/lib/x86_64-linux-gnu/libboost_chrono.so.1.58.0
cp /usr/lib/x86_64-linux-gnu/libssl.so lynxd/usr/lib/x86_64-linux-gnu/libssl.so
cp /usr/lib/x86_64-linux-gnu/libcrypto.so lynxd/usr/lib/x86_64-linux-gnu/libcrypto.so

echo "

Package: lynxd
Version: 0.16.3.5
Maintainer: Lynx Core Development Team
Architecture: all
Description: https://getlynx.io

" > /root/lynxd/DEBIAN/control

wget https://raw.githubusercontent.com/getlynx/LynxCI/master/compilers/postinst ‐P /lynxd/DEBIAN 

chmod -R 755 /root/lynxd/*

cd /root/ && dpkg-deb --build lynxd

mv lynxd.deb lynxd_16.3.5-1_amd64.deb

#curl -sLO http://cdn.getlynx.io/lynxd_16.3.5-1_amd64.deb && dpkg -i lynxd_16.3.5-1_amd64.deb
#curl -sLO http://cdn.getlynx.io/lynxd.deb && dpkg -i lynxd.deb
