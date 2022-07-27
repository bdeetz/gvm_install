#!/usr/bin/env bash

set -e
set -o pipefail

# verify we are running as the correct user
if [[ "$(whoami)" != "root" ]]
then
  printf "ERROR: You must be root to execute this script. Exiting\n\n"
  exit 1
fi

# stop the services being worked on
systemctl stop openvas
systemctl stop gvm.path
systemctl stop gvm.service
systemctl stop gsa.path
systemctl stop gsa.service

# upgrade the host to the latest packages and kernel
apt-get update
apt-get upgrade
apt-get dist-upgrade

# where repos get cloned to and built from
dest_dir="/opt/gvm"

cd ${dest_dir}

# delete the artifacts of the old deployment
rm -rf /opt/gvm/bin
rm -rf /opt/gvm/etc/
rm -rf /opt/gvm/lib/
rm -rf /opt/gvm/var/
rm -rf /opt/gvm/share/
rm -rf /opt/gvm/sbin/
rm -rf /opt/gvm/include/

# update the shared library path to the new destination
echo "/usr/local/lib" > /etc/ld.so.conf.d/gvm.conf
ldconfig

###########################################
# build gvm-libs
###########################################
repo="gvm-libs"
repo_path="${dest_dir}/${repo}"

rm -rf ${repo_path}

git clone -b v21.4.4 https://github.com/greenbone/gvm-libs.git ${repo_path}

install_script="${dest_dir}/install_gvm_libs.sh"

cat << EOF > ${install_script}
#!/usr/bin/env bash

set -e

export PKG_CONFIG_PATH=/opt/gvm/lib/pkgconfig:/usr/local/lib/pkgconfig/:$PKG_CONFIG_PATH

mkdir -p /opt/gvm/gvm-libs/build
cd /opt/gvm/gvm-libs/build
cmake ..
make
make install
EOF

chmod 755 ${install_script}

${install_script}
ldconfig

###########################################
# Build and Install OpenVAS SMB
###########################################
repo="openvas-smb"
repo_path="${dest_dir}/${repo}"

rm -rf ${repo_path}

git clone -b v21.4.0 https://github.com/greenbone/openvas-smb.git ${repo_path}

install_script="${dest_dir}/install_openvas_smb.sh"

cat << EOF > ${install_script}
#!/usr/bin/env bash

set -e

cd /opt/gvm/openvas-smb/
mkdir -p /opt/gvm/openvas-smb/build
cd /opt/gvm/openvas-smb/build

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/:$PKG_CONFIG_PATH

cmake ..
make
make install
EOF

chmod 755 ${install_script}

${install_script}
ldconfig

###########################################
# Build and Install OpenVAS
###########################################
repo="openvas"
repo_path="${dest_dir}/${repo}"

rm -rf ${repo_path}

git clone -b v21.4.4 https://github.com/greenbone/openvas.git ${repo_path}

install_script="${dest_dir}/install_openvas.sh"

cat << EOF > ${install_script}
#!/usr/bin/env bash

set -e

mkdir -p /opt/gvm/openvas/build
cd /opt/gvm/openvas/build

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/:$PKG_CONFIG_PATH
cmake ..
make
make install
EOF

chmod 755 ${install_script}

${install_script}
ldconfig

###########################################
# Build and Install Greenbone Vulnerability Manager
###########################################
repo="gvmd"
repo_path="${dest_dir}/${repo}"

rm -rf ${repo_path}

git clone -b v21.4.5 https://github.com/greenbone/gvmd.git ${repo_path}

install_script="${dest_dir}/install_gvm.sh"

cat << EOF > ${install_script}
#!/usr/bin/env bash

set -e

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/:$PKG_CONFIG_PATH

mkdir -p /opt/gvm/gvmd/build
cd /opt/gvm/gvmd/build

cmake -DGVMD_RUN_DIR=/var/run/gvmd/ -DGVMD_PID_PATH=/var/run/gvmd/gvmd.pid ..
cmake ..

make
make install
EOF

chmod 755 ${install_script}

${install_script}
ldconfig

# allow the gvm user to sudo for openvas
echo "gvm ALL = NOPASSWD: /usr/local/sbin/openvas" >> /etc/sudoers.d/gvm

