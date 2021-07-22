#!/bin/bash

USER_FTP=admin
PASSWD_FTP=admin
HOST_FTP=192.168.1.1
PORT_FTP=21
RFOLDER="Backups/Dlink/"
LOG="/tmp/`basename $BASH_SOURCE | cut -f 1 -d '.'`.log"
echo -n >  $LOG
USER=admin
PASSWD=admin
PASSWD_MD5=`echo -n $PASSWD|md5sum| awk '{print $1}'`
TFTPROOT=/srv/tftp
# for SNMP v3
#SNMPSET="snmpset -v 3 -a SHA -A ******* -x DES -X ******* -u monitor -l authPriv "
# for SNMP v2c
SNMPSET="snmpset -v2c -c private "
DATE=`date +%d%m%Y`
TFTP_SERV=192.168.1.11
TFTP_SERV_HEX=$(printf '%02X' ${TFTP_SERV//./ })
LFILENAME="running-config"

INC_IP="
192.168.1.44
"
EXC_IP="
192.168.1.252
"
REQ_IP=()
FIRST_IP=192.168.1.1
NUM_IP=100


if ! dpkg -s tftpd-hpa > /dev/null; then
    echo "tftp-hpa is not installed"
     exit 1
fi
if ! dpkg -s syslinux-utils > /dev/null; then
    echo "syslinux-utils is not installed"
     exit 1
fi
if ! dpkg -s snmp > /dev/null; then
    echo "snmp is not installed"
     exit 1
fi
if ! dpkg -s sshpass > /dev/null; then
    echo "sshpass is not installed"
     exit 1
fi
if ! dpkg -s curl > /dev/null; then
    echo "curl is not installed"
     exit 1
fi


function SendtoFTP(){
    local ret=0
    if [ $# -eq 2 ]; then
	if [ -s $TFTPROOT/$1.cfg ]; then
	    mv $TFTPROOT/$1.cfg $TFTPROOT/$DATE-$1.cfg
	    curl -# --upload-file "$TFTPROOT/$DATE-$1.cfg" ftp://$USER_FTP:$PASSWD_FTP@$HOST_FTP:$PORT_FTP/$2 && \
	    rm $TFTPROOT/$DATE-$1.cfg >> $LOG
	    ret=0
	else
	    ret=2
	fi
    else
	echo "Wrong parameters in function SendtoFTP" >> $LOG
	ret=1
    fi
echo $ret
}

function TelnetRequest(){
    local ret=0
    if [ $# -eq 3 ]; then
	(
	    sleep 5;
	    echo -en "$USER\r";
	    sleep 1;
	    echo -en "$PASSWD\r";
	    sleep 3;
	    echo -en "$2\r";
	    sleep 3;
	    echo -en "logout\r";
	) | telnet $1 >> $3
	ret=0
    else
	echo "Wrong parameters in function TelnetRequest" >> $LOG
	ret=1
    fi
echo $ret
}

function SSHRequest(){
    local ret=0
    if [ $# -eq 3 ]; then
	if ! grep "$(ssh-keyscan $ip 2>/dev/null)" ~/.ssh/known_hosts > /dev/null; then
	    echo "Unknow ssh host $1" >> $LOG 
	    ssh-keyscan $1 >> ~/.ssh/known_hosts
	fi
	sshpass -p $PASSWD scp $USER@$1:$2 $3/$1.cfg
    ret=0
    else
	echo "Wrong parameters in function SSHRequest" >> $LOG
	ret=1
    fi
echo $ret
}

NextIP(){
    if [ $# -eq 1 ]; then
	local IP=$1
	local IP_HEX=$(printf '%.2X' ${IP//./ })
	local NEXT_IP_HEX=$(printf %.8X `echo $(( 0x$IP_HEX + 1 ))`)
	local NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo $NEXT_IP_HEX | sed -r 's/(..)/0x\1 /g'`)
	echo "$NEXT_IP"
    else
	echo "Wrong parameters in function SSHRequest" >> $LOG
    fi
}

PING_IP=${FIRST_IP}
for i in `seq 1 $NUM_IP`
do
    ping  -W 1 -c 1 $PING_IP > /dev/null
    if [ $? -eq 0  ]; then
        REQ_IP+=("$PING_IP")
    fi
    PING_IP=$(NextIP $PING_IP)
done
REQ_IP=`echo "${REQ_IP[@]} ${INC_IP[@]}"|tr ' ' '\n'|sort|uniq`
for element in ${EXC_IP}
do
    REQ_IP=${REQ_IP/${element}/}
done

echo ${REQ_IP[@]}>>$LOG

for ip in ${REQ_IP}
do
    RFILENAME_HEX=$(xxd -pu <<< "$ip.cfg")
    RFILENAME_HEX=${RFILENAME_HEX::-2}
    LFILENAME_HEX=$(xxd -pu <<< "$LFILENAME")
    LFILENAME_HEX=${LFILENAME_HEX::-2}
    MODEL=`snmpwalk -v1 -c public $ip 1.3.6.1.2.1.1.1.0| awk '{ print $4 }'  | sed  -e 's/\"//g'`
    [ -z $MODEL  ] && MODEL=$ip
    NOTFOUND=0
    echo "=$ip==============$MODEL================" >> $LOG
    case $MODEL in

	"DGS-1510-52X" | "DGS-1510-20" ) 
	    $SNMPSET $ip \
		.1.3.6.1.4.1.171.14.14.1.2.1.2.1 i 2 \
		.1.3.6.1.4.1.171.14.14.1.2.1.3.1 x $LFILENAME_HEX \
		.1.3.6.1.4.1.171.14.14.1.2.1.4.1 x $RFILENAME_HEX \
		.1.3.6.1.4.1.171.14.14.1.2.1.5.1 i 1 \
		.1.3.6.1.4.1.171.14.14.1.2.1.6.1 x $TFTP_SERV_HEX \
		.1.3.6.1.4.1.171.14.14.1.2.1.12.1 i 4 >>$LOG
	    RFOLDER="Backups/Dlink/"
	;;

	"WS6-DGS-1210-26/F1"|"WS6-DGS-1210-10P/F1"|"WS6-DGS-1210-28P/F1"|"WS6-DGS-1210-20/F1"|"WS6-DGS-1210-52/F1"|"WS6-DGS-1210-28/F1" )
	    # 1- TFTP SERVER
	    # 2- IPv4 (1)
	    # 3 - InterfaceName
	    # 4 - Filename
	    # 5 - Operation status 1-download, 2 - upload
	    # 6 - Config ID (1,2)
	    $SNMPSET $ip \
		.1.3.6.1.4.1.171.11.153.1000.3.10.5.0 i 2 \
		.1.3.6.1.4.1.171.11.153.1000.3.10.4.0 s "$ip.cfg" \
		.1.3.6.1.4.1.171.11.153.1000.3.10.1.0 x $TFTP_SERV_HEX \
		.1.3.6.1.4.1.171.11.153.1000.3.10.2.0 i 1 >> $LOG
	    RFOLDER="Backups/Dlink/"
	;;

	"DGS-1210-52/ME/A1" )
	    $SNMPSET $ip \
		.1.3.6.1.4.1.171.10.76.29.1.3.10.1.0 x $TFTP_SERV_HEX \
		.1.3.6.1.4.1.171.10.76.29.1.3.10.4.0 s "$ip.cfg" \
		.1.3.6.1.4.1.171.10.76.29.1.3.10.5.0 i 2 \
		.1.3.6.1.4.1.171.10.76.29.1.3.10.7.0 i 1 >>$LOG
	    RFOLDER="Backups/Dlink/"
	;;

	"DGS-1210-10P" )
	    $SNMPSET $ip \
		.1.3.6.1.4.1.171.10.76.12.3.5.0 a $TFTP_SERV \
		.1.3.6.1.4.1.171.10.76.12.3.6.0 s "$ip.cfg" \
		.1.3.6.1.4.1.171.10.76.12.3.7.0 i 2  >>$LOG
	    RFOLDER="Backups/Dlink/"
	;;

	"DGS-1210-52/C1" )
	    $SNMPSET $ip \
		.1.3.6.1.4.1.171.10.76.22.1.3.10.1.0 x $TFTP_SERV_HEX \
		.1.3.6.1.4.1.171.10.76.22.1.3.10.4.0 s "$ip.cfg" \
		.1.3.6.1.4.1.171.10.76.22.1.3.10.5.0 i 2  >>$LOG
	    RFOLDER="Backups/Dlink/"
	;;

	"DGS-1210-10P/C1" )
	    $SNMPSET $ip \
		.1.3.6.1.4.1.171.10.76.18.1.3.10.1.0 x $TFTP_SERV_HEX \
		.1.3.6.1.4.1.171.10.76.18.1.3.10.4.0 s "$ip.cfg" \
		.1.3.6.1.4.1.171.10.76.18.1.3.10.5.0 i 2  >>$LOG
	    RFOLDER="Backups/Dlink/"
	;;

	"DGS-1210-28" )
	    $SNMPSET $ip \
		.1.3.6.1.4.1.171.10.76.15.3.10.1 a $TFTP_SERV \
		.1.3.6.1.4.1.171.10.76.15.3.10.4 s "$ip.cfg" \
		.1.3.6.1.4.1.171.10.76.15.3.10.5 i 2  >>$LOG
	    RFOLDER="Backups/Dlink/"

;;

	# Ubiquiti
	"Linux" )
	    LFILE_SSH=/tmp/system.cfg
	    RFOLDER_SSH=/srv/tftp
	    RFOLDER="Backups/UBNT/"
	    SSHRequest $ip $LFILE_SSH $RFOLDER_SSH
	;;

	"DFL-260E" )
	    LFILE_SSH=system.bak
	    RFOLDER_SSH=/srv/tftp
	    RFOLDER="Backups/DFL/"
	    SSHRequest $ip $LFILE_SSH $RFOLDER_SSH
	;;

	"ZyXEL"|"Keenetic" )
	    REQUESTSTRING="cat startup-config"
	    RFOLDER="Backups/Keenetic/"
	    OUT=/tmp/temp.txt
	    echo -n > $OUT 
	    TelnetRequest $ip "${REQUESTSTRING}" $OUT
	    cat $OUT | sed 's/\r$//; 1,/name = startup-config:/d; /(config)>/,$d' > $TFTPROOT/$ip.cfg
	;;

	"DGS-1100-08P"|"192.168.1.13" )
	    RFOLDER="Backups/Dlink/"
	    COOKIE=(`curl -i -# -X POST -d pass=$PASSWD_MD5 http://$ip/cgi/login.cgi | sed 's|.*SessID=||; s|.*Gambit=||'|sed -r 's/;path.+//'|sed -n "2,3p"`)
	    curl -X POST -d "pswType=1"  "http://$ip/cgi/backup.cgi" -H "Cookie: Gambit=${COOKIE[1]}; SessID=${COOKIE[0]}" -o $TFTPROOT/$ip.cfg
	;;
	"192.168.1.6" )
	    RFOLDER="Backups/Dlink/"
	    COOKIE=`curl -i -# --cookie-jar - -o /dev/null -X POST -d \
		"pwd=$PASSWD&login=Login&err_flag=&err_msg=" \
		"http://$ip/hp_login.html"|sed 's|.*SID\t||'|\
		sed -r 's/;\n+//'|sed -n '5p'`
	    curl -i -# -o /dev/null -X POST -d "v_1_1_1=TFTP&v_1_2_1=TFTP&v_1_2_1=TFTP&v_1_3_1=IPv4&v_1_3_1=IPv4&v_1_4_1=$TFTP_SERV&v_1_4_1=$TFTP_SERV&v_1_5_1=$ip.cfg&v_1_5_1=$ip.cfg&v_1_6_1=Configuration&v_1_6_1=Configuration&v_1_16_2=1&v_1_14_1=image2&v_1_15_1=image1&v_1_10_1=1&v_2_1_1=%%A0&submit_flag=8&submit_target=transfer_in_progress.html&err_flag=0&err_msg=&clazz_information=UploadFile.html&v_1_11_1=Upload" \
		"http://$ip/UploadFile.html" -H "Cookie: SID=$COOKIE; dw_nav=Maintenance"
	    curl -i -# -o /dev/null -X POST -d "loginpage=hp_login.html" "http://$ip/links.html" \
		    -H "Cookie: SID=$COOKIE"
	;;

    * )
	echo "$ip $MODEL Device not found">> $LOG
	NOTFOUND=1
	;;
 
    esac
    if [ $NOTFOUND -ne 1 ]; then
	sleep 5
	if [ $(SendtoFTP $ip $RFOLDER) -ne 0 ]; then
	    echo "File from $ip not ready. Try to waiting file..." >>$LOG
	    sleep 10
	    SendtoFTP $ip $RFOLDER
	fi
    fi
done
