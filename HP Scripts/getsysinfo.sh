#!/usr/bin/ksh
# @(#)Revision: 9.23$ $by S. Stechemesser, HP$ $Date: 10/22/2014$
#
#the below construct is needed no line in getsysinfo.sh is longer than 80 chars
#for cut&paste
READMELINK="https://h20565.www2.hp.com/portal/site/hpsc/template.PAGE/public"
READMELINK="$READMELINK/kb/docDisplay/?docId=emr_na-c03800758"
export LANG=C
GETSYSINFOVERSION="9.23"
#CKSUM: 3194520570
#use the TMPDIR environment variable if needed - see man mktemp
TMPDIR=${TMPDIR:-/tmp} # set TMPDIR to /tmp if not set
NAMEBASE=sysinfo  #default output name prefix
#add hostname + timestamp by default
NAME=${NAMEBASE}_`hostname`_`date +%Y%m%d%H%M` 
TDIR=$TMPDIR/$NAME
MPJAVA=0           #do not run jar file by default, only with -mp option
GETOA=0            #get OA info via telnet	
SD2=0              #do not run be default
SGINFO=0	   #do not run sginfo by default
MAXFILESIZE=1024 # Maximum size of some logfile in kbytes
GETFIRSTLINES=2000 # if logfiles are truncated, also the first lines are saved
MAXBACKDATE=180 # for some logfiles: get information less than 180 days old
RUNCRASHINFO=0 #1=run crashinfo on last crash  
               #2=run crashinfo for all crashes
SAN=0 #do not capture fcddiag by default
NET=0 #do not capture nettl and netstat logs by default
diskjn=0 #do not query all disks with diskinfo or scsimgr by default
INITDATA=0 # do not capture initdata stuff by default
PMANI=0 # do not use print_manifest by default
SASOPTION=1 # 0: run sasmgr in any case
XPINFO=0 #1: run XPINFO
NOHIST=0 #evweb -b history by default (set to 1 if it makes problems) 
NMVMUNIX=0 # do not collect symbols from vmunix by default
ESCSIDIAG=0 #do not capture escsi_diag output
SWINFO=0    #higher values capture more data for SW suport
OSELOGS=1   #capturing of /var/opt/psb/oselogs 
#
#better do not change parameters below here unless you know what you are doing
#Integrity check
CksumCalc=`grep -v CKSUM: $0 | cksum | cut -d" " -f 1`
CksumPost=`grep CKSUM: $0 | cut -d" " -f 2 | head -1`
if [ $CksumCalc != $CksumPost ] ; then
 echo "WARNING: Script $0 is modified or currupt"
 echo "The calculated checksum does not match $0 version  $GETSYSINFOVERSION"
 echo "    Calculated: $CksumCalc"
 echo "    Expected  : $CksumPost"
 echo "    if in doubt, press CTRL-C within 10 seconds to abort"
sleep 10
fi
WARNING="" 
HPMPLVER=hpmpl.285.jar
HPMPL=$PWD/$HPMPLVER #external jar File to collect MP data
OPDIR=$PWD     #save actual directory for later use
SGINFOEXE=$OPDIR/sginfo #default location of sginfo
SD2COLLECT=sd2collect.pl   #SD2 data collector
NSYSINFO_ADDCMDS=0  #number of additional commands to run
U=`uname`  
if [ "T$U" != "THP-UX" ] ; then
   echo "Script is only supported on HP-UX ! - Abort"; exit -1
fi
CPOPT="-p"
whoami | grep -q root
if [ $? -ne 0 ] ; then
   echo "WARNING - Script should be run as root user. Continue ? (y/n)"  
   read JN
   if [ "j$JN" = "jn" ] ; then
     exit 
   fi 
   CPOPT=""
fi

PATH=${PATH}:/usr/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/contrib/bin
PATH=${PATH}:/opt/sas/bin:/opt/fcms/bin
export PATH
secure=0 
tgz=1
echo "getsysinfo.sh version $GETSYSINFOVERSION"
echo "options: "
echo "-a   : get all information except -diag (-h -f -san -xp -p -net -d)"
echo "-s   : secure, use only non hanging commands"
echo "-h   : get all files from /var/tombstones directory instead only those"
echo "     : younger than $MAXBACKDATE days.Collect SFM hist. and SAL records" 
echo "-f   : do not truncate some of the logfiles to $MAXFILESIZE kB" 
echo "-f \"regexp\": filter syslog files with regexp (e.g. \"inetd|ftpd\")" 
echo "-sh  : make shell archive $NAME.shar (ascii)"
echo "-u   : uuencoded tgz file => $NAME.uu (ascii)" 
echo "-n FN: explicitly set output filename to FN"
echo "-d   : diskinfo from all disks (scsimgr get_info on 11.31)"
echo "-san : capture fcddiag (or td-,fclp-,fcocdiag)"
echo "-net : capture netfmt /var/adm/nettl.LOG000 "
echo "-p   : include information from print_manifest"
echo "-diag: capture additional data for STM/EMS/SFM problems - Huge output !"
echo "-sw  : capture additional information needed for software support"
echo "-c [all|N]: run crashinfo on last N crashdumps (<$MAXBACKDATE days)"
echo "-xp  : get information about XP diskarrays with xpinfo (may take long)"
echo "-oa  : capture show all etc. from onboard administrator (OA) via telnet"
echo "-mp  : run external mp collection java program $HPMPLVER"
echo "-mpopt \"options\" - set additional options for $HPMPLVER"
echo "-sd2 : capture Superdome 2 or C[37]000 OA logs with external $SD2COLLECT"
echo "-sd2opt \"options\" - set additional options for $SD2COLLECT"
echo "-sginfo : run sginfo service guard data collector - must be in same dir"
echo "-x file : capture file as additional information"
echo "-x 'exec:command' : log the output of command to file addcmds.log"
echo "For more details on getsysinfo.sh please see\n$READMELINK\n"
for I in "$@"
do
  echo $I | grep -q -e "^-"
  if [ $? -eq 0 ] ; then
  OLDOPTIONS="$OLDOPTIONS $I"
  else 
  OLDOPTIONS="$OLDOPTIONS \"$I\""
  fi
done
while [ $# -gt 0 ]
do
i=$1
shift
case $i in
-s)
   secure=1
   echo "I will only use normaly non hanging commands "
;;
-sh)
   tgz=0
;;
-t)
   tgz=1
;;
-u)
   tgz=2
;;
-sginfo)
if [ -f /etc/cmcluster.conf ] ; then
SGINFO=2
NAME=${NAMEBASE}+sginfo_`hostname`_`date +%Y%m%d%H%M`
else
  echo "No Service Guard detected on this system"
fi
;;
-n)
#check if name argument was given
NEXT="-"
if [ $# -gt 0 ] ; then
  NEXT=$1
fi
echo $NEXT | grep -q -E "^-"
if [ $? -eq 1 ] ; then
  OUTFILE=$1 
  shift
  echo "setting output filename to $OUTFILE"
else
  H=`hostname`
  NAME=${NAMEBASE}_${H}_`date "+%d.%m.%Y_%H.%M"`
fi
;;
-a)
  MAXFILESIZE=0
  MAXBACKDATE=10000
  SAN=1
  XPINFO=1
  NET=1
  PMANI=1
  diskjn=1
  NMVMUNIX=1
  ESCSIDIAG=1
  SD2OPT="-a"
  OSELOGS=1
  RUNCRASHINFO=1
  SGINFO=1
  echo "-a option set :  using options  -h -f -d -net -xp -san -p -sw -sginfo"
;;
-f)
   #check if additional parameter to exclude lines from syslog
   if [ $# -gt 0 ] ; then
    echo $1 | grep -q -E "^-"
    if [ $? -ne 0 ] ; then 
      export SGREP=$1
      shift
    fi
   fi
   MAXFILESIZE=0  # get full files
   SD2OPT="$SD2OPT -maxfpl 0 -maxmca 0"
;;
-d)
   diskjn=1
;;
-san)
   SAN=1
   ESCSIDIAG=1
;;
-net)
   NET=1
;;
-x)
#check if additional parameter(s)
while [ $# -gt 0 ] ; do
 echo $1 | grep -q -E "^-"
 if [ $? -ne 0 ] ; then 
   echo $1 | grep -q -e "^exec:" #command ?
   if [ $? -eq 0 ] ; then
     X=`echo $1 | cut -c 6-`
     SYSINFO_ADDCMD[$NSYSINFO_ADDCMDS]=$X #save add commands in array
     let NSYSINFO_ADDCMDS=$NSYSINFO_ADDCMDS+1
   else #additional file
    SYSINFO_ADDFILES="$SYSINFO_ADDFILES $1" 
   fi
   shift
 else
   break
 fi
done
;;
-lan)  #to prevent from typos
   NET=1
;;
-p)
   PMANI=1
;;
-h)
   MAXBACKDATE=10000
     SD2OPT="$SD2OPT -d 0"
   OSELOGS=1
   echo "I will collect more information than usual "
;;
-diag)
   let INITDATA=$INITDATA+1
   OSELOGS=1
   MAXFILESIZE=0  # same as -h -f
   MAXBACKDATE=10000
;;
-c)
   RUNCRASHINFO=1
   if [ $# -gt 0 ] ; then
    if [ $1 = "all" ] ; then
      RUNCRASHINFO=99  #maximum 99 dumps - that is really much
    else
      RUNCRASHINFO=$1  #specify the number of dumps here
    fi
   fi
;;
-sw)
   NMVMUNIX=1 
   ESCSIDIAG=1
   SWINFO=1
   SGINFO=1
   if [ $RUNCRASHINFO -eq 0 ] ; then
      RUNCRASHINFO=1  #-c option is stronger than this
   fi
;;
-xp)
   XPINFO=1
   echo "will run xpinfo. "