# create a systemd unit file for the service
cat << EOF > /etc/systemd/system/gvmd.service
[Unit]
RuntimeDirectory=gvmd
Description=Greenbone Vulnerability Manager daemon (gvmd)
After=network.target postgresql.service ospd-openvas.service
Wants=postgresql.service ospd-openvas.service
Documentation=man:gvmd(8)
ConditionKernelCommandLine=!recovery

[Service]
Type=forking
User=gvm
PIDFile=/run/gvmd/gvmd.pid
RuntimeDirectory=gvmd
RuntimeDirectoryMode=2775
ExecStart=/usr/local/sbin/gvmd --osp-vt-update=/run/ospd/ospd-openvas.sock --listen-group=gvm
Restart=always
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF


###########################################
# Install GVM Tools
###########################################
pip install gvm-tools


###########################################
# Build and Install Greenbone Secuirty Assistant UI Components
###########################################
# gsa
repo="gsa"
repo_path="${dest_dir}/${repo}"

rm -rf ${repo_path}

git clone -b v21.4.4 https://github.com/greenbone/gsa.git ${repo_path}

install_script="${dest_dir}/install_gsa.sh"

cat << EOF > ${install_script}
#!/usr/bin/env bash

set -e

cd /opt/gvm/gsa

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/:$PKG_CONFIG_PATH

yarn
yarn build
yarn install
EOF

chmod 755 ${install_script}

${install_script}
ldconfig


###########################################
# Build and Install Greenbone Secuirty Assistant UI Server
###########################################
# gsad
repo="gsad"
repo_path="${dest_dir}/${repo}"

rm -rf ${repo_path}

git clone -b v21.4.4 https://github.com/greenbone/gsad.git ${repo_path}

install_script="${dest_dir}/install_gsad.sh"

cat << EOF > ${install_script}
#!/usr/bin/env bash

set -e

cd /opt/gvm/gsad
mkdir -p /opt/gvm/gsad/build
cd /opt/gvm/gsad/build

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/:$PKG_CONFIG_PATH

cmake ..
make
make install

