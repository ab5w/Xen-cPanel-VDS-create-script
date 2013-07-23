#!/bin/bash
#
#   This script creates a cPanel Xen VDS and sets the relevant configs, 
#   first checking if it's added to racktables. It also checks if there
#   is enough free diskspace and RAM on the node first!
#   
#   Copyright (C) 2013 Craig Parker <craig@paragon.net.uk>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 3 of the License, or
#   (at your option) any later version.
#     
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#   
#   You should have received a copy of the GNU General Public License
#   along with this program; If not, see <http://www.gnu.org/licenses/>.
#
#   Guide to the argument variables;
#
#   Name = $1
#   Disk = $2
#   RAM = $3
#   IP = $4
#   Subnet = $5
#   Vlan = $6
#   Gateway = $7
#   Brand = $8
#

RED='\033[01;31m'
RESET='\033[0m'
CONTENT=$(wget http://example.com/vmcheck.php?name=$1 -q -O -)
FREEHDD=`vgs --units G | grep vg | awk '{print $7}' | awk -F '.' '{print $1}'`
FREERAM=`xm info | grep 'free_memory' | awk '{print $3}'`
MAC=$(/usr/local/sbin/easymac.sh -x | awk '{print $4}')

if [ $# -ne 8 ] ; then
echo -e 'Please add arguments in the order of; hostname, disksize (in GB), RAM (in MB), IP, Subnet Mask, VLAN, Gateway, Brand (brand1 or brand2).\nFor example; herpderp 40 1536 192.168.1.55 255.255.255.0 123 192.168.1.1 brand2'
exit 0
fi

echo "Checking if VM already exists.";

if [ -f /etc/xen/$1 ] ; then
echo -e $RED"Xen config with that name already exists!"$RESET
exit 0
fi

if [ -e /dev/vg/$1 -o -e /dev/vg/$1-swap ] ; then
echo -e $RED"LVM Exists!"$RESET
exit 0
fi

echo "Checking disk size.";

if [ $2 -lt 10 -o $2 -gt 200 ] ; then
echo -e $RED"Please check disk size is correct, size is in GB!"$RESET
exit 0
fi

echo "Checking RAM.";

if [ $3 -lt 128 -o $3 -gt 10000 ] ; then
echo -e $RED"Please check RAM is correct, size is in MB!"$RESET
exit 0
fi

echo "Checking IP.";

if [[ $4 == *.1 ]] || [[ $4 == *.0 ]] || [[ $4 == *.255 ]] ; then # Thanks to OG-Gareth for the idea of checking for .0 and .255 as well. :D
echo -e $RED"IP can't end in .0, .1 or .255"$RESET
exit 0
fi

echo "Checking VLAN.";

if ! [[ "$6" =~ ^[0-9]+$ ]] ; then
echo -e $RED"Need a numeric VLAN ID. For example; 123"$RESET
exit 0
fi

echo "Checking brand.";

if [[ "$8" != "brand1" && "$8" != "brand2" ]] ; then
echo -e $RED"Please check brand is correct!"$RESET
exit 0
fi

echo "Checking if object is in racktables.";

if [ $CONTENT -lt 1 ] ; then
echo -e $RED'Please create the rack tables object and link the node container!'$RESET
exit 0
fi

echo "Checking available disk space.";

if [ $FREEHDD -lt $2 ] ; then
echo -e $RED"Not enough disk space on the node!"$RESET
exit 0
fi

echo "Checking available RAM.";

if [ $FREERAM -lt $3 ] ; then
echo -e $RED"Not enough free RAM on the node!"$RESET
exit 0
fi

if [ $3 -le 1536 ] ; then

		export CPU="2"

	elif [ $3 -le 3072 ] ; then
		
		export CPU="4"

	else
	
		export CPU="6"

fi

echo "Creating LVM.";

lvcreate -L$2G -n $1 vg;
lvcreate -L1024M -n $1-swap vg;
mkfs -t ext3 /dev/vg/$1;
mkswap /dev/vg/$1-swap;
mkdir /mnt/$1;
mount /dev/vg/$1 /mnt/$1;

echo -e $RED"Copying image to mountpoint. This takes /ages/...\nWhich makes it the perfect time to create the DNS zone, reverse PTR and add the cPanel license!"$RESET;

cp -ax /root/newimage/* /mnt/$1;

echo "Inserting variables to their relevant config files.";

sed -i "s/{name}/$1/g" /mnt/$1/etc/sysconfig/network;
sed -i "s/{ip}/$4/g" /mnt/$1/etc/sysconfig/network-scripts/ifcfg-eth0;
sed -i "s/{subnet}/$5/g" /mnt/$1/etc/sysconfig/network-scripts/ifcfg-eth0;
sed -i "s/{gateway}/$7/g" /mnt/$1/etc/sysconfig/network-scripts/ifcfg-eth0;
sed -i "s/{ip}/$4/g" /mnt/$1/etc/wwwacct.conf;
sed -i "s/{name}/$1/g" /mnt/$1/etc/wwwacct.conf;

if [ $8 = "brand1" ] ; then
	
		sed -i "s/{brand}/brand1.com/g" /mnt/$1/etc/wwwacct.conf;

	else
	
		sed -i "s/{brand}/brand2.com/g" /mnt/$1/etc/wwwacct.conf;
fi

echo "Unmounting.";

umount /mnt/$1;

echo "Removing mount point.";

rm -rf /mnt/$1;

echo "Creating Xen config.";

cp /usr/local/etc/dummyconfig /etc/xen/$1;

sed -i "s/{ram}/$3/g" /etc/xen/$1;
sed -i "s/{name}/$1/g" /etc/xen/$1;
sed -i "s/{vlan}/$6/g" /etc/xen/$1;
sed -i "s/{mac}/$MAC/g" /etc/xen/$1;
sed -i "s/{cores}/$CPU/g" /etc/xen/$1;

echo "Booting VM";

xm create -c $1