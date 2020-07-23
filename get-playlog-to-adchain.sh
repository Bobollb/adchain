#!/bin/bash
source /etc/profile

pwd=/root/develop/bitcoin

step=2
playLogId=`cat ${pwd}/index.dat` 

while true
do
	playlog=`curl -s http://14.116.192.182:8088/playlog/test?playLogId=${playLogId}` 
	echo $playlog >> ${pwd}/playlogdata.txt
	echo $playlog > ${pwd}/playlog.txt

	# 上链
	${pwd}/playlogtest.sh >> ${pwd}/adchainlog.log 2>&1
	
    echo ${playLogId} > ${pwd}/index.dat   	
	playLogId=`expr ${playLogId} + 1`
	
	sleep $step
done
exit 0