;;
-mpopt)
HPMPLOPT="$1"
shift
;; 
-mp)
MPJAVA=1
;;
-oa)
 GETOA=1
;;
-sd2)
SD2=1
;;
-sd2opt)
SD2OPT="$1"
;;
-nohist)
   NOHIST=1 # do not run history query on SFM evweb
   echo "evweb history will not run." 
;;
esac
done
if [ "1$OUTFILE" = "1" ]; then # automatically set output filename
OUTFILE="$NAME.shar"
if [ $tgz -eq 1 ] ; then OUTFILE="$NAME.tgz" ; fi
if [ $tgz -eq 2 ] ; then OUTFILE="$NAME.tgz.uu" ; fi
OUTFILE=$TMPDIR/$OUTFILE
echo "setting output filename to $OUTFILE"
fi
OSVER=`uname -r`
#definition der Funktionen
hw_disk_check() # better version from Stefan Stechemesser MUHW
{
DEVICES=`ioscan -fknCdisk | grep -e /rdsk/ | cut -d "/" -f4`
printf "\n%-24s%-10s%-22s%-8s%-8s%-3s%-3s\n" Hardwarepath Device \
Vendor/Product Cap/GB Firm. QD IR
echo "-----------------------------------------------------------------------\
-------"
for device in $DEVICES
do
      scsi=`/usr/sbin/scsictl -akq /dev/rdsk/$device 2>/dev/null`
      sir=`echo $scsi|awk -F";" '{ print $1; }{}'`
      sqd=`echo $scsi|awk -F";" '{ print $2; }{}'`
      hw_pfad=` lssf /dev/dsk/$device  | awk '{ print $(NF-1) }'`
      printf "%-24s%-10s" $hw_pfad $device
      (diskinfo -v /dev/rdsk/$device 2> /dev/null \
| grep -e product -e rev -e vendor -e size) |\
awk '{if(match($1,"vendor:")) {vendor=$2}} \
{if (match($1,"product")) {product=$3}} \
{if (match($1,"size:")) {size=$2}} \
{if (match($1,"rev")) {vend_p=vendor"/"product;printf "%-22s%-8.1f%-8s",\
vend_p,(size+0.01)/1000000,$3}} '
printf "%-3s%-3s\n" $sqd $sir
done
}
sizefile()
{
# copies only the last FILESIZE bytes of file FILE
 FILE=$1
 FILESIZE=$2
 SOUTFILE=$TDIR/$3
 if [ -f $FILE ] ; then
    FSIZE=`ls -l $FILE | awk '{print $5}' `
    let FSIZE=$FSIZE/1024 #calculate size in kBytes
    if [ $FSIZE -gt $FILESIZE -a $FILESIZE -ne 0 ] ; then
       NBLOCKS=`expr \( $FSIZE - $FILESIZE \) `
       echo "Truncating File $FILE from $FSIZE to $FILESIZE kB  "
       (#get first $GETFIRSTLINES lines of file
       echo "WARNING from : $0"
       echo "File $FILE truncated from $FSIZE to $FILESIZE kbytes by $0"
       echo "here are the first $GETFIRSTLINES lines of the file:"
       echo "#############################################################"
       head -n $GETFIRSTLINES $FILE
       echo "#############################################################"
       echo "$0: here are the last $FILESIZE kbytes of this file"
       echo "#############################################################"
       dd if=$FILE bs=1k skip=$NBLOCKS )> $SOUTFILE
    else
       echo "getting $FILE"
       echo $FILE|grep -q syslog
       if [ $? -eq 0 -a "X$SGREP" != "X" ] ; then
	  echo "filtering lines !~/$SGREP/"
	  perl -n -e "if(! /$SGREP/){print \$_;}" <$FILE  > $SOUTFILE
       else
         cp $FILE $SOUTFILE
       fi
    fi
    touch -r $FILE $SOUTFILE  #set timestamp
 else
    echo File $FILE does not exist
 fi
}
copyfiles()
{
#looking for files younger then $MAXBACKDATE days or give back the latest file
  FILE=$1
  DIR=$2
  RESULT=`find  $DIR -mtime -$MAXBACKDATE -a -type f | grep "$FILE"`
  if [ "TEST$RESULT" = "TEST" ] ; then
  RESULT=`ls -rt $DIR/${FILE}* | tail -1`
  fi
  if [ "TEST$RESULT" != "TEST" ] ; then
    cp $CPOPT $RESULT $TDIR
  fi
}
ex_cat()
{ #appends a file  to a logfile if it exists
 if [ -f $1 ] ; then
  echo `date +"%T"` "cat $1 >> $2"
  ( echo "### $1 ###" ; cat $1 ) >>  $TDIR/$2 2>&1
 fi
}
ex_log()
{ #executes and logs a command
echo `date +"%T"` "$1 >> $2" ; ( echo "### $1 ###"
if [ `echo $1 | grep -c -e '|'` -gt 0 ]; then
eval $1
else
$1
fi ) >> $TDIR/$2 2>&1
return $?
}
ex_log2()
{ #executes a program only if it exists
THISCOMMAND=`echo "$1" | cut -d ' ' -f 1`
if [ -x $THISCOMMAND ] ; then
  ex_log "$1" $2
  return $?
fi
}
ex_log3()
{ #executes a program only if it exists and prints to STDOUT
THISCOMMAND=`echo "$1" | cut -d ' ' -f 1`
if [ -x $THISCOMMAND ] ; then
  echo `date +"%T"` "$1 >> $2" ; echo "### $1 ###"  >> $TDIR/$2
  $1 2>&1 | tee -a $TDIR/$2
  return $?
fi
}


sw_runsection()
{
#for swainv collection
#section $1  command $2
typeset COMAND="swlist $2"
print "<section name=\"$1\" cmd=\"LANG=C $COMAND\">"
print "<![CDATA["
LANG=C $COMAND
print "]]>"
print "</section>"
}

swainv() #collects logdata for patch analysis
{
typeset Target=`hostname`
echo "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>"                               
echo "<collections collect_version=\"getsysinfo.$GETSYSINFOVERSION.sh\" >"                        
echo "<collection target=\"$Target\">"
echo "<env>"
print "<attribute name=\"collection_time\" \
value=$(date -u +'"%Y-%m-%dT%H:%M:%S+0000"') \
local=\"$(date +'%d %B %Y %X %z')\" />"
typeset -i numProcs=`ioscan -fk | grep processor | wc -l`
print "<attribute name=\"cpus\" value=\"$numProcs\" />"
print "<attribute name=\"machine_model\" value=\"$(getconf MACHINE_MODEL)\" />"
print "<attribute name=\"platform\" value=\"$(uname -s)\" />"
print "<attribute name=\"os\" value=\"$(uname -r)\" />"
echo "</env>"
sw_runsection "filesets" "-l fileset -v  -x  show_superseded_patches=false \
-a is_patch -a patch_state -a software_spec -a state" 
sw_runsection "products" " -l product -v  -x show_superseded_patches=false \
-a is_patch -a install_date -a software_spec -a title"
sw_runsection "bundles" "-l bundle -v  -x show_superseded_patches=false \
-a contents -a revision -a software_spec -a title"
echo "</collection>
</collections>"
}
###########################################
###  Start of getsysinfo.sh collection  ###
###########################################
mkdir $TDIR
if [ $? -ne 0 ] ; then
echo "Could not create directory $TDIR - maybe a problem with mktemp"
echo "I try a workaround"
TDIR=$TDIR.sysinfotmp
mkdir $TDIR
if [ $? -ne 0 ] ; then
echo $TDIR also failed. please edit script and set TDIR manually - Abort.
exit -1
fi
else
echo "created tempdir $TDIR."
fi
echo $TDIR | grep -q -e "^/" #TDIR must be absolute !
if [ $? -ne 0 ] ; then
echo "WARNING - mktemp created relative path $TDIR ! Check TMPDIR variable"
cd $TDIR
if [ $? -eq 0 ] ; then
TDIR=`pwd`
echo "TDIR is set to $TDIR".
else
echo "ERROR: could not make absolute PATH out of $TDIR - TMPDIR=$TMPDIR"
echo "Abort"
exit -1
fi
fi
#Log the stdout stderr to getsysinfo.log 
logfile=$TDIR/getsysinfo.log 
tee $logfile >&2 |& 
exec >&p 2>&1 
echo 
echo =================================== 
echo version : $GETSYSINFOVERSION 
echo arguments to $0: $OLDOPTIONS
echo =================================== 
echo 
echo "getting system information "
/bin/uname -a > $TDIR/config
/bin/model >> $TDIR/config
SYSTYPE=PA
EOPTION=""
model | grep -q -E "^ia64" 
if [ $? -eq 0 ] ; then
  SYSTYPE=IA64
  EOPTION="e" 
fi
model | grep -q -v -e BL8 -e "Superdome2"
BLADEJN=$?  #1 if this is a blade
echo "Systemtype: $SYSTYPE "
(echo "Uptime  and Date:" 
uptime
date 
echo "$0 version $GETSYSINFOVERSION" 
echo $0 options: $OLDOPTIONS
echo $0 cksum: $CksumCalc \\c
if [ $CksumCalc != $CksumPost ] ; then
 echo " (expected: $CksumPost)"
else 
 echo " (OK)"
fi
echo "LANG=\"$LANG\""  ) >> $TDIR/config
OA_IP=""
MP_IP=""
MASTERBLADE=""
if [ $MPJAVA -gt 0 -o $SD2 -gt 0 -o $GETOA -gt 0 ] ; then #try guess MP/OA IPs
if [ -x /opt/propplus/bin/cprop -a $secure -eq 0 ] ; then
 /opt/wbem/sbin/cimconfig -l -c | grep -q "CIM server is not running"
 if [ $? -ne 0 ] ; then  #we can run cprop
 echo "guessing some system parameters from cprop ..."
 /opt/propplus/bin/cprop -list >$TDIR/cprop.txt
 getfromcprop() #function to grep some data out of cprop
 {
  grep -v "Unknown" $TDIR/cprop.txt | grep -q "$1"
  if [ $? -eq 0 ] ; then
   echo getting $2 information from cprop -detail -c \"$1\" 1>&2
   /opt/propplus/bin/cprop -detail -c "$1" |grep "$2" |head -1 |\
   cut -d : -f 2- | sed 's/^ *//;s/ *$//'
  else 
   echo "$2 information not available from cprop" 1>&2
  fi
 }
  MASTERBLADE=`getfromcprop Blade "BayID_get"`
  OA_IP=`getfromcprop "Enclosure Information" ManagementIPAddress`
  MP_IP=`getfromcprop "Management Processor" IPAddress`
 fi
fi
if [ "X$OA_IP" != "X" ] ; then
  echo "OA_IP (from cprop) : $OA_IP" | tee -a $TDIR/config
fi
if [ "X$MASTERBLADE" != "X" ] ; then
  echo "MASTERBLADE Slot (from cprop) : $MASTERBLADE" | tee -a $TDIR/config
fi
if [ "X$MP_IP" != "X" ] ; then
  echo "MP_IP (from cprop) : $MP_IP" | tee -a $TDIR/config
fi
fi #end guessing IP addresses
if [ $MPJAVA -eq 1 ] ; then
#java wrapper 
 if [ "T$JAVA_HOME" = "T" ] ; then
  echo "JAVA_HOME not set. trying to guess it "     
  if [ -d /opt/java6/jre ]; then
   JAVA_HOME=/opt/java6/jre
  else
   JAVA_HOME=`ls -rtd /opt/* | grep java | tail -1`/jre
  fi
  echo "JAVA_HOME set to $JAVA_HOME"
 fi
 JAVA=$JAVA_HOME/bin/java 
 if [ ! -x $JAVA ] ; then
  echo could not find a JAVA executable in $JAVA . 
  echo "Please set JAVA_HOME (path to jre or jdk)"
  echo "could not start $HPMPL - do not use -mp option."
  exit -1;
 fi
 #check JAVA version
 echo "checking JAVA version"
 $JAVA -version 2>&1 | perl -n -e 'if(/java version \"(\d+.\d+)/)
{$v=$1;print $_; if($v >= 1.5){exit(1);}}'
 if [ $? -ne 1 ] ; then
  echo "At least Java version 1.5 needed for $HPMPL - Abort"
  echo "rerun without -mp option"
  exit -5
 fi
 cd $TDIR
 if [ ! -f $HPMPL ] ; then
   X=`ls -rt $OPDIR/hpmpl.*.jar | tail -1`
   if [ "T$X" != "T" ] ; then
      echo "WARNING: Could not find actual $HPMPL\nusing $X instead ..." 
      HPMPL=$X
   else
      echo "ERROR: Could not find $HPMPL - abort" 
      echo "rerun without -mp option."
      exit -2
   fi
 fi
 if [ $BLADEJN -eq 1 -a "X$HPMPLOPT"="X" ] ; then
 cat<<EOF
The -mp option was given to capture additional data from the MP or OA.
As this is a blade system, it is strongly recommended to capture all data 
from the Onboard Administrator (OA) $OA_IP.
Please give the OA IP Address, user and password when asked later and the OA
data and Blade MP logs from all Integrity Blades will be captured by the 
$HPMPL script using ssh.
Note: No login credentials will ever be saved to any file by getsysinfo.sh
EOF
 if [ "X$HPMPLOPT"="X" -a "X$OA_IP" != "X" ] ; then
   HPMPLOPT="-ssh -h $OA_IP -oamp" #we set the OA IP address
   if [ "X$MASTERBLADE" != "X" ] ;then
     HPMPLOPT="$HPMPLOPT $MASTERBLADE"; #collect MP info only from Master
     echo setting hostname for OA to $OA_IP from cprop
     echo !!! please give OA  login and password when asked by HPMPL !!!
   fi
 else
   HPMPLOPT="-ssh -oamp"
   echo !!! please give OA IP, login and password when asked by HPMPL !!!
 fi    
 echo
 fi #end BLADEJN=1
 if [ "X$HPMPLOPT" = "X" -a "X$MP_IP" != "X" ] ; then #try setting default
    echo setting hostname for MP to $MP_IP from cprop
    HPMPLOPT="-ssh -h $MP_IP"
 fi
 echo $JAVA -jar $HPMPL $HPMPLOPT 
 $JAVA -jar $HPMPL $HPMPLOPT | tee $TDIR/hpmpl.log 2>&1
 cd $OPDIR
fi #end HPMPL
#
if [ $GETOA -eq 1 ] ; then
 echo "Enter OA IP or hostname (default: $OA_IP): "
 read OAHOSTNAME
 if [ "T$OAHOSTNAME" = "T" ] ; then
  OAHOSTNAME=$OA_IP
 fi
 echo "Enter OA username [Administrator]"
 read OAUSER
 if [ "T$OAUSER" = "T" ] ; then
  OAUSER=Administrator
 fi
 echo "OA Password [Admin]"
 read OAPASS
 if [ "T$OAPASS" = "T" ] ; then
  OAPASS=Admin
 fi
  echo Getting show all from OA $OAHOSTNAME with telnet 
  echo if this process does not finish in \~ 5 minutes - CTRL-C to abort.
  echo 
 (sleep 2
  echo $OAUSER
  sleep 1
  echo $OAPASS
  sleep 2
  echo "SHOW ALL"
  sleep 1
  echo "exit"
  sleep 1) | telnet $OAHOSTNAME | tee "$TDIR/show_all.$OAHOSTNAME.txt" 2>&1
  head -50 $TDIR/show_all.$OAHOSTNAME.txt | grep -q "Onboard Administrator"
  if [ $? -ne 0 ] ; then
    echo "Failed. Please collect OA logs manually from $OAHOSTNAME";
  else 
  echo "OK."
  head -50 $TDIR/show_all.$OAHOSTNAME.txt | grep -q "HP Superdome"
  if [ $? -eq 0 ] ; then
  echo "Superdome 2 OA detected. Getting additional information from OA"
  echo "This may take a while."  
  (sleep 2
   echo $OAUSER
   sleep 1
   echo $OAPASS
   sleep 2
   echo "show hr" ; sleep 1
   echo "show indict" ; sleep 1
   echo "exit" ; sleep 1
   echo "show cae -L" ; sleep 1
   echo "show fru" ; sleep 1
   echo "show errdump dir all" ; sleep 1
   echo "exit" ; sleep 1) |\
   telnet $OAHOSTNAME  >>$TDIR/show_all.$OAHOSTNAME.txt 2>&1
  fi
  fi  #end check if show all succeeded
fi
if [ $SD2 -eq 1 ] ; then
   mkdir $TDIR/sd2collect
   if [ $? -eq 0 ] ; then
   echo "running external program perl $SD2COLLECT -o $TDIR/sd2collect $SD2OPT"
   if [ -f $SD2COLLECT ] ; then 
   if [ "X$SD2OPT"="X" -a "X$OA_IP" != "X" ] ; then
     SD2OPT="-h $OA_IP";
   fi
   perl $SD2COLLECT -o $TDIR/sd2collect $SD2OPT | tee $TDIR/sd2collect.log 2>&1
   if [ $? -ne 0 ] ; then
      echo "Error during $SD2COLLECT run."
      echo "Please check OA credentials or run without -sd2 option"
      echo "if telnet is disabled on the MP try the -mp option with hpmpl.jar"
      exit -2
   fi
   else          
    echo "could not find $SD2COLLECT."
    echo "Please run without -sd2 option and try "-oa" instead !"
    exit -3
   fi
   echo "\n$SD2COLLECT finished."
   cd $OPDIR
   fi #end cd 
fi
echo "getting process information"
echo $OSVER | grep -q -e 11.00 -e 10.20
echo "getting process information"
echo $OSVER | grep -q -e 11.00 -e 10.20
if [ $? -eq 0 ] ; then
  PSOPT=ef
else
  PSOPT=AHflx #only for >11.00
fi
export UNIX95=1
ex_log "ps -$PSOPT" ps_top.txt
unset UNIX95
ex_log "top -f $TDIR/ps_top.txt -d 1 -n 128" ps_top.txt
if [ $secure -eq 0 ];then
echo CS_MACHINE_SERIAL: `/usr/bin/getconf CS_MACHINE_SERIAL` >> $TDIR/config
echo PARTITION_IDENT  : `/usr/bin/getconf PARTITION_IDENT` >> $TDIR/config
echo "temporary directory: $TDIR" >> $TDIR/config
ex_log setboot config
ex_log set config
echo "vgdisplay -v " | tee -a  $TDIR/config.lvm
vgdisplay -v >> $TDIR/config.lvm   2>&1 
#begin vxvm output
if [ -x /usr/sbin/vxdctl ] ; then
TMP=`/usr/sbin/vxdctl mode | awk ' { print $2 } '`
if [ "$TMP" != "disabled" -a "$TMP" != "not-running" ] ; then
ex_log "/usr/sbin/vxdctl -c mode" vxvm.txt
ex_log "/usr/sbin/vxdctl license" vxvm.txt
ex_log "/usr/sbin/vxprint -ht" vxvm.txt
ex_log "/usr/sbin/vxdisk list" vxvm.txt
/usr/sbin/vxdisk -e list > /dev/null 2>&1
if [ $? -eq 0 ] ; then
ex_log "/usr/sbin/vxdisk -e list" vxvm.txt
fi
ex_log "/usr/sbin/vxdisk -o alldgs list" vxvm.txt
ex_log "/usr/sbin/vxdisk -s list" vxvm.txt
ex_log "/usr/sbin/vxdg list" vxvm.txt
# the "bootdg" option is new in 4.0
/usr/sbin/vxdg help 2>&1 | grep "bootdg" >> /dev/null
if [ $? -eq 0 ] ; then
ex_log "/usr/sbin/vxdg bootdg" vxvm.txt
fi
for i in `/usr/sbin/vxdg -q list | awk ' { print $1 } '`
do
ex_log "/usr/sbin/vxdg list $i" vxvm.txt 
ex_log "/usr/sbin/vxstat -g $i -ffc -d" vxvm.txt
ex_log2 "/usr/sbin/vxdmpadm gettune dmp_cache_open" vxvm.txt
done
fi
fi #end vxvm section
fi
if [ $secure -eq 1 ] ; then
  ioscanopt='k';
  EOPTION=""
fi
IOSCAN=$TDIR/ioscan.txt
if [ "`uname -r`" = "B.11.31" ] ; then
  echo "for ioscan -fnk see file ioscan_fnk.txt" > $IOSCAN
  ex_log "insf -Lv" ioscan.txt
  ex_log "ioscan -fN$ioscanopt" ioscan.txt
  IOSCAN=$TDIR/ioscan_fnk.txt
  ex_log "insf -Lv" ioscan_fnk.txt
  ex_log "ioscan -fkn$EOPTION" ioscan_fnk.txt
  model | grep -q Superdome2
  if [ $? -eq 0 ] ; then  
    ex_log "ioscan -${ioscanopt}m resourcepath" ioscan.txt
  fi
  ex_log "ioscan -${ioscanopt}m dsf" ioscan.txt
  ex_log "ioscan -${ioscanopt}m lun" ioscan.txt
  ex_log "ioscan -${ioscanopt}m hwpath" ioscan.txt
  echo ioscan -P health
  ex_log "ioscan -P health | grep -v -e online -e N/A" ioscan.txt
  ex_log "ioscan -P physical_location | grep -v N/A" ioscan.txt
  ex_log "ioscan -P wwid | grep -v N/A" ioscan.txt
  ex_log "ioscan -s" ioscan.txt
else
  ex_log "ioscan -fn$ioscanopt" ioscan.txt
fi
ex_log "ls -lR /dev" ioscan.txt
if [ $secure -eq 0 ];then
echo "getting bootconfig "
ex_log "lvlnboot -v" bootconf.txt 
cat $TDIR/bootconf.txt >> $TDIR/config.lvm 
for i in `cat $TDIR/bootconf.txt | \
awk '{if(match($0,"Boot Disk")){print $1}}' ` 
do
(echo "checking bootdisk $i "
if [ "X$SYSTYPE" = "XPA" ] ; then
 echo "### lifls -l $i ###" 
 lifls -l $i  
 echo "### AUTO file of $i ###"  
 lifcp $i:AUTO $TDIR/AUTO
 cat $TDIR/AUTO 
fi  
if [ "X$SYSTYPE" = "XIA64" ] ; then
  EFIFS=`echo $i | sed -e "s/p2/p1/" -e "s/s2/s1/"`
 (
  echo "### grep vmunix: Boot device /var/adm/syslog/syslog.log"
  grep 'vmunix: Boot device' /var/adm/syslog/syslog.log
  echo "### EFI Filesystem ###\nefi_ls -d $EFIFS"
  efi_ls -d $EFIFS 
 echo efi_ls -d $EFIFS efi 
 efi_ls -d $EFIFS efi 
 echo efi_ls -d $EFIFS efi/hpux
 efi_ls -d $EFIFS efi/hpux )|  tee -a $TDIR/efils.txt
 efi_cp -d $EFIFS -u efi/hpux/AUTO $TDIR
 echo "### contens of AUTO file ###"
 cat $TDIR/AUTO 
fi
) >>  $TDIR/bootconf.txt
 rm $TDIR/AUTO
done
fi
(echo
echo "### setboot: ###"
setboot 
echo
for i in /stand/ioconfig /etc/ioconfig /stand/ext_ioconfig /etc/ext_ioconfig
do
if [ -f $i ] ; then
echo ### $i ###
ll $i
cksum $i
fi
done
echo "### Contents of /stand: ###" 
ll  -R /stand ) >> $TDIR/bootconf.txt
if [ -x /usr/contrib/bin/machinfo ] ; then
/usr/contrib/bin/machinfo -m > $TDIR/machinfo.txt 2>/dev/null
if [ $? -ne 0 ] ; then #only some new systems support -m option
/usr/contrib/bin/machinfo > $TDIR/machinfo.txt
fi
fi
#capture oselogs for Tukwila and newer systems
if [ $OSELOGS -eq 1 -a -d /var/opt/psb/oselogs ] ; then
  echo "capturing /var/opt/psb/oselogs ..."
  tar -cvf - -C /var/opt/psb oselogs | gzip -9 -c > $TDIR/oselogs.tgz
fi
if [ -x /usr/bin/graphinfo ] ; then
/usr/bin/graphinfo > $TDIR/graphinfo.txt  2>&1
fi
if [  -s /var/dt/Xerrors ] ; then
cp $CPOPT /var/dt/Xerrors $TDIR
fi
#for partitioned systems get partition status
model |  grep -q -e "S[Du1]" -e "r[xp][78]"
if [ $? -eq 0 -a -x /usr/sbin/parstatus ] ; then
   echo "### parstatus ### "  | tee $TDIR/partition.txt
   /usr/sbin/parstatus  >> $TDIR/partition.txt 2>&1  # cellbased ?
   if [ $? -eq 0 ] ; then #not if an error has happened
   for i in `parstatus -P -M | perl -n -e \
    'if(/partition:(\d+)/){print "$1 ";}' `
   do
      ex_log "parstatus -p $i -V" partition.txt 
   done
   for i in `parstatus -C -M | perl -n -e \
    'if(/cell:cab(\d),cell(\d)/){ print "$1/$2 ";}' \
    -e 'if(/blade:\s+(\S+)/){print "$1 ";}' `
   do
      ex_log "parstatus -c $i -V" partition.txt 
   done
   fi
fi
if [ -x /usr/sbin/vparstatus ] ; then
   echo "vparstatus "
   ex_log /usr/sbin/vparstatus partition.txt 
   ex_log "/usr/sbin/vparstatus -m"  partition.txt 
   ex_log "/usr/sbin/vparstatus -v"  partition.txt  
   ex_log "/usr/sbin/vparstatus -A" partition.txt
if [ -x /usr/sbin/vparextract ] ; then
   ex_log "/usr/sbin/vparextract -l" partition.txt
else
   ex_log "/usr/sbin/vparstatus -e"  partition.txt 
fi
fi
if [ -x /opt/hpvm/bin/vparstatus ] ; then # vpars 6.X
 ex_log2 /opt/hpvm/bin/vparstatus partition.txt
 grep "No vPars or VMs currently configured" $TDIR/partition.txt
 if [ $? -ne 0 ] ; then
   ex_log2 "/opt/hpvm/bin/vparstatus -v" partition.txt
   ex_log2 "/opt/hpvm/bin/vparstatus -A" partition.txt
   ex_log2 "/opt/hpvm/bin/vparnet" partition.txt
   ex_log2 "/opt/hpvm/bin/vparnet -V" partition.txt
   ex_log2 "/opt/hpvm/bin/vparhwmgmt -p cpu -l" partition.txt
   ex_log2 "/opt/hpvm/bin/vparhwmgmt -p memory -l" partition.txt
   ex_log2 "/opt/hpvm/bin/vparhwmgmt -p dio -l" partition.txt
   (echo "\n### see hpvmstatus.txt for further info on vPars 6.X ###" 
   echo "\n### see fcmsutil.out for NPIV information ###")\
    >>$TDIR/partition.txt
 fi
fi
VMGUEST=0
model | grep -q -E "Virtual "
if [ $? -eq 0 ] ; then  #virtual machine guest
 VMGUEST=1
 if [ -x /opt/hpvm/bin/hpvminfo ] ; then
 ex_log2 "/opt/hpvm/bin/hpvminfo -v" hpvmstatus.txt  
 ex_log2 /opt/hpvm/bin/hpvminfo hpvmstatus.txt  
 ex_log2 "/opt/hpvm/bin/hpvminfo -V" hpvmstatus.txt  
 ex_log2 "/opt/hpvm/bin/hpvmdevinfo" hpvmstatus.txt
 VMHOST=`grep Hostname $TDIR/hpvmstatus.txt | cut -f 2 -d : `
 fi
 #attach gvsdmgr output to fcmsutil.out
 X=/opt/gvsd/bin/gvsdmgr
 if [ -x $X ] ; then
echo "### gvsd fibre channel info see fcmsutil.out ###" >> $TDIR/hpvmstatus.txt
  for I in `ioscan -fnkd gvsd | grep /dev/gvsd` 
  do
   ex_log "$X get_info -D $I" fcmsutil.out
   ex_log "$X get_stat -D $I" fcmsutil.out
   ex_log "$X get_info -D $I -q tgt=all" fcmsutil.out
   ex_log "$X get_stat -D $I -q tgt=all" fcmsutil.out
  done
 fi
else  #not a vm guest
 if [ -x /opt/hpvm/bin/hpvmstatus ] ; then
   ex_log2 "/opt/hpvm/bin/hpvmstatus -v"  hpvmstatus.txt
   grep "No vPars or VMs currently configured" $TDIR/hpvmstatus.txt
   if [ $? -ne 0 ] ; then
    ex_log2 "/opt/hpvm/bin/hpvmnet -v"  hpvmstatus.txt
    ex_log2 "/opt/hpvm/bin/hpvmstatus -V"  hpvmstatus.txt
    ex_log2 "/opt/hpvm/bin/hpvmstatus -s"  hpvmstatus.txt
    ex_log2 "/opt/hpvm/bin/hpvmstatus -m"  hpvmstatus.txt
    ex_log2 "/opt/hpvm/bin/hpvmdevinfo" hpvmstatus.txt
    ex_log2 "/opt/hpvm/bin/hpvmnet -V"  hpvmstatus.txt
    ex_log2 "/opt/hpvm/bin/hpvmmgmt -V -l ram" hpvmstatus.txt
    for i in `hpvmstatus -M | cut -d : -f 1`
    do
     echo "\n### Recources for vm $i ###\n" >> $TDIR/hpvmstatus.txt
     ex_log "/opt/hpvm/bin/hpvmstatus -P $i" hpvmstatus.txt
     ex_log "/opt/hpvm/bin/hpvmdevinfo -P $i -V" hpvmstatus.txt
     ex_log "/opt/hpvm/bin/hpvmstatus -d -P $i" hpvmstatus.txt 
     ex_log "/opt/hpvm/bin/hpvmstatus -C -P $i" hpvmstatus.txt 
     ex_log "/opt/hpvm/bin/hpvmstatus -r -P $i" hpvmstatus.txt 
     ex_log "/opt/hpvm/bin/hpvmstatus -i -P $i" hpvmstatus.txt 
     ex_log "/opt/hpvm/bin/hpvmstatus -e -P $i" hpvmstatus.txt 
     if [ $secure -eq 0 ] ; then
      echo "/opt/hpvm/bin/hpvmconsole -P $i -q -c \"rec -view\""
     (echo "### /opt/hpvm/bin/hpvmconsole -P $i -q -c \"rec -view\" ###"
     /opt/hpvm/bin/hpvmconsole -P $i -q -c "rec -view" )\
     >> $TDIR/hpvmstatus.txt
     ex_log "/opt/hpvm/bin/hpvmconsole -P $i -q -c cl" hpvmconsole.$i.txt
     fi
   done
  fi
 fi
fi
/etc/dmesg > $TDIR/dmesg.txt
ex_log "swlist -l bundle" swlist.txt
echo "_______________________________________" >> $TDIR/swlist.txt
ex_log "swlist -l product -a date -a title -a revision" swlist.txt
echo "checking for unconfigured patches "
(echo " ### swlist -l fileset -a state | grep -E -v '^#|conf' ###"
swlist -l fileset -a state | grep -E -v '^#|conf' )>>$TDIR/swlist.txt
sizefile /var/adm/sw/swagent.log   $MAXFILESIZE   swagent.log
echo $OSVER | grep -q -e 10.20
if [ $? -ne 0 ] ; then
 echo "capturing swainv sw_inventory.xml for patch analysis "
 swainv inventory.xml > $TDIR/sw_inventory.xml
fi
echo "getting lvmtab shutdownlog fstab rc.log syslog and OLDsyslog \
information "
if [ -x  /usr/sbin/lvmadm ] ; then
 ex_log "/usr/sbin/lvmadm -l" config.lvm
fi
ex_log "strings /etc/lvmtab" config.lvm
if [ -f /etc/lvmtab_p ] ; then
   ex_log "strings /etc/lvmtab_p" config.lvm
fi
echo "### fstab: ###" >> $TDIR/config.lvm
cat /etc/fstab >> $TDIR/config.lvm
echo "getting kernel module status "
if [ -x /usr/sbin/kcmodule ] ; then
(/usr/sbin/kcmodule
/usr/sbin/kctune ) > $TDIR/kernelconf.txt
else
cp /stand/system $TDIR/kernelconf.txt
fi
ex_log2 /usr/sbin/kcusage kernelconf.txt
what /stand/vmunix >> $TDIR/kernelconf.txt
cp $CPOPT /etc/shutdownlog $TDIR
sizefile /etc/rc.log $MAXFILESIZE rc.log
sizefile /etc/rc.log.old $MAXFILESIZE rc.log.old
cp /etc/syslog.conf $TDIR
sizefile /var/adm/syslog/syslog.log   $MAXFILESIZE   syslog.log
OLDSYSLOG=`ls -rt /var/adm/syslog | grep OLDsyslog | tail -1` 
if [ "Test$OLDSYSLOG" != "Test" ] ; then
  sizefile /var/adm/syslog/$OLDSYSLOG   $MAXFILESIZE  $OLDSYSLOG
fi
echo "getting lan information"
NWMGR=/usr/sbin/nwmgr
ex_log2 $NWMGR lanconfig.txt
if [ $secure -eq 0 ] ; then
 if [ -x $NWMGR ] ; then #nwmgr instead of lanscan
  ex_log "ioscan -fnkC lan" lanconfig.txt
  grep -q hp_apa $TDIR/lanconfig.txt
  if [ $? -eq 0 ] ; then
     ex_log "$NWMGR -g -S apa" lanconfig.txt
  fi
  grep -q vlan $TDIR/lanconfig.txt
  if [ $? -eq 0 ] ; then
     ex_log "$NWMGR -g -S vlan" lanconfig.txt
  fi
  X=mib
  if [ $NET -eq 1 ] ; then
   X=extmib
  fi
  for I in `$NWMGR |cut -f 1 -d " " | grep lan`;do
   LANNR=` echo $I | cut -c 4- ` 
   if [ $LANNR -ge 5000 ] ; then #vlans
    ex_log "$NWMGR -g -v -c $I" lanconfig.txt
    ex_log "$NWMGR -g --st -c $I " lanconfig.txt
   elif [ $LANNR -ge 900 ] ; then #hp_apa
    ex_log "$NWMGR -A all -S apa -c $I" lanconfig.txt
    ex_log "$NWMGR -g --st $X -c $I" lanconfig.txt 
   else #all other lan drivers
    ex_log "$NWMGR -q vpd -c $I" lanconfig.txt
    ex_log "$NWMGR -q info -c $I" lanconfig.txt
    ex_log "$NWMGR -g --st $X -c $I" lanconfig.txt #statistics
   fi
  done
 else #no nwmgr present
  ex_log2 /usr/sbin/lanscan  lanconfig.txt
  F=`perl -n -e 'if(/lan(\d+)/) { print "$1 ";}' $TDIR/lanconfig.txt`
  uname -r | grep -q 11   #not tested for HPUX 10.20
  if [ $? -eq 0 ] ; then
  lanadmin -? 2>&1 | egrep -q "^g "
  if [ $? -eq 0 ] ; then  #only if -g option exists
   for I in $F
   do
    ex_log "lanadmin -x vpd $I" lanconfig.txt
    ex_log "lanadmin -x vmtu $I" lanconfig.txt
    ex_log "lanadmin -g $I" lanconfig.txt
   done
  fi
  fi #end 10.20 test
 fi #end test if nwmgr is there
 ex_log "netstat -inv" lanconfig.txt
 ex_log "netstat -rnv" lanconfig.txt
 ex_log "netstat -gn" lanconfig.txt
 ex_log "netstat -s" lanconfig.txt
fi
ex_cat /etc/hosts lanconfig.txt
ex_cat /etc/rc.config.d/netconf lanconfig.txt
ex_cat /etc/rc.config.d/netconf-ipv6 lanconfig.txt
ex_cat /etc/rc.config.d/hp_apaconf lanconfig.txt 
ex_cat /etc/rc.config.d/hp_apaportconf lanconfig.txt 
ex_cat /etc/rc.config.d/vlanconf  lanconfig.txt 
ex_cat /etc/lanmon/lanconfig.ascii  lanconfig.txt
if [ $NET -eq 1 ] ;then
 echo /usr/sbin/netfmt /var/adm/nettl.LOG000 
 /usr/sbin/netfmt /var/adm/nettl.LOG000 > $TDIR/nettl.LOG000.txt 2>&1
 sizefile $TDIR/nettl.LOG000.txt $MAXFILESIZE  nettl.txt
 rm $TDIR/nettl.LOG000.txt
 ex_log "netstat -a" lanconfig.txt
fi
if [ $diskjn -eq 1 ] ; then 
 echo getting information about hardisks 
 #for HPUX 11.31
 echo $OSVER | grep -q -e "11.31"
 if [ $? -eq 0 ] ;then # run scsictl for all SCSI luns
 for i in `ioscan -m lun | perl -n -e \
 'if(/(\/dev\/rdisk\/disk\d+[\n|\s]|\/dev\/pt\/pt\d+)/){print "$1\n";}' `
 do
    ex_log "scsimgr get_info -D $i" diskinfo.txt 
 done
 else
   hw_disk_check | tee $TDIR/diskinfo.txt 
 fi
fi
if [ $ESCSIDIAG -eq 1 ] ; then
 #capture escsi information
 ex_log  "/usr/bin/escsi_diag -X" escsi_diag.txt
fi
if [ $PMANI -eq 1 -a -x /opt/ignite/bin/print_manifest ] ; then
 echo "print_manifest "
 /opt/ignite/bin/print_manifest > $TDIR/print_manifest.txt
fi
LISTE=`grep -e /dev/fcms -e /dev/td -e /dev/fcd -e /dev/fclp -e /dev/fcoc \
-e /dev/fcq $IOSCAN |  awk '{printf "%s ", $1}' `
if [ "T$LISTE" != "" ]; then  #we have FC devices
echo getting fibre channel related information
for i in $LISTE
do
echo $i
 DRIVER=`echo $i | cut -d '/' -f 3 | sed 's/[0123456789]//g'`
 FCMSTOOL=${DRIVER}util
 FCMSUTIL=/opt/fcms/bin/$FCMSTOOL
 if [ -x $FCMSUTIL ] ; then
  ex_log "$FCMSUTIL $i" fcmsutil.out
  X=`echo $i | grep fcms`
  if [ "test$X" = "test" ] ; then
   ex_log "$FCMSUTIL $i vpd" fcmsutil.out
  fi
  if [ "$DRIVER" = "fcd" -a $secure -eq 0 ] ; then
    ex_log "$FCMSUTIL $i sfp" fcmsutil.out
  fi
  $FCMSUTIL $i | grep -q "NPIV Supported = YES" 
  if [ $? -eq 0 ] ; then
   ex_log "$FCMSUTIL $i npiv_info" fcmsutil.out
  fi
  ex_log "$FCMSUTIL $i stat" fcmsutil.out
 fi
