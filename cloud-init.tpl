#!/bin/bash
#set -e

# Install all the needed packages
sudo apt autoremove -y
sudo apt-get remove apache2 -y

sudo apt-get update 

sudo apt install xrdp lxde make gcc g++ libcairo2-dev libjpeg-turbo8-dev libpng-dev libtool-bin libossp-uuid-dev libavcodec-dev libavutil-dev libswscale-dev freerdp2-dev libpango1.0-dev libssh2-1-dev libvncserver-dev libtelnet-dev libssl-dev libvorbis-dev libwebp-dev tomcat9 tomcat9-admin tomcat9-common tomcat9-user nginx -y

# Start and enable Tomcat
sudo systemctl start tomcat9
sudo systemctl enable tomcat9

# Download and install Guacamole Server
#wget https://downloads.apache.org/guacamole/1.4.0/source/guacamole-server-1.4.0.tar.gz -P /tmp/
wget https://archive.apache.org/dist/guacamole/1.4.0/source/guacamole-server-1.4.0.tar.gz -P /tmp/
tar xzf /tmp/guacamole-server-1.4.0.tar.gz -C /tmp/

(
    cd /tmp/guacamole-server-1.4.0 
    sudo ./configure --with-init-dir=/etc/init.d
    sudo make
    sudo make install
    sudo ldconfig
)

sudo systemctl start guacd
sudo systemctl enable guacd 


####
sudo mkdir /etc/guacamole

echo "<user-mapping>
<authorize 
    username=\"${username}\"
    password=\"${password}\">
  <connection name=\"localhost-ssh\">
    <protocol>ssh</protocol>
    <param name=\"hostname\">localhost</param>
    <param name=\"port\">22</param>
    <param name=\"username\">${username}</param>
    <param name=\"password\">${password}</param>
  </connection>    
  <connection name=\"localhost-rdp\">
    <protocol>rdp</protocol>
    <param name=\"hostname\">localhost</param>
    <param name=\"port\">3389</param>
    <param name=\"username\">${username}</param>
    <param name=\"password\">${password}</param>
  </connection>
  <connection name=\"app1-dev\">
    <protocol>ssh</protocol>
    <param name=\"hostname\">${host1}</param>
    <param name=\"port\">22</param>
    <param name=\"username\">${username}</param>
    <param name=\"password\">${password}</param>
  </connection>  
  <connection name=\"app1-prod\">
    <protocol>ssh</protocol>
    <param name=\"hostname\">${host2}</param>
    <param name=\"port\">22</param>
    <param name=\"username\">${username}</param>
    <param name=\"password\">${password}</param>
  </connection>
  <connection name=\"app2-dev\">
    <protocol>ssh</protocol>
    <param name=\"hostname\">${host3}</param>
    <param name=\"port\">22</param>
    <param name=\"username\">${username}</param>
    <param name=\"password\">${password}</param>
  </connection>  
  <connection name=\"app2-prod\">
    <protocol>ssh</protocol>
    <param name=\"hostname\">${host4}</param>
    <param name=\"port\">22</param>
    <param name=\"username\">${username}</param>
    <param name=\"password\">${password}</param>
  </connection>  
</authorize>
</user-mapping>" | sudo tee -a /etc/guacamole/user-mapping.xml


#sudo wget https://downloads.apache.org/guacamole/1.4.0/binary/guacamole-1.4.0.war -O /etc/guacamole/guacamole.war 
sudo wget https://archive.apache.org/dist/guacamole/1.4.0/binary/guacamole-1.4.0.war -O /etc/guacamole/guacamole.war 

sudo ln -s /etc/guacamole/guacamole.war /var/lib/tomcat9/webapps/ 
sleep 10 
sudo mkdir /etc/guacamole/{extensions,lib} 
sudo bash -c 'echo "GUACAMOLE_HOME=/etc/guacamole" >> /etc/default/tomcat9'

echo "guacd-hostname: localhost
guacd-port:    4822
user-mapping:    /etc/guacamole/user-mapping.xml
auth-provider:    net.sourceforge.guacamole.net.basic.BasicFileAuthenticationProvider"  | sudo tee -a /etc/guacamole/guacamole.properties

sudo ln -s /etc/guacamole /usr/share/tomcat9/.guacamole

sudo systemctl restart tomcat9 
sudo systemctl restart guacd 

#####
# Create user for RDP session
sudo useradd -m -s /bin/bash ${username} 
echo "${username}:${password}" | sudo chpasswd

# Download ssl cert for nginx
sudo systemctl start nginx 
sudo systemctl enable nginx 

# Create Desktop shortcuts
sudo mkdir /home/${username}/Desktop

echo "[Desktop Entry]
Type=Link
Name=Firefox Web Browser
Icon=firefox
URL=/usr/share/applications/firefox.desktop" | sudo tee -a /home/${username}/Desktop/firefox.desktop

echo "[Desktop Entry]
Type=Link
Name=LXTerminal
Icon=lxterminal
URL=/usr/share/applications/lxterminal.desktop" | sudo tee -a /home/${username}/Desktop/lxterminal.desktop

sudo chown ${username}:${username} /home/${username}/Desktop 
sudo chown ${username}:${username} /home/${username}/Desktop/* 

# Nginx config - SSL redirect
echo "server {
    listen 80;
	  server_name ${hostname};
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;

    access_log  /var/log/nginx/guac_access.log;
    error_log  /var/log/nginx/guac_error.log;

    location / {
          proxy_pass http://localhost:8080/guacamole/;
          proxy_buffering off;
          proxy_http_version 1.1;
          proxy_cookie_path /guacamole/ /;
    }
}" | sudo tee -a /etc/nginx/conf.d/default.conf

sudo systemctl restart nginx 

# Customize Guacamole login page
sudo ls -l /var/lib/tomcat9/webapps/guacamole/ 
sudo wget https://avx-build.s3.eu-central-1.amazonaws.com/logo-144.png 
sudo wget https://avx-build.s3.eu-central-1.amazonaws.com/logo-64.png 
# while [ ! -d /var/lib/tomcat9/webapps/guacamole/images/ ]; do
#   sleep 1
# done
sudo cp logo-144.png /var/lib/tomcat9/webapps/guacamole/images/ 
sudo cp logo-64.png /var/lib/tomcat9/webapps/guacamole/images/ 
sudo cp logo-144.png /var/lib/tomcat9/webapps/guacamole/images/guac-tricolor.png 
sudo sed -i "s/Apache Guacamole/FlightSchool - Test Server/g" /var/lib/tomcat9/webapps/guacamole/translations/en.json 
sudo systemctl restart tomcat9 
sudo systemctl restart guacd 

sudo cp logo-64.png /usr/share/lxde/images/lxde-icon.png 

# Add pod ID search domain
sudo sed -i '$d' /etc/netplan/50-cloud-init.yaml 
echo "            nameservers:
                search: [${domainname}]" | sudo tee -a /etc/netplan/50-cloud-init.yaml
sudo netplan apply 

sudo sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
sudo /etc/init.d/ssh restart