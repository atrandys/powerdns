#!/bin/bash
#Install powerdns & powerdns-admin

echo "Install pdns & pdns-backend-mysql"
sleep 2s
yum install -y epel-release yum-plugin-priorities
curl -o /etc/yum.repos.d/powerdns-auth-master.repo https://repo.powerdns.com/repo-files/centos-auth-master.repo
wget https://rpms.remirepo.net/enterprise/remi-release-7.rpm
rpm -Uvh remi-release-7.rpm
yum -y install tcl expect expect-devel socat

yum install -y pdns pdns-backend-mysql

echo "Install mysql"
sleep 2s
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
EOF

mysql -uroot -p$mysqlpasswd <<-EOF
create database powerdns;
use powerdns;
CREATE TABLE domains (
  id                    INT AUTO_INCREMENT,
  name                  VARCHAR(255) NOT NULL,
  master                VARCHAR(128) DEFAULT NULL,
  last_check            INT DEFAULT NULL,
  type                  VARCHAR(6) NOT NULL,
  notified_serial       INT DEFAULT NULL,
  account               VARCHAR(40) DEFAULT NULL,
  PRIMARY KEY (id)
) Engine=InnoDB;

CREATE UNIQUE INDEX name_index ON domains(name);


CREATE TABLE records (
  id                    BIGINT AUTO_INCREMENT,
  domain_id             INT DEFAULT NULL,
  name                  VARCHAR(255) DEFAULT NULL,
  type                  VARCHAR(10) DEFAULT NULL,
  content               VARCHAR(64000) DEFAULT NULL,
  ttl                   INT DEFAULT NULL,
  prio                  INT DEFAULT NULL,
  change_date           INT DEFAULT NULL,
  disabled              TINYINT(1) DEFAULT 0,
  ordername             VARCHAR(255) BINARY DEFAULT NULL,
  auth                  TINYINT(1) DEFAULT 1,
  PRIMARY KEY (id)
) Engine=InnoDB;

CREATE INDEX nametype_index ON records(name,type);
CREATE INDEX domain_id ON records(domain_id);
CREATE INDEX recordorder ON records (domain_id, ordername);


CREATE TABLE supermasters (
  ip                    VARCHAR(64) NOT NULL,
  nameserver            VARCHAR(255) NOT NULL,
  account               VARCHAR(40) NOT NULL,
  PRIMARY KEY (ip, nameserver)
) Engine=InnoDB;


CREATE TABLE comments (
  id                    INT AUTO_INCREMENT,
  domain_id             INT NOT NULL,
  name                  VARCHAR(255) NOT NULL,
  type                  VARCHAR(10) NOT NULL,
  modified_at           INT NOT NULL,
  account               VARCHAR(40) NOT NULL,
  comment               VARCHAR(64000) NOT NULL,
  PRIMARY KEY (id)
) Engine=InnoDB;

CREATE INDEX comments_domain_id_idx ON comments (domain_id);
CREATE INDEX comments_name_type_idx ON comments (name, type);
CREATE INDEX comments_order_idx ON comments (domain_id, modified_at);


CREATE TABLE domainmetadata (
  id                    INT AUTO_INCREMENT,
  domain_id             INT NOT NULL,
  kind                  VARCHAR(32),
  content               TEXT,
  PRIMARY KEY (id)
) Engine=InnoDB;

CREATE INDEX domainmetadata_idx ON domainmetadata (domain_id, kind);


CREATE TABLE cryptokeys (
  id                    INT AUTO_INCREMENT,
  domain_id             INT NOT NULL,
  flags                 INT NOT NULL,
  active                BOOL,
  content               TEXT,
  PRIMARY KEY(id)
) Engine=InnoDB;

CREATE INDEX domainidindex ON cryptokeys(domain_id);


CREATE TABLE tsigkeys (
  id                    INT AUTO_INCREMENT,
  name                  VARCHAR(255),
  algorithm             VARCHAR(50),
  secret                VARCHAR(255),
  PRIMARY KEY (id)
) Engine=InnoDB;

CREATE UNIQUE INDEX namealgoindex ON tsigkeys(name, algorithm);
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
sleep 2s
yum -y install php72 php72-php-gd php72-php-mcrypt php72-php-opcache php72-php-pdo php72-php-mbstring php72-php-cli php72-php-fpm php72-php-mysqlnd php72-php-xml php72-php-odbc php72-php-pear gettext
systemctl start php72-php-fpm
systemctl enable php72-php-fpm
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
