#!/bin/bash

w="whiptail" 
TITLE="PeerOS setup wizard" 
WELCOME_MSG="\nWelcome to Subutai PeerOS Wizard.\n\nThis wizard will guide you to setup subutai PeerOs on your Debian system."
EXTRADISK_MSG="\nWARNING: Don't forget the extra partition or volume!\n\n"
NEXT="Next" 


is_port_free(){
    lsof -i :$1 > /dev/null;
    echo $?;
}

create_diskimg(){
    LPATH=$($w --inputbox "\nEnter the path to disk image file.(e.g /zfs.img)\n\n `df -x tmpfs -x devtmpfs -h`" 20 60 --title "$TITLE" 3>&2 2>&1 1>&3)
    SIZE=$($w --inputbox "\nEnter the size of ZFS disk image in Gigabytes.\n\n `df -x tmpfs -x devtmpfs -h`" 20 60 --title "$TITLE" 3>&2 2>&1 1>&3)
    
    dd if=/dev/zero of=$LPATH bs=1G count=$SIZE &> /dev/null &
    let "total=1024*1024*$SIZE"
    fsize=$(du $LPATH | awk '{ print $1}')
    (
    while [ $fsize -lt $total ]; do
        echo "print(int(($fsize/float($total))*100))" | python # | $w --gauge "Creating filesystem disk image..." 20 60 0  --title "$TITLE" 
           fsize=$(du $LPATH | awk '{ print $1}')
           sleep 1
        done; )	 | $w --gauge "Creating filesystem disk image..." 20 60 0  --title "$TITLE" 
    zfs_setup $LPATH      

}

zfs_setup(){
    zpool create -f subutai $1 &&
    zfs create -o mountpoint="/var/lib/lxc" subutai/fs
}

menu_partition(){
    CHOICE=$($w --menu "Choose a partition to serve as storage for your Resource Host"  20 60 3 --title "$TITLE" \
        "1" "Enter the device path (e.g /dev/sdd2)" \
        "2" "Create a loobback device" \
        "3" "List storage block devices" 3>&2 2>&1 1>&3
    )
    case $CHOICE in
        "1")
            DEVICE=$($w --inputbox "Enter the device path (e.g /dev/sdd2)" 20 60 3>&1 1>&2 2>&3)
            zfs_setup $DEVICE
            ;;
        "2")
            create_diskimg
            ;;
        "3") 
            echo "Press Enter to return to menu"
            lsblk -o KNAME,TYPE,SIZE
            read
            menu_partition
            ;;
    esac
}

$w --msgbox "$WELCOME_MSG"  20 60 --title "$TITLE" --ok-button "$NEXT" 
$w --msgbox "$EXTRADISK_MSG"  20 60 --title "$TITLE" --ok-button "$NEXT" 
COUNT=10
(
for PORT in 53 67 80 443 1900 6881 8086 8443 8444; 
do 
    res=`is_port_free $PORT`
    if [ $res != 1 ]; then 
        if [ $PORT = 53 ]; then 
            echo "Disabling dnsmasq..."
            systemctl disable systemd-resolved.service
            service systemd-resolved stop
        else
            echo "The $PORT must be not used"; 
            exit
        fi
    fi
    echo $COUNT  
    let "COUNT=$COUNT + 10" 
done; ) | $w --gauge "Checking $PORT service port" 20 60 0  --title "$TITLE" 
 
$w --infobox "Adding contrib and non-free to source list"  20 60 --title "$TITLE"  
#SED_RES=`sed -i 's/main/main contrib non-free/g' /etc/apt/sources.list`
$w --infobox "Updating the repositories index..."  20 60 --title "$TITLE"  
APT_UP_RES=`apt-get update`
$w --infobox "Adding security keys..."  20 60 --title "$TITLE"  
APT_UP_RES=`apt-key adv --recv-keys --keyserver keyserver.ubuntu.com C6B2AC7FBEB649F1`

COUNT=25
(
for PKG in zfutils zfs-dkms lxc dirmngr  ; 
do 
    DEBIAN_FRONTEND=noninteractive apt-get -y install $PKG &> /dev/null
    echo $COUNT 
    let "COUNT=$COUNT + 25" 
done; ) | $w --gauge "Installing $PKG ..." 20 60 0  --title "$TITLE" 



$w --infobox "Loading ZFS module..."  20 60 --title "$TITLE"
depmod
Modprobe_zfs_RES=`modprobe zfs`
menu_partition
$w --infobox "Adding Subutai deb repository..."  20 60 --title "$TITLE"  
echo "deb http://deb.subutai.io/subutai prod main" > /etc/apt/sources.list.d/subutai.list
apt-get -y update &> /dev/null
$w --infobox "Installing Subutai ..."  20 60 --title "$TITLE"  
apt-get -y install subutai &> /dev/null
$w --infobox "Installing Management container..."  20 60 --title "$TITLE"  
subutai import management

