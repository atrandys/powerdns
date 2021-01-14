#!/bin/bash
#Install powerdns & powerdns-admin

echo "Install pdns & pdns-backend-mysql"
yum install -y epel-release yum-plugin-priorities
curl -o /etc/yum.repos.d/powerdns-auth-master.repo https://repo.powerdns.com/repo-files/centos-auth-master.repo
wget https://rpms.remirepo.net/enterprise/remi-release-7.rpm
rpm -Uvh remi-release-7.rpm
yum -y install tcl expect expect-devel socat

yum install -y pdns pdns-backend-mysql

echo "Install mysql"
yum -y install mariadb mariadb-server
systemctl start mariadb
systemctl enable mariadb

mysqlpasswd=$(cat /dev/urandom | head -1 | md5sum | head -c 8)
powerdnsdb=$(ls /usr/share/doc/ | grep pdns-backend-mysql)
apikey=$(cat /dev/urandom | head -1 | md5sum | head -c 16)

/usr/bin/expect << EOF
spawn mysql_secure_installation
expect "password for root" {send "\r"}
expect "root password" {send "Y\r"}
expect "New password" {send "$mysqlpasswd\r"}
expect "Re-enter new password" {send "$mysqlpasswd\r"}
expect "Remove anonymous users" {send "Y\r"}
expect "Disallow root login remotely" {send "Y\r"}
expect "database and access" {send "Y\r"}
expect "Reload privilege tables" {send "Y\r"}
spawn mysql -u root -p
expect "Enter password" {send "$mysqlpasswd\r"}
expect "MariaDB" {send "create database powerdns;\r"}
expect "MariaDB" {send "use powerdns;\r"}
expect "MariaDB" {send "source /usr/share/doc/$powerdnsdb/schema.mysql.sql;\r"}
expect "MariaDB" {send "exit\r"}
EOF



cat >> /etc/pdns/pdns.conf <<-EOF
launch=gmysql
gmysql-host=localhost
gmysql-user=root
gmysql-password=$mysqlpasswd
gmysql-dbname=powerdns

api=yes
api-key=$apikey
webserver-address=0.0.0.0
webserver-allow-from=0.0.0.0/0,::/0
EOF

chown -R pdns:pdns /etc/pdns/pdns.conf

systemctl restart pdns
systemctl enable pdns

echo "Install powerdns-admin"
yum -y install php74 php74-php-gd php74-php-opcache php74-php-pdo php74-php-mbstring php74-php-cli php74-php-fpm php74-php-mysqlnd php74-php-xml php74-php-odbc php74-php-pear gettext


echo "Install nginx"
echo "Input your domain"
read your_domain
wget http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm
rpm -Uvh nginx-release-centos-7-0.el7.ngx.noarch.rpm
yum install -y nginx
systemctl enable nginx.service
systemctl stop nginx.service

mkdir /etc/nginx/ssl
cat > /etc/nginx/nginx.conf <<-EOF
user  nginx;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    error_log /var/log/nginx/error.log error;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    include /etc/nginx/conf.d/*.conf;
}
EOF

    curl https://get.acme.sh | sh
    ~/.acme.sh/acme.sh  --issue  -d $your_domain  --standalone
    ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
        --key-file   /etc/nginx/ssl/$your_domain.key \
        --fullchain-file /etc/nginx/ssl/fullchain.cer

cat > /etc/nginx/conf.d/default.conf<<-EOF
server {
    listen 80 default_server;
    server_name _;
    return 444;  
}
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/nginx/ssl/fullchain.cer; 
    ssl_certificate_key /etc/nginx/ssl/$your_domain.key;
    return 444;
}
server { 
    listen       80;
    server_name  $your_domain;
    rewrite ^(.*)$  https://\$host\$1 permanent; 
}
server {
    listen 443 ssl http2;
    server_name $your_domain;
    root /usr/share/nginx/html;
    index index.php index.html;
    ssl_certificate /etc/nginx/ssl/fullchain.cer; 
    ssl_certificate_key /etc/nginx/ssl/$your_domain.key;
    ssl_stapling on;
    ssl_stapling_verify on;
    add_header Strict-Transport-Security "max-age=31536000";
    access_log /var/log/nginx/hostscube.log combined;
    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    location / {
       try_files \$uri \$uri/ /index.php?\$args;
    }
}
EOF
cd /usr/share/nginx/html
rm -rf ./*
wget https://jaist.dl.sourceforge.net/project/poweradmin/poweradmin-2.1.7.tgz
tar xvf poweradmin-2.1.7.tgz
mv poweradmin-2.1.7/* ./
nginx -t
systemctl start nginx

echo "mysqlpasswd: $mysqlpasswd"
echo "powerdnsdb: powerdns"
echo "apikey: $apikey"