mkdir -p /usr/local/share/gvm/gsad/web/
cp -r /opt/gvm/gsa/build/* /usr/local/share/gvm/gsad/web/
chown -R gvm:gvm /usr/local/share/gvm
EOF

chmod 755 ${install_script}

${install_script}
ldconfig

# create systemd unit file for the gsad service
cat << EOF > /etc/systemd/system/gsad.service
[Unit]
Description=Greenbone Security Assistant daemon (gsad)
Documentation=man:gsad(8) https://www.greenbone.net
After=network.target gvmd.service
Wants=gvmd.service

[Service]
RuntimeDirectory=gsad
Type=forking
User=gvm
Group=gvm
PIDFile=/run/gsad/gsad.pid
ExecStart=/usr/local/sbin/gsad --ssl-private-key=/var/lib/gvm/CA/servercert.key
Restart=always
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
Alias=greenbone-security-assistant.service
EOF

###########################################
# Build and Install OSPd and OSPd-OpenVAS
###########################################
# ospd
repo="ospd"
repo_path="${dest_dir}/${repo}"

rm -rf ${repo_path}

git clone -b v21.4.4 https://github.com/greenbone/ospd.git ${repo_path}

# ospd-openvas
repo="ospd-openvas"
repo_path="${dest_dir}/${repo}"

rm -rf ${repo_path}

git clone -b v21.4.4 https://github.com/greenbone/ospd-openvas.git ${repo_path}

install_script="${dest_dir}/install_ospd.sh"

cat << EOF > ${install_script}
#!/usr/bin/env bash

set -e

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/:$PKG_CONFIG_PATH

cd /opt/gvm/ospd
python3 setup.py install

cd ../ospd-openvas
python3 -m pip install --user poetry
/root/.local/bin/poetry install
EOF

chmod 755 ${install_script}

${install_script}
ldconfig

# create a systemd unit file for the ospd-openvas service
cat << EOF > /etc/systemd/system/ospd-openvas.service
[Unit]
Description=OSPd Wrapper for the OpenVAS Scanner (ospd-openvas)
Documentation=man:ospd-openvas(8) man:openvas(8)
After=network.target networking.service redis-server@openvas.service
Wants=redis-server@openvas.service
ConditionKernelCommandLine=!recovery

[Service]
RuntimeDirectory=ospd
Type=simple
User=gvm
Group=gvm
Environment=PATH=/opt/gvm/ospd-openvas/.venv/bin/:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/opt/gvm/bin:/opt/gvm/sbin:/opt/gvm/.local/bin
RuntimeDirectory=ospd
RuntimeDirectoryMode=2775
PIDFile=/run/ospd/ospd-openvas.pid
ExecStart=/opt/gvm/ospd-openvas/.venv/bin/ospd-openvas --config /etc/gvm/ospd-openvas.conf --log-config /etc/gvm/ospd-logging.conf
SuccessExitStatus=SIGKILL
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF


###########################################
# Housekeeping
###########################################
# allow the gvm user to attach to the redis socket
usermod -a -G redis gvm

# configure openvas to connect to redis using a socket rather than IP
echo "db_address = /run/redis-openvas/redis.sock" > /etc/openvas/openvas.conf

# configure ospd-openvas
cp /opt/gvm/ospd-openvas/config/ospd-openvas.conf /etc/gvm/ospd-openvas.conf

# configure ospd-openvas logging
cp /opt/gvm/ospd-openvas/docs/example-ospd-logging.conf /etc/gvm/ospd-logging.conf

# remove old systemd unit files that have been replaced with better ones
rm /etc/systemd/system/gsa.path
rm /etc/systemd/system/gsa.service
rm /etc/systemd/system/gvm.path
rm /etc/systemd/system/gvm.service
rm /etc/systemd/system/openvas.service

# ensure gvm user has access to appropriate directories
mkdir -p /var/log/gvm/
chown -R gvm:gvm /var/log/gvm/

mkdir -p /var/lib/gvm/gvmd/gnupg
chown -R gvm:gvm /var/lib/gvm

mkdir -p /var/lib/openvas/
chown -R gvm:gvm /var/lib/openvas/

chown -R gvm:gvm /usr/local/share/gvm

# allow gvm user to open a socket on privileged ports when running the gsad binary
sudo setcap CAP_NET_BIND_SERVICE=+eip /usr/local/sbin/gsad

# create a directory for the gsad certificate to be placed
mkdir -p /var/lib/gvm/CA/

# create a self signed certificate for the vulnerability scanner
openssl req -x509 -newkey rsa:2048 -nodes -days 3640 -keyout /var/lib/gvm/CA/servercert.key -out /var/lib/gvm/CA/servercert.pem -subj "/C=US/ST=NY/L=NY/O=ActionIQ/OU=Security/CN=gsa.security.actioniq.co"

# allow the gvm user to access its certificate
chown -R gvm:gvm /var/lib/gvm/CA/

ldconfig

# remove all existing cron jobs from the gvm user's crontab
echo "" | crontab -u gvm -

# create cron jobs to a more appropriate location
cat << EOF > /etc/cron.d/gvm
59 3 * * * gvm /usr/local/sbin/greenbone-feed-sync --type SCAP
7 23 * * * gvm /usr/local/bin/greenbone-nvt-sync
56 5 * * * gvm /usr/local/sbin/greenbone-feed-sync --type CERT
58 20 * * * gvm /usr/local/sbin/greenbone-feed-sync --type GVMD_DATA
25 18 * * * gvm /usr/bin/sudo /usr/local/sbin/openvas --update-vt-info
EOF

# load the new unit files
systemctl daemon-reload

# enable the new services
systemctl enable gsad
systemctl enable gvmd
systemctl enable ospd-openvas

# start the services
systemctl start ospd-openvas
systemctl start gvmd
systemctl start gsad

# begin syncing threat feeds
sudo -u gvm /usr/local/sbin/greenbone-feed-sync --type SCAP
sudo -u gvm /usr/local/bin/greenbone-nvt-sync
sudo -u gvm /usr/local/sbin/greenbone-feed-sync --type CERT
sudo -u gvm /usr/local/sbin/greenbone-feed-sync --type GVMD_DATA
su gvm -c /usr/bin/sudo /usr/local/sbin/openvas --update-vt-info