done
if [ $secure -eq 0 ] ; then
for i in td fcd fclp fcoc ; do
echo $LISTE | grep -q $i
if [ $? -eq 0 -a -x /opt/fcms/bin/${i}list ] ; then
 ex_log /opt/fcms/bin/${i}list fcmsutil.out
 if [ $i = fcd -a $OSVER=B.11.31 ] ; then
    ex_log "/opt/fcms/bin/${i}list -N" fcmsutil.out
 fi
 if [ $SAN -eq 1 ] ; then  #capture XXXdiag output
    FCDIAG=/opt/fcms/bin/${i}diag
    if [ -x $FCDIAG ] ; then
     FCDNAME=${i}diag.`date '+%d.%m.%Y_%H.%M'`.txt.gz
     echo "\n###see also $FCDNAME###" >>$TDIR/fcmsutil.out
     echo "$FCDIAG | gzip -9 -c > $FCDNAME "
     $FCDIAG | gzip -9 -c >$TDIR/$FCDNAME
     DELLIST="$FCDNAME $DELLIST"
    fi 
 fi
fi
done
fi
fi
if [ -x /usr/sbin/icod_stat ] ; then
   echo "get iCAP info (icod_stat) "
   echo "icod_stat:" > $TDIR/icod.txt 
   /usr/sbin/icod_stat >> $TDIR/icod.txt 2>&1
   version=`grep "Software version:" $TDIR/icod.txt | awk '{ print $3 }' |\
   cut -d. -f2`
   if [ "Test$version" != "Test" ] ; then
   if [ $version -ge 6 ] ; then 
     echo "icod_stat -s:" >> $TDIR/icod.txt
     icod_stat -s >> $TDIR/icod.txt 2>&1
     if [ -f /var/adm/icod.log ] ; then
        cp $CPOPT /var/adm/icod.log $TDIR
     fi  
   else
     echo "icod_stat -u:" >> $TDIR/icod.txt
     icod_stat -u >> $TDIR/icod.txt 2>&1
   fi 
   fi
fi  
STMBIN="/usr/sbin/stm/ui/bin/stm"
if [ -x $STMBIN ];then      # does cstm exist ?
CSTMCOMMAND="gop termwait yes\nselall\ninfo\nwait\nil\n\nexit\n\n" 
#check regarding known issue with tape backups on HPUX 11.31
echo $OSVER | grep -q -e "11.31"
if [ $? -eq 0 ] ;then # check for known diag problem 
DIAGVER=`perl -n -e 'if(/Sup\-Tool\-Mgr.+B\.11\.31\.(\d+)/){print $1;}' < \
$TDIR/swlist.txt `
if [ $DIAGVER -lt 6 ] ; then
echo "WARNING : Diag Version < Sep 2009 - no cstm info tool will be started for tapes" 
echo "          to prevent possible stop of running backups\n"
CSTMCOMMAND="gop termwait yes\nselall\nuscl type Tape\ninfo\nwait\nil\n\nexit\n\n"
fi
fi
if [ $secure -eq 0 ] ; then
if [ -n "`ps -ef | grep -v grep | grep diagmond`" ] ; then # is diag running ?
echo "getting diagnostic information. This may take some minutes "
echo $CSTMCOMMAND |  $STMBIN -c > $TDIR/cstm.info 2>&1
echo "gop cstmpager cat;ru l\nvd\n\nvda\n\n"| $STMBIN -c >$TDIR/memlog.txt
fi
fi #end secure
if [ -f /var/stm/logs/os/log*.raw* ] ; then
echo get latest logs from logtool 
LOGFILE=`ll -rt /var/stm/logs/os/log*.raw* | tail -1 | awk ' { print $9 } ' `
cp $CPOPT $LOGFILE $TDIR/lastlogs.raw
fi
if [ -f /var/stm/logs/os/fpl.log.* ] ; then
echo "writing fpl.log"
copyfiles fpl.log /var/stm/logs/os
fi
if [ -f /var/stm/logs/os/ccerrlog ] ; then
copyfiles ccerrlog /var/stm/logs/os
fi
fi
if [ -f /var/opt/resmon/log/event.log ] ; then
echo "getting EMS event.log file"
copyfiles event.log /var/opt/resmon/log
fi
if [ -f /var/opt/resmon/log/rst.log ] ; then
sizefile /var/opt/resmon/log/rst.log  $MAXFILESIZE   rst.log
fi
grep -e "OnlineDiag" -e ' EMS'  -e Sup-Tool-Mgr -e SFM $TDIR/swlist.txt > \
$TDIR/diaginfo.txt
#get initdata like information
if [ $INITDATA -ge 1 ] ; then
 echo "getting additional diagnostic log data (-diag option is set)"
 if [ -x $STMBIN ] ; then
  echo 'map;gop termwait yes;wait;lsal;wait;uial;wait;lml;wait;exit' | \
  $STMBIN -c  > $TDIR/cstm.addinfo
  echo q | /etc/opt/resmon/lbin/monconfig | grep Version >> $TDIR/initdata
  echo '\n/etc/opt/resmon/lbin/moncheck'
  /etc/opt/resmon/lbin/moncheck > $TDIR/moncheck.out
 fi
 ex_log2 /usr/sbin/psrset psrset.out
 if [ -x /opt/wbem/bin/cimprovider ] ; then
   echo '\n/opt/wbem/bin/cimprovider -l -s' | \
   tee $TDIR/cimprovider.out
   /opt/wbem/bin/cimprovider -l -s >> $TDIR/cimprovider.out
   echo '\n/opt/wbem/bin/cimprovider -lm SFMProviderModule' \
   | tee -a $TDIR/cimprovider.out
   /opt/wbem/bin/cimprovider -lm SFMProviderModule >> \
   $TDIR/cimprovider.out
   if [ -x /opt/sfm/bin/CIMUtil ] ; then
   echo "The following command is executed twice, pausing two mins. between"
   echo "instances, because it may be building its inventory the first time"
   echo "it's executed on the system"
   ex_log2 "/opt/sfm/bin/CIMUtil -e root/cimv2 HPUX_Processor" cimutil_proc.out
   echo '\nsleep 120'
   sleep 120
   ex_log2 "/opt/sfm/bin/CIMUtil -e root/cimv2 HPUX_Processor" cimutil_proc.out
   fi
 fi
 cat $TDIR/config > $TDIR/initdata 
 #check for RAWLOGS:
 RAWFILES="stm/logs/memlog"
 NRAWLOGS=`grep "log.*raw" $TDIR/diaginfo.txt  | wc -l`
 if [$NRAWLOGS -gt 100 ] ; then
 echo "WARNING!!!  $NRAWLOGS raw diagnostics logfiles found in /var/stm/logs/os"
 echo "These logs will be excluded unless -diag optin is given twice !"  
 echo "if the sysinfo.tgz is huge, delete or move some of these files !"
 else
   RAWFILES=stm/logs
 fi
 #make sure that /var/opt/psb is not collected 
 PSBFILES=`ls /var/opt/psb  | grep -v db| awk '{print "opt/psb/" $0}'`
 WBEMFILES="opt/wbem/c* opt/wbem/in* opt/wbem/rep_status \
 opt/wbem/repository opt/wbem/ssl.*"
 if [ $INITDATA -ge 2 ] ; then
    PSBFILES=opt/psb #capture db also if -diag was given twice
    RAWFILES=stm/logs
    WBEMFILES="opt/wbem"
 fi
 tar -cvf $TDIR/diagdata.tar -C /var  opt/hpsmh\
 stm/config/tools/monitor stm/data $RAWFILES opt/sfm $PSBFILES $WBEMFILES \
 opt/sfmdb/pgsql/sfmdb.log -C /etc hosts inetd.conf services opt/resmon/log/. \
  -C $TDIR initdata cstm.addinfo  moncheck.out psrset.out \
 cimutil_proc.out cimprovider.out 
 rm $TDIR/cstm.addinfo $TDIR/moncheck.out  $TDIR/initdata \
 $TDIR/cimutil_proc.out $TDIR/cimprovider.out $TDIR/psrset.out 
 echo "gzip -9 $TDIR/diagdata.tar"
 gzip -9 $TDIR/diagdata.tar
fi
#added for possible U320-Adapter
if [ -x /usr/sbin/mptconfig ] ; then
  for i in /dev/mpt*
  do
   if [ -c $i ] ; then
   ( echo ======== $i =======
   mptutil $i
   mptconfig $i )>> $TDIR/mpt.out
   fi
  done 
fi
#if XP-Diskarray is connected:
if [ $XPINFO -eq 1 ] ; then
 if [ -x /usr/contrib/bin/xpinfo ] ; then
  ex_log /usr/contrib/bin/xpinfo   xpinfo.out
 fi
