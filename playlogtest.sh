#!/bin/sh


#----------------------- 命名原则与解释 -----------------------#
# 本脚本命名词缀与名称对应： 
# 1.总地址       --> boss       
# 2.广告屏(终端) --> terminal
# 3.广告         --> ad         (缩写)
# 4.地址         --> addr       (缩写)


# ---------------------- 目录 ----------------------#
# 测试目录是 /root/develop/bitcoin
pwd=`pwd`


# ----------------------- 读取配置参数 -----------------------#
# 配置文件adchain.conf
# 1. 总地址(BossAddr)
# 2. 总地址最低余额(BossMinBalance)
# 3. 广告屏拥有的最低余额(terminalMinBalance)
# 4. 总地址给广告屏单次转账(singleTransferMoneyFromBossToTerminal)
bossAddr=`cat ${pwd}/adchain.conf | jq '.bossAddr' | sed 's/\"//g'`
bossMinBalance=`cat ${pwd}/adchain.conf | jq '.bossMinBalance' | sed 's/\"//g'`
terminalMinBalance=`cat ${pwd}/adchain.conf | jq '.terminalMinBalance' | sed 's/\"//g'`
singleTransferMoneyFromBossToTerminal=`cat ${pwd}/adchain.conf | jq '.singleTransferMoneyFromBossToTerminal' | sed 's/\"//g'`
singleTransferMoneyFromTerminalToAd=0.01
myFee=0.01
# ----------------------- 读取配置完成 -----------------------#


# ----------------------- 函数区 -----------------------#


# 检查总地址的金额情况，不足则补充
# 参数 : 无
# 返回值 : 0   ---  没找到总地址
#          1   ---  最后一次加了钱，不一定充足，大概率充足
#          2   ---  钱确定充足
checkBossAddrBalance()
{
	# 总地址余额
	bossBalance=-1
	
	# 查listaddressgroupings
	listaddressgroupings=`bitcoin-cli -regtest listaddressgroupings`
	
	# while 查总地址的余额。
	index=0
	while true
	do
		label=`echo ${listaddressgroupings} | jq '.['${index}'] | .[0] | .[2]' | sed 's/\"//g'`
		# echo "${index}:${label}"
		if [ "${label}" = "boss" ]
		then  
			bossBalance=`echo ${listaddressgroupings} | jq '.['${index}'] | .[0] | .[1]'`
			echo "找到boss了,还剩下了${bossBalance}"
			break
		fi
		index=`expr $index + 1`
	done

	# 异常处理，没有找到总地址的情况,则bossBanlance=-1
	if [ `expr ${bossBalance} \< 0` -eq 1 ];
	then 
		echo "地址集中没有总地址，请使用getnewaddress获取并写入adchain.conf中"
		return 0
	fi
	
	# 判断boss的金额是否大于限定的最低余额
	if [  `echo "$bossBalance < $bossMinBalance" | bc` -eq 1 ];then 
		echo "boss余额不足 ${bossMinBalance},即将生成块，并给钱"
		bitcoin-cli -regtest generatetoaddress 1 ${bossAddr}
		return 1
	else
		echo "金额充足"
		return 2
	fi 
}

