#!/bin/sh

# Script Params
# $1 = OPNScriptURI
# $2 = OpnVersion
# $3 = Primary/Secondary/SingNic/TwoNics
# $4 = Trusted Nic subnet prefix - used to get the gw
# $5 = Windows-VM-Subnet subnet prefix - used to route/nat allow internet access from Windows Management VM
# $6 = ELB VIP Address
# $7 = Private IP Secondary Server

# Check if Primary or Secondary Server to setup Firewal Sync
# Note: Firewall Sync should only be setup in the Primary Server
if [ "$3" = "Primary" ]; then
    fetch $1config-active-active-primary.xml
    fetch $1get_nic_gw.py
    gwip=$(python get_nic_gw.py $4)
    sed -i "" "s/yyy.yyy.yyy.yyy/$gwip/" config-active-active-primary.xml
    sed -i "" "s_zzz.zzz.zzz.zzz_$5_" config-active-active-primary.xml
    sed -i "" "s/www.www.www.www/$6/" config-active-active-primary.xml
    sed -i "" "s/xxx.xxx.xxx.xxx/$7/" config-active-active-primary.xml
    sed -i "" "s/<hostname>OPNsense<\/hostname>/<hostname>OPNsense-Primary<\/hostname>/" config-active-active-primary.xml
    cp config-active-active-primary.xml /usr/local/etc/config.xml
elif [ "$3" = "Secondary" ]; then
    fetch $1config-active-active-secondary.xml
    fetch $1get_nic_gw.py
    gwip=$(python get_nic_gw.py $4)
    sed -i "" "s/yyy.yyy.yyy.yyy/$gwip/" config-active-active-secondary.xml
    sed -i "" "s_zzz.zzz.zzz.zzz_$5_" config-active-active-secondary.xml
    sed -i "" "s/www.www.www.www/$6/" config-active-active-secondary.xml
    sed -i "" "s/<hostname>OPNsense<\/hostname>/<hostname>OPNsense-Secondary<\/hostname>/" config-active-active-secondary.xml
    cp config-active-active-secondary.xml /usr/local/etc/config.xml
elif [ "$3" = "SingNic" ]; then
    fetch $1config-snic.xml
    cp config-snic.xml /usr/local/etc/config.xml
elif [ "$3" = "TwoNics" ]; then
    fetch $1config.xml
    fetch $1get_nic_gw.py
    gwip=$(python get_nic_gw.py $4)
    sed -i "" "s/yyy.yyy.yyy.yyy/$gwip/" config.xml
    sed -i "" "s_zzz.zzz.zzz.zzz_$5_" config.xml
    cp config.xml /usr/local/etc/config.xml
fi

#OPNSense default configuration template
#fetch https://raw.githubusercontent.com/dmauser/opnazure/dev_active_active/scripts/$1
#fetch https://raw.githubusercontent.com/dmauser/opnazure/master/scripts/$1
#cp $1 /usr/local/etc/config.xml

# 1. Package to get root certificate bundle from the Mozilla Project (FreeBSD)
# 2. Install bash to support Azure Backup integration
env IGNORE_OSVERSION=yes
pkg bootstrap -f; pkg update -f
env ASSUME_ALWAYS_YES=YES pkg install ca_root_nss && pkg install -y bash

#Download OPNSense Bootstrap and Permit Root Remote Login
# fetch https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in
#fetch https://raw.githubusercontent.com/opnsense/update/7ba940e0d57ece480540c4fd79e9d99a87f222c8/src/bootstrap/opnsense-bootstrap.sh.in
fetch https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in
sed -i "" 's/#PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config

#OPNSense
sed -i "" "s/reboot/shutdown -r +1/g" opnsense-bootstrap.sh.in
sh ./opnsense-bootstrap.sh.in -y -r "$2"

# Add Azure waagent
fetch https://github.com/Azure/WALinuxAgent/archive/refs/tags/v2.8.0.11.tar.gz
tar -xvzf v2.8.0.11.tar.gz
cd WALinuxAgent-2.8.0.11/
python3 setup.py install --register-service --lnx-distro=freebsd --force
cd ..

# Fix waagent by replacing configuration settings
ln -s /usr/local/bin/python3.9 /usr/local/bin/python
##sed -i "" 's/command_interpreter="python"/command_interpreter="python3"/' /etc/rc.d/waagent
##sed -i "" 's/#!\/usr\/bin\/env python/#!\/usr\/bin\/env python3/' /usr/local/sbin/waagent
sed -i "" 's/ResourceDisk.EnableSwap=y/ResourceDisk.EnableSwap=n/' /etc/waagent.conf
fetch $1actions_waagent.conf
cp actions_waagent.conf /usr/local/opnsense/service/conf/actions.d

# Installing bash - This is a requirement for Azure custom Script extension to run
pkg install -y bash

# Remove wrong route at initialization
cat > /usr/local/etc/rc.syshook.d/start/22-remoteroute <<EOL
#!/bin/sh
route delete 168.63.129.16
EOL
chmod +x /usr/local/etc/rc.syshook.d/start/22-remoteroute

#Adds support to LB probe from IP 168.63.129.16
# Add Azure VIP on Arp table
echo # Add Azure Internal VIP >> /etc/rc.conf
echo static_arp_pairs=\"azvip\" >>  /etc/rc.conf
echo static_arp_azvip=\"168.63.129.16 12:34:56:78:9a:bc\" >> /etc/rc.conf
# Makes arp effective
service static_arp start
# To survive boots adding to OPNsense Autorun/Bootup:
echo service static_arp start >> /usr/local/etc/rc.syshook.d/start/20-freebsd