fi
if [ $secure -eq 0 ] ; then
 ex_log bdf bdf_swapinfo.txt
 ex_log "swapinfo -tam" bdf_swapinfo.txt
 echo $OSVER | grep -q -e "11.23" -e "11.31"
 if [ $? -eq 0 ] ; then
   ex_log2  "/usr/bin/olrad -q" olar.txt
 else
   ex_log2  "/usr/bin/rad -q" olar.txt
 fi
 #if EVA-Diskarray (active - passive mode) is connected:
  ex_log2 "/sbin/spmgr display"  spmgr.out
 #if Diskarray (active - active mode) is connected:
  ex_log2 "/sbin/autopath display" autopath.out
 #if Raid 4SI Interface is installed
  ex_log2 "/sbin/irdiag -v" irdiag.out
 #if raid160 or sa6402 card is installed
 I=`ioscan -fnkd ciss | grep /dev/ciss`
 if [ "Test$I" != "Test" ] ; then
  echo "getting info about SA Raid cards"
  ( echo date: `date`
  echo "ciss devices in ioscan:"
  ioscan -fnkd ciss) >> /$TDIR/sautil.txt
  for J in $I
  do
   ex_log "sautil $J" sautil.txt
   #should work with both SAS and SCSI targets
   disklist=`sautil $J | perl -n -e \
   'if(/(SCSI|SAS\/SATA) DEVICE (\S+:\S+) (\[DISK\] )*-/){ print "$2\n";}'`
   ex_log "sautil $J stat" sautil.txt
   ex_log "sautil $J get_trace_buf" sautil.txt
   ex_log "sautil $J get_fw_err_log -raw" sautil.txt
   for disk in $disklist ; do
     ex_log "sautil $J get_disk_err_log $disk" sautil.txt
   done
  done 

 fi
 ex_log3 /opt/wbem/sbin/wbemassist diaginfo.txt
 ex_log2 "/opt/wbem/sbin/cimconfig -l -c" diaginfo.txt
 grep -q "CIM server is not running" $TDIR/diaginfo.txt
 if [ $? -ne 0 ] ; then #skip cprop if cimserver not running
  ex_log2 "/opt/wbem/sbin/cimconfig -l -p" diaginfo.txt
  ex_log2 "/opt/wbem/bin/cimprovider -l -s" diaginfo.txt
  if [ ! -f $TDIR/cprop.txt ] ; then #may exist from OA and MP IP detection 
    ex_log2 "/opt/propplus/bin/cprop -list" cprop.txt
  fi
  if [ $SWINFO -ge 1 ] ; then 
    ex_log2 "/opt/propplus/bin/cprop -detail -a" cprop.txt
  else
  #capture all except Software related things unless -sw is given
    cat $TDIR/cprop.txt | perl -n -e \
    'if(/^\s.+\|\s(\S.+)/){$x=$1; if($x!~/Software|Process\s|Unknown/) 
    { print STDERR "/opt/propplus/bin/cprop -detail -c \"$1\"\n";
      print `/opt/propplus/bin/cprop -detail -c "$1" 2>&1`;}}' \
    >> $TDIR/cprop.txt 
  fi
  OA_IP=`grep ManagementIPAddress $TDIR/cprop.txt | head -1 | \
     cut -d : -f 2- | sed 's/^ *//;s/ *$//' `
 fi
fi  #end secure
#check for SAS devices
I=`grep /dev/sasd $IOSCAN`
if [ "Test$I" != "Test" ] ; then
echo "getting information about SAS devices "
F=$TDIR/sas.txt
P=`grep escsi_ctlr $IOSCAN | awk '{print " -e "$3}' `
echo "+ ioscan" > $F
grep $P $IOSCAN >> $F
echo "+ ioscan of sas disks" >> $F
grep -i "SAS-" $TDIR/swlist.txt >> $F
RUNSAS=$secure  
#possible MCA check see emr_na-c01639427-1
grep -q  PHKL_37814 $TDIR/swlist.txt 
if [ $? -eq 0 ] ; then
 SASVER=`grep "SAS-SASD" $TDIR/swlist.txt | awk '{print $2}' `
 SASVER=`echo $SASVER | cut -d '.' -f 4`
 if [ $SASVER -lt 812 ] ; then
  (
  echo "\nWARNING !!! Patch PHKL_37814 is installed, but SAS-SASD revision"
  echo is still $SASVER. Please update at least to B.11.23.0812 !
  echo $0 will not run sasmgr unless the SASOPTION is set to 1.
  echo "prevent a potential MCA crash.\n") | tee -a $F
  RUNSAS=$SASOPTION
 fi
fi
if [ $RUNSAS -eq 0 ] ; then
echo "running sasmgr "
(for sas in $I
do
echo #############################################
echo ++ Information for $sas:
cc="sasmgr get_info -D $sas"
echo + $cc
$cc
for i in vpd smp_addr raid "lun=all -q lun_locate" reg=all
do
echo
echo + $cc -q $i
$cc  -q $i
done
for i in phy=all target=all phy_in_port=all
do
echo; echo + $cc -q $i
$cc -q $i
echo + sasmgr get_stat -D $sas -q $i
sasmgr get_stat -D $sas -q $i
done
echo + sasmgr get_stat -D $sas
sasmgr get_stat -D $sas
done) >> $F
fi
echo "getting file /stand/krs/system.krs"
cp $CPOPT /stand/krs/system.krs $TDIR/system.krs
fi
#/var/tombstones
mkdir $TDIR/tombstones
if [ -d /var/tombstones ] ; then
cd /var/tombstones
if [ $? -eq 0 ] ; then
echo getting tombstones from last $MAXBACKDATE days 
ls -l > $TDIR/tombstones/ll.txt
find . -mtime -$MAXBACKDATE -type f  | cpio $CPOPT -vdlmx $TDIR/tombstones
fi
fi
if [ -f $TDIR/efils.txt ] ; then
 grep -i -e efi_ls -e mca -e err $TDIR/efils.txt | \
 perl -n -e "if(/efi_ls -d (\S+)\s*(\S*)/){\$p=\$2.'/'; \$e=\$1; }"\
 -e "if(/(\S+)\s+(\d+\/\s*\d+\/\d+)/){\$fn=\$p.\$1;\$fo=\$2;\$fo=~s/\//\_/g;" \
 -e "\$eo=\$e;\$eo=~s/\/.+\/.+\///g; " \
 -e "\$fo=~s/\s//g;\$fo=\$fn.'.'.\$eo.'.'.\$fo.'.bin';\$fo=~s/(.)\/\$1/_/g;" \
 -e "\$cm=\"efi_cp -d \$e -u \".\$fn.\" $TDIR/tombstones/\".\$fo;" \
 -e " print \$cm,'  '; system(\$cm);}"
 mv $TDIR/efils.txt $TDIR/tombstones/efils.txt
 #check if an MCA happened but no entry is in shutdownlog
 if [ `find . -name mca\* -a -newer /etc/shutdownlog | wc -l` -gt 0 ] ; then
  model | grep -q -e i2 -e i4
  if [ $? -eq 0 ] ; then
    NMVMUNIX=1 
  fi
 fi
fi
if [ $NMVMUNIX -eq 1 ] ; then
 ex_log "/usr/bin/nm -x -v /stand/vmunix" vmunix.nm
 gzip -9 $TDIR/vmunix.nm
fi
if [ $SGINFO -ge 1 -a -f /etc/cmcluster.conf ] ; then
 echo "running external program sginfo "
 if [ -f $SGINFOEXE ] ; then 
   DELLIST="$DELLIST sginfo.log";
   sh $SGINFOEXE -d $TDIR | tee $TDIR/sginfo.log 2>&1
   #determine the output dir of SGINFO
   SGOUT=`find $TDIR -type d | grep .sginfo. | head -1`
   if [ -f $SGOUT.tar.gz ] ; then
      echo removing $SGOUT dir, only keep $SGOUT.tar.gz file
      rm -r $SGOUT
      DELLIST="$DELLIST $SGOUT.tar.gz";
   fi 
 else          
  if [ $SGINFO -gt 1 ] ;then
  WARNING="$WARNING could not find sginfo tool\n"
  WARNING="$WARNING please download sginfo from "
  WARNING="$WARNING ftp://hpcu:Toolbox1@ftp.usa.hp.com/sginfo\n"
  WARNING="$WARNING and place in this directory, or rerun without -sginfo.\n"
  fi
 fi
else #if no -sginfo was set, capture basic SG info
I=service_guard.txt
grep -i serviceguard $TDIR/swlist.txt >> $TDIR/$I
ps -ef | grep -v grep | grep -q cmcld >> $TDIR/$I #Service Guard running ?
if  [ $? -eq 0 ] ; then
  echo "capturing basic Service Guard related information"
  echo "for more detailed service guard info, please use the sginfo tool."
  ex_log2 "/usr/sbin/cmviewcl" $I
  ex_log2 "/usr/sbin/cmviewcl -v" $I
else
   echo "cmcld not running." >> $I  
   mv $TDIR/$I $TDIR/service_guard_off.txt
fi 
fi #end of sginfo section
CRASHDIR=/var/adm/crash
ex_log crashconf crash.txt
if [ -d $CRASHDIR ] ; then
 echo list crash directory
 DUMPSFOUND=0 
 for i in `find $CRASHDIR -name INDEX`
 do
  ex_log "cat $i" crash.txt
  DUMPSFOUND=1
 done
 cd $CRASHDIR
 find . -name crashinfo\*txt -o -name crashinfo\*html -o -name mca* | \
 cpio -pvdlmx $TDIR/tombstones
 ex_log "ll -R $CRASHDIR" crash.txt
 ACTUALDUMPSFOUND=0
 ACTDUMPWARN=14
 for i in `find $CRASHDIR -mtime -$ACTDUMPWARN -name INDEX`
 do
  let ACTUALDUMPSFOUND=$ACTUALDUMPSFOUND+1  #recent dumps found
 done
 if [ $RUNCRASHINFO -eq 0 ] ; then
 if [ $ACTUALDUMPSFOUND -ge 2 ] ; then