# Boss转账给终端广告屏的转账函数
# 参数 1. terminalAddr    -----  终端地址
#      2. bossAddr        -----  总地址
# 返回值： 无
transferFromBosstoTerminal()
{
	local terminalAddr=$1
	local bossAddr=$2
	echo "总地址即将开始转钱给广告屏"
	
	local listunspent=`bitcoin-cli -regtest listunspent 1 9999999 "[\"${bossAddr}\"]" | jq '.'`
	# echo listunspent=$listunspent
	
	local index=0
	local unspent=0
	while true
	do
		# 这里是所有的unspent都不符合条件的情况，这里先暂时不做处理
		# 我的思路是可以用一个类似垃圾回收的机制，来聚拢余额到一个vout
		if [ "$unspent" = "null" ]
		then
			echo 所有的unspent都不符合条件！！！可暂时先调整参数！！！
			break
		fi
		
		# 正常的情况，找合适大小的unspent
		unspent=`echo ${listunspent} | jq '.['${index}'].amount'`
		moneyAndFee=`echo "$singleTransferMoneyFromBossToTerminal + $myFee" | bc`
		if [  `echo "$unspent >= $moneyAndFee" | bc` -eq 1 ]
		then
			echo "$index : $unspent金额大小足够，可以给广告屏转"
			txid=`bitcoin-cli -regtest listunspent 1 9999999 "[\"${bossAddr}\"]" | jq '.['${index}'].txid'`
			echo txid=$txid
			vout=`bitcoin-cli -regtest listunspent 1 9999999 "[\"${bossAddr}\"]" | jq '.['${index}'].vout'`
			echo vout=$vout
			amount=`bitcoin-cli -regtest listunspent 1 9999999 "[\"${bossAddr}\"]" | jq '.['${index}'].amount'`
			echo amount=$amount #余额
			
			# 计算找零
			rechange=`echo "$amount - $moneyAndFee" | bc -l`
			# bc 计算器的结果是0.xxxx时，不显示前面的0，所以必须补上不然报错
			flag=`echo "$rechange < 1" | bc`
			if [ $flag -eq "1" ]
			then
				echo "rechange小于0"
				rechange=`echo "0$rechange"`
			fi
			echo rechange=$rechange
			if [ "$rechange" = "00" ]
			then
				echo "rechange等于0"
				rawtransactionHex=`bitcoin-cli -regtest createrawtransaction "[{\"txid\":${txid},\"vout\":${vout}}]" "[{\"${terminalAddr}\":${singleTransferMoneyFromBossToTerminal}}]"`
			else
				rawtransactionHex=`bitcoin-cli -regtest createrawtransaction "[{\"txid\":${txid},\"vout\":${vout}}]" "[{\"${terminalAddr}\":${singleTransferMoneyFromBossToTerminal}},{\"${bossAddr}\":${rechange}}]"`	
			fi

			#rawtransactionHex=`bitcoin-cli -regtest createrawtransaction "[{\"txid\":${txid},\"vout\":${vout}}]" "[{\"${terminalAddr}\":${singleTransferMoneyFromBossToTerminal}},{\"${bossAddr}\":${rechange}}]"`
			echo rawtransactionHex=$rawtransactionHex
			key=`bitcoin-cli -regtest dumpprivkey ${bossAddr}`
			echo key=$key
			signrawtransactionHex=`bitcoin-cli -regtest signrawtransactionwithkey "${rawtransactionHex}" "[\"${key}\"]" | grep "hex" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g'`
			echo signrawtransactionHex=$signrawtransactionHex
			rawtransactionTxid=`bitcoin-cli -regtest sendrawtransaction ${signrawtransactionHex}`
			echo rawtransactionTxid=$rawtransactionTxid
			bitcoin-cli -regtest generatetoaddress 1 ${bossAddr}
			break
		fi
		index=`expr $index + 1`
	done	
}



# 总地址转账函数: 确保总地址余额的够，以及给广告屏转账
# 参数： 1. add1是广告屏地址 
# 		 2. add2是总地址
# 返回值: 无
transferFromBoss()
{
	# add1是广告屏地址 add2是总地址
	local add1=$1
	local add2=$2
	
	
	# 先确保boss有钱
	checkBossAddrBalance
	while [ $? -ne 2 ]
	do 
		checkBossAddrBalance
	done

	# 到这里Boss肯定有大于最小限额的钱转账给广告屏
	transferFromBosstoTerminal $add1 $add2
}


# 广告屏对广告转账函数
# 参数： 1. add1是广告地址
# 		 2. add2是广告屏地址
# 返回值: 无
transfer()
{
	# add1是广告地址，addd2是广告屏地址
	local add1=$1
	local add2=$2

	local listunspent=`bitcoin-cli -regtest listunspent 1 9999999 "[\"${add2}\"]" | jq '.'`
	# echo listunspent=$listunspent
	
	local moneyAndFeeToAd=`echo "$singleTransferMoneyFromTerminalToAd + $myFee" | bc`
	
	local index=0
	local unspent=0
	
	# 循环遍历检查是否有合适的unspent
	while true
	do
		# 这里是所有的unspent都不符合条件的情况。
		# 即没有unspent有足够的钱，只能请求总地址来转钱
		if [ "$unspent" = "null" ]
		then
			echo 所有的unspent都不符合条件！应调用BOSS转账
			transferFromBoss ${add2} ${bossAddr}
			break;
		fi
		
		# 正常的情况，找合适大小的unspent
		unspent=`bitcoin-cli -regtest listunspent 1 9999999 "[\"${add2}\"]" | jq '.['${index}'].amount'`
		if [ `echo "$unspent >= $moneyAndFeeToAd" | bc` -eq 1 ]
		then
			echo "存在合适的unspent"
			break;
		fi
		index=`expr $index + 1`
	done	
	
	
	# 这时候要么BOSS转了钱，要么有合适的unspent
	index=0
	unspent=0
	while true
	do
		# 这里理论上不可能发生
		if [ "$unspent" = "null" ]
		then
			echo "查了一圈没查到"
			index=0
			#break
		fi
		
		# 正常的情况，找合适大小的unspent
		unspent=`bitcoin-cli -regtest listunspent 1 9999999 "[\"${add2}\"]" | jq '.['${index}'].amount'`
		
		if [ `echo "$unspent >= $moneyAndFeeToAd" | bc` -eq 1 ]
		then
			echo "index：$index , unspent: $unspent  -> 金额大小足够，可以给广告转"
			txid=`bitcoin-cli -regtest listunspent 1 9999999 "[\"${add2}\"]" | jq '.['${index}'].txid'`
			echo txid=$txid
			vout=`bitcoin-cli -regtest listunspent 1 9999999 "[\"${add2}\"]" | jq '.['${index}'].vout'`
			echo vout=$vout
			amount=`bitcoin-cli -regtest listunspent 1 9999999 "[\"${add2}\"]" | jq '.['${index}'].amount'`
			echo amount=$amount #余额
		
			# 计算找零，只有两种可能，有找零和没找零
			rechange=`echo "$amount - $moneyAndFeeToAd" | bc -l`
			
			# bc 计算器的结果是0.xxxx时，不显示前面的0，所以必须补上不然报错
			flag=`echo "$rechange < 1" | bc`
			if [ $flag -eq "1" ]
			then
				echo "rechange小于0"
				rechange=`echo "0$rechange"`
			fi
			echo rechange=$rechange
			# 找零为0的情况
			if [ "$rechange" = "00" ]
			then
				echo "rechange等于0"
				rawtransactionHex=`bitcoin-cli -regtest createrawtransaction "[{\"txid\":${txid},\"vout\":${vout}}]" "[{\"${add1}\":${singleTransferMoneyFromTerminalToAd}}]"`
			else
				rawtransactionHex=`bitcoin-cli -regtest createrawtransaction "[{\"txid\":${txid},\"vout\":${vout}}]" "[{\"${add1}\":${singleTransferMoneyFromTerminalToAd}},{\"${add2}\":${rechange}}]"`	
			fi
			
			echo rawtransactionHex=$rawtransactionHex
			key=`bitcoin-cli -regtest dumpprivkey ${add2}`
			echo key=$key
			signrawtransactionHex=`bitcoin-cli -regtest signrawtransactionwithkey "${rawtransactionHex}" "[\"${key}\"]" | grep "hex" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g'`
			echo signrawtransactionHex=$signrawtransactionHex
			rawtransactionTxid=`bitcoin-cli -regtest sendrawtransaction ${signrawtransactionHex}`
			echo rawtransactionTxid=$rawtransactionTxid
			bitcoin-cli -regtest generatetoaddress 1 ${bossAddr}
			break
		fi
		index=`expr $index + 1`
	done	
}
# ----------------------- 函数区结束 -----------------------#



