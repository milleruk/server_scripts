#!/bin/bash
PHP_MEMORY_LIMIT=256M
PHP_POST_MAX_SIZE=128M
PHP_UPLOAD_MAX_FILESIZE=128M
NR_CPUS=$(grep -c ^processor /proc/cpuinfo) 
IP=`ifconfig  | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}'`

export DEBIAN_FRONTEND=noninteractive

############## Iptables
# Only allow SSH, HTTP and HTTPS 
cat >> /etc/iptables.rules <<EOL
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [62117:57253927]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT 
-A INPUT -p icmp -j ACCEPT 
-A INPUT -i lo -j ACCEPT 
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT 
-A INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT 
-A INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT 
-A INPUT -j REJECT --reject-with icmp-host-prohibited 
-A FORWARD -j REJECT --reject-with icmp-host-prohibited 
COMMIT
EOL

iptables-restore /etc/iptables.rules

echo '#!/bin/sh' > /etc/network/if-pre-up.d/iptables
echo '/sbin/iptables-restore < /etc/iptables.rules' >> /etc/network/if-pre-up.d/iptables
chmod +x /etc/network/if-pre-up.d/iptables

##############  NGINX 
wget http://nginx.org/keys/nginx_signing.key
apt-key add nginx_signing.key
echo 'deb http://nginx.org/packages/mainline/debian/ jessie nginx' >> /etc/apt/sources.list
echo 'deb-src http://nginx.org/packages/mainline/debian/ jessie nginx' >> /etc/apt/sources.list

apt-get -y update && apt-get upgrade
apt-get -y install nginx mariadb-server mariadb-client php5-fpm php5-mysqlnd php5-curl php5-gd php-pear php5-imagick php5-mcrypt php5-memcache php5-xmlrpc php5-intl curl git unzip sudo pwgen apache2-utils rsync

sed -i 's/worker_processes .*/worker_processes '${NR_CPUS}';/' /etc/nginx/nginx.conf
sed -i -e"s/keepalive_timeout\s*65/keepalive_timeout 2/" /etc/nginx/nginx.conf
sed -i -e"s/keepalive_timeout 2/keepalive_timeout 2;\n\tclient_max_body_size '${PHP_POST_MAX_SIZE}'/" /etc/nginx/nginx.conf

mkdir -p /var/www/html
chown www-data:www-data /var/www/html

# I Prefer to have sites in /opt/sites
mkdir -p /opt/sites/
chown www-data:www-data /opt/sites/


# to generate your dhparam.pem file, run in the terminal - needed for SSL Lets Encrtpy Later
openssl dhparam -out /etc/nginx/dhparam.pem 2048

# Put standard nginx config in place. Ready for addnewsite.sh
wget -O /etc/nginx/conf.d/nginx_extra.conf https://raw.githubusercontent.com/milleruk/server_scripts/master/nginx_extra.conf

############## PHP
sed -i 's/memory_limit = .*/memory_limit = '${PHP_MEMORY_LIMIT}'/' /etc/php5/cli/php.ini
sed -i 's/memory_limit = .*/memory_limit = '${PHP_MEMORY_LIMIT}'/' /etc/php5/fpm/php.ini
sed -i 's/post_max_size = .*/post_max_size = '${PHP_POST_MAX_SIZE}'/' /etc/php5/fpm/php.ini
sed -i 's/upload_max_filesize = .*/upload_max_filesize = '${PHP_UPLOAD_MAX_FILESIZE}'/' /etc/php5/fpm/php.ini
sed -i 's/;realpath_cache_size = .*/realpath_cache_size = '256k'/' /etc/php5/fpm/php.ini

echo "realpath_cache_size = 256k" >> /etc/php5/cli/php.ini

cat >> /etc/php5/fpm/pool.d/www.conf <<EOL
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 10
pm.max_requests=500
listen=127.0.0.1:9000
EOL

#############  Additional Tools
apt-get install -y build-essential redis-server memcached fail2ban zsh
update-rc.d redis-server defaults
update-rc.d memcached defaults

############# letsencrypt
git clone https://github.com/letsencrypt/letsencrypt /opt/letsencrypt
cd /opt/letsencrypt
./letsencrypt-auto

mkdir /var/www/letsencrypt

##############  unattended upgrades
apt-get -y install unattended-upgrades apt-listchanges
echo -e "APT::Periodic::Update-Package-Lists \"1\";\nAPT::Periodic::Unattended-Upgrade \"1\";\n" > /etc/apt/apt.conf.d/20auto-upgrades

# restart services
service unattended-upgrades restart
service php5-fpm restart
service nginx restart

wget -O /root/addsite.sh https://raw.githubusercontent.com/milleruk/server_scripts/master/addsite.sh
chmod +x /root/addsite.sh

echo
echo
echo "==========================================================="
echo "Ip is: $IP"
echo 
echo "Add new site using:"
echo "/root/addsite.sh www.example.tld"
echo 
echo "make sure dns is already resolving"
echo 


#// TODO
#// config optimalisatie mysql
#// geen root login