WARNING="$WARNING\nNote: there are $ACTUALDUMPSFOUND crash dumps in $CRASHDIR
 <=$ACTDUMPWARN days old.\nUse option -c all to analyze them with crashinfo"
 else 
 if [ $ACTUALDUMPSFOUND -eq 1 ] ; then
  WARNING="$WARNING\nNote: there is a dump in $CRASHDIR
 <=$ACTDUMPWARN days old.\nUse option -c to analyze it with crashinfo"
 fi
 fi
 else #run crashinfo if  RUNCRASHINFO not 0
 if [ $DUMPSFOUND -ge 1 ] ; then
  if [ "X$CRASHINFO" = "X" ] ; then #is crashinfo location defined ?
   CRASHINFOraw=/opt/sfm/tools/crashinfo-a-2.exe
   if [ $SYSTYPE=IA64 ] ; then
    CRASHINFOraw=/opt/sfm/tools/crashinfo-a-i.exe
   fi
   if [ -x $CRASHINFOraw ] ; then
    mkdir $TDIR/crashinfo.tmp
    cd $TDIR/crashinfo.tmp
    $CRASHINFOraw
    CRASHINFO=$TDIR/crashinfo.tmp/crashinfo
    echo "using $CRASHINFO for analyzing available dumps"
    cd $TDIR
   fi
  fi
  if [ "X$CRASHINFO" != "X" ] ; then
   if [ -x $CRASHINFO ] ; then
    # check if a crash is available
    cd $CRASHDIR
    CRLIST=`find . -mtime -$MAXBACKDATE -type d -name "crash.*" |\
             cut -c 3-| grep -E "crash.[0-9]+" | tail -$RUNCRASHINFO`
    for i in $CRLIST
    do
     if [ -f $i/INDEX ] ; then
       echo "$CRASHINFO -H -c $i > $TDIR/crashinfo.$i.html"
       $CRASHINFO -H -c $i > $TDIR/crashinfo.$i.html
     fi
    done
    cd $TDIR
   fi
  fi
  if [ -d "$TDIR/crashinfo.tmp" ] ; then #cleanup
   echo removing temporary crashinfo directory $TDIR/crashinfo.tmp ...
   rm -r "$TDIR/crashinfo.tmp"
   echo done.
  fi
 fi #end DUMPSFOUND -gt 0
 fi #end run crashinfo section
fi
cd $OPDIR 
echo $OSVER | grep -q -e "11.23" -e "11.31"
if [ $? -eq 0 ] ; then #only for these OS versions
if [ -x /opt/sfm/bin/sfmconfig ] ; then # system fault manager
ex_log "/opt/sfm/bin/sfmconfig -w -q" sfmconfig.txt 
if [ -f /var/opt/sfm/log/event.log ] ; then
 cp /var/opt/sfm/log/event.log $TDIR/sfm_event.log
fi
grep -q -e "EMS hardware monitors are enabled" \
	-e "SysFaultMgmt is not" $TDIR/sfmconfig.txt
if [ $? -eq 1  -a $secure -eq 0 ] ; then  #capture sfmlogs
  EVW=/opt/sfm/bin/evweb
  ex_log "$EVW subscribe -L" sfmconfig.txt
  ex_log "$EVW eventviewer -L -x -f" sfmlog.txt
  if [ $MAXBACKDATE -eq 10000 ] ; then # only with -h option
   if [ $NOHIST -eq 0 ] ; then
    echo if the following command makes problems restart $0 with -nohist 
    ex_log "$EVW eventviewer -L -x -f -b history" sfmlog.txt
   fi
  fi
  CPESFM=0 # no CPEs found ?
  if [ -x /opt/sfm/bin/logExtractor ] ; then
  #check if CPE or CMC logs are in sfmlog.txt
  grep -q -e "CPE_" -e "CMC_" $TDIR/sfmlog.txt
  if [ $? -eq 0 -o $MAXBACKDATE -eq 10000 ] ; then  #also if -h option was used
   echo running SFM logExtractor to extract cpe and cmc binaries
   mkdir $TDIR/tombstones/sfm_sal
   /opt/sfm/bin/logExtractor -d $TDIR/tombstones/sfm_sal
   (echo "check sfmlog.txt for details on these SAL binary logs !"
    echo "Files can be analyzed by mca.exe."
   ) >$TDIR/tombstones/sfm_sal/0readme.SALlogs.txt
   CPESFM=`ls -1 $TDIR/tombstones/sfm_sal | wc -l` #number of CPEs
  fi
  #capture details if -f, -h or if logExtractor failed
  if [ $MAXBACKDATE -eq 10000 -o $MAXFILESIZE -eq 0 -o $CPESFM -le 1 ] ; then
   echo "getting event details via evweb"
   perl -p -e 'if(/(evweb logviewer -E -r -i \d+)/)
    {print STDERR "$1\n";print "###$1###\n",`/opt/sfm/bin/$1`,"\n";}' \
    < $TDIR/sfmlog.txt > $TDIR/sfmlog.details.txt
   mv $TDIR/sfmlog.details.txt $TDIR/sfmlog.txt
  fi
fi
fi
fi
fi 
ll -R /opt/sfm /var/adm/syslog /var/opt/psb /var/opt/resmon /var/opt/sfm \
/var/opt/wbem /var/stm >> $TDIR/diaginfo.txt
I=0
while [ $NSYSINFO_ADDCMDS -gt $I ]
do
   X=${SYSINFO_ADDCMD[$I]}
   ex_log "$X" addcmds.log
   let I=$I+1
done
if [ "X$SYSINFO_ADDFILES" != X ] ; then
echo "also collecting: $SYSINFO_ADDFILES" 
for I in $SYSINFO_ADDFILES
 do
  if [ -f $I ] ; then
   X=`echo $I|sed -e "s/\//\_/g"` #from path to filename
   X="addfile_$X";
   sizefile $I $MAXFILESIZE $X 
   DELLIST="$DELLIST $X" 
  else
    echo "Additional File $I not readable"
  fi
 done
fi
#finally make a compressed archive of the information
jn="n"
while [ -f $OUTFILE -a $jn != "y" ];do
echo "overwrite file $OUTFILE ? (y/n)" 1>&2
read jn
if [ $jn != "y" ];then
echo "please enter new full pathname " 1>&2
read OUTFILE
jn="y"
fi
echo $jn
done
echo `date +"%T"` collection completed.
echo "writing system info to $OUTFILE "
cd $TMPDIR #construct to have the directory in the tar
if [ -d $NAME ] ; then
  STARGET=$NAME
else
  cd $TDIR
  STARGET=.
fi
case $tgz in
0)
shar -c -Z -u $STARGET > $OUTFILE ;;
1)
echo "tar -cvf - $STARGET | gzip -9 -c > $OUTFILE"
tar -cvf - $STARGET | gzip -9 -c > $OUTFILE ;;
2)
echo "tar -cvf - $STARGET | gzip -9 -c | uuencode sysinfo.tgz > $OUTFILE"
tar -cvf - $STARGET | gzip -9 -c | uuencode sysinfo.tgz > $OUTFILE ;;
esac
echo cleaning up
cd $TDIR
# for security no  rm -r or rm * !!!
for i in config iosca*.txt dmesg.txt swlist.txt syslog.* cstm.info cprop.txt \
rc.log* lastlogs.raw OLDsyslog* diskinfo.txt fcmsutil.out ccerrlog* \
event?log* rst.log  partition.txt config.lvm shutdownlog irdiag.out sas.txt \
spmgr.out xpinfo.out fpl.log.* memlog.txt machinfo.txt graphinfo.txt nettl.txt \
mpt.out sautil.txt kernelconf.txt Xerrors icod.* ps_top.txt print_manifest.txt \
bootconf.txt crash.txt autopath.out diagdata.tar.gz vxvm.txt sfm* system.krs \
hpvm*.txt lanconfig.txt swagent.log diaginfo.txt sw_inventory.xml mplog* \
show_all.*.txt hpmpl*.??? sd2collect.log escsi_diag.txt vmunix.nm.gz sd2log* \
bdf_swapinfo.txt olar.txt oselogs.tgz gsplog* $DELLIST crashinfo.crash.*.html \
getsysinfo.log service_guard*txt addcmds.log
do  # to avoid errors regarding missing files
  if [ -f "$i" ] ; then
     rm "$i"
  fi
done
for i in tombstones sd2collect
do
if [ -d $i ] ; then
rm -r $i
fi
done
cd $OPDIR
rmdir $TDIR 
echo "sysinfo successfully written to $OUTFILE."
if [ $tgz -eq 1 ] ; then
echo "ATTENTION: $OUTFILE is a binary file."
echo "Transfer it in binary mode via ftp or mail. "
echo "You can use the -u or -sh option to create ascii output.\n"
fi
echo "For more information on getsysinfo.sh please read"
echo $READMELINK
#Virtual Machine reminder
if [ $VMGUEST -eq 1 ] ; then
echo "!!! This is a Virtual Machine Client !!!"
echo "Please do not forget to also capture the sysinfo.tgz from the VM Host"
echo $VMHOST !
fi
#some warnings for Blades:
if [ $BLADEJN -eq 1 -a $SD2 -eq 0 -a $GETOA -eq 0 -a $MPJAVA -eq 0 ] ; then
echo Note: This is a Blade System. 
echo Concider capturing show all information from the OA.
echo $GETSYSINFOVERSION | grep -q -e "s" -e "all"
if [ $? -eq 0 ] ; then  #embedded version
echo "if the OA $OA_IP is reachable via telnet from this host you could run:"
echo "$0 -sd2 -sd2opt \"-h $OA_IP\" $OLDOPTIONS" 
echo "if the OA is only reachable via ssh, run:"
echo "$0 -mp -mpopt \"-ssh -h $OA_IP\" $OLDOPTIONS"
else
echo "if the OA $OA_IP is reachable via telnet from this host you could run:"
echo "$0 -oa  $OLDOPTIONS" 
sleep 2
fi
echo
fi #end blade hint to run show all on OA
echo $WARNING
sleep 1