# ----------------------- 脚本主运行区 ---------------------#
# 行处理日志
cat ${pwd}/playlog.txt | while read line
do
	echo 
	echo ----------------------------开始处理一条日志------------------------------------
	# 生成终端对应的addr 
	
	# 该日志的ID
	playlogid=`echo ${line} | jq '.playLogId' | sed 's/\"//g'`
	echo "当前日志编号:${playlogid}"

	# 获取日志每一条记录的终端名字
	terminal=`echo ${line} | jq '.terminalName' | sed 's/\"//g'`
	#echo $terminal

	# 判断文件中是否存在有这个终端
	checkterminal=`cat ${pwd}/terminal.dat | grep -w ${terminal}`
	if  test  -z "${checkterminal}"
	then 
		echo '终端不存在，即将创建新地址对应'
		newterminaladdr=`bitcoin-cli -regtest getnewaddress ${terminal}`
		# 这里要生成块奖励，不然这个地址是没有币的
		#bitcoin-cli -regtest generatetoaddress 101 ${newterminaladdr}
		echo '{"terminal":"'${terminal}'","addr":"'${newterminaladdr}'"}'>>${pwd}/terminal.dat
		
        terminaladdr=${newterminaladdr}
		echo ${newterminaladdr}
	else 
		terminaladdr=`echo ${checkterminal} | jq '.addr' | sed 's/\"//g'`
		
		echo '终端已存在，不会再生成地址,终端地址为'
		echo ${terminaladdr}
	fi


	# 为每一个广告生成地址
	adId=`echo ${line} | jq '.fileId' | sed 's/\"//g'`

	# 判断文件中是否存在有这个广告
	checkad=`cat ${pwd}/ad.dat | grep -w ${adId}`
	if  test  -z "${checkad}"
	then 
		echo '广告不存在，即将创建新地址对应'
		newadaddr=`bitcoin-cli -regtest getnewaddress ${adId}`
		echo '{"adId":"'${adId}'","addr":"'${newadaddr}'"}'>>${pwd}/ad.dat
		
		adaddr=${newadaddr}
		echo ${newadaddr}
	else 
		adaddr=`echo ${checkad} | jq '.addr' | sed 's/\"//g'`
		
		echo '广告已存在，不会再生成地址,广告地址为'
		echo ${adaddr}
	fi


	# terminaladdr是终端地址，即广告屏映射的地址
	# adaddr是广告地址，即广告映射的地址
	echo 日志地址提取结果:
	echo terminaladdr=${terminaladdr}
	echo adaddr=${adaddr}

	# 现在我们获取了该条日志的广告地址和终端地址
	# 现在只需要 adaddr + terminaladdr 再调用一个转账函数完成转账即可
	echo 下面开始转账上链:
	transfer ${adaddr} ${terminaladdr}
	
	echo ----------------------------结束处理一条日志------------------------------------
	echo 
done
# ----------------------- 脚本主运行区结束 ---------------------#



