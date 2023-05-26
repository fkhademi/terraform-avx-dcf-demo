#!/bin/bash

sudo hostnamectl set-hostname ${hostname}

# Create user for SSH session
sudo useradd -m -s /bin/bash ${username} 
echo "${username}:${password}" | sudo chpasswd 
sudo adduser ${username} sudo

sudo sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
sudo /etc/init.d/ssh restart

# Egress script

echo '#!/bin/bash

while :
do
    delay=$((RANDOM % 120))
	TXT=`shuf -n 1 /root/domains.txt`
    logger -s "Interval $delay sending curl to $TXT"
	curl -I -m 2 $TXT
	sleep $delay
done
' | sudo tee -a /home/${username}/egress.sh


nohup /home/${username}/egress.sh &

echo "#!/bin/sh
nohup /home/${username}/egress.sh &" | sudo tee -a /etc/init.d/egress

sudo chmod +x /etc/init.d/egress
sudo ln -s /etc/init.d/egress /etc/rc2.d/S99egress 

# Domain list
echo "https://aviatrix.com
https://raw.githubusercontent.com
https://cnn.com
https://facebook.com
http://amazonaws.com
http://data.cn
http://hello.ru
http://spam.cn
https://hub.docker.com
http://azurerm.com
sinajs.cn
tmgrup.com.tr
mail.ru
rlinks.one.in
rss.tmgrup.com.tr
rt.flix360.com
rtt.campanja.com
rum.azion.com
rum.azioncdn.net
rum.conde.io
tracking.ecookie.fr
tracking.kdata.fr
tracking.netvigie.com
trk.adbutter.net
visitping.rossel.be
analytics.styria.hr
adv-sv-stat.focus.cn
ia.51.la
imp.ad-plus.cn
imp.go.sohu.com
imp.optaim.com
log.hiiir.com
log.tagtic.cn
m.lolvsdota.cn
track.ra.icast.cn
tracking.cat898.com
useg.nextdigital.com.hk
v.emedia.cn
videostats.kakao.com
tracking.vid4u.org
bisko.mall.tv
bnr.alza.cz
counter.cnw.cz
fimg-resp.seznam.cz
h.imedia.cz
hit.skrz.cz
i.imedia.cz
log.idnes.cz
pixel.cpex.cz
stat.cncenter.cz
t.leady.com
t.leady.cz
track.leady.cz
log.ecgh.dk
statistics.jfmedier.dk
trckr.nordiskemedier.dk
ubt.berlingskemedia.net
analytics.belgacom.be
atconnect.npo.nl
cookies.reedbusiness.nl
statistics.rbi-nl.com
insight.fonecta.fi
tags.op-palvelut.fi
links.boom.ge
rum.marquardmedia.hu
videostat-new.index.hu
videostat.index.hu
analytics.bhaskar.com
analytics.competitoor.com
analytics00.meride.tv
click.kataweb.it
counter.ksm.it
counter2.condenast.it
d32hwlnfiv2gyn.cloudfront.net
dmpcdn.el-mundo.net
encoderfarmstatsnew.servicebus.windows.net
evnt.iol.it
fb_servpub-a.akamaihd.net
c.bigmir.net
cnstats.cdev.eu
cnt.logoslovo.ru
cnt.nov.ru
cnt.rambler.ru
cnt.rate.ru
count.yandeg.ru
counter.insales.ru
counter.megaindex.ru
counter.nn.ru
counter.photopulse.ru
counter.pr-cy.ru
counter.star.lg.ua
counter.tovarro.com
counter.wapstart.ru
crm-analytics.imweb.ru
dbex-tracker-v2.driveback.ru
error.videonow.ru
g4p.redtram.com
mediator.mail.ru
metrics.aviasales.ru
piper.amocrm.ru
rbc.magna.ru
s.agava.ru
scnt.rambler.ru
scounter.rambler.ru
service-stat.tbn.ru
stat.eagleplatform.com
stat.radar.imgsmail.ru
stat.rum.cdnvideo.ru
stat.sputnik.ru
stat.tvigle.ru
statistics.fppressa.ru
stats.embedcdn.cc
stats.seedr.com
stats.tazeros.com
target.mirtesen.ru
target.smi2.net
target.smi2.ru" | sudo tee -a /root/domains.txt

