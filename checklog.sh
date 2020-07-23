pwd=`pwd`

#判断playlog中是否存在上链交易
isExist(){
	labelA=$1
	labelB=$2

	k=0
	cat ${pwd}/playlogdata.txt | while read line
	do
		#echo ${line}
		k=`expr $k + 1`
		terminalName=`echo $line | jq '.terminalName' | sed 's/"//g'`
		fileId=`echo $line | jq '.fileId' | sed 's/"//g'`
		#terminalName=`echo $line | grep "terminalName" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g'`
		#fileId=`echo $line | grep "fileId" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g'`
		echo terminalName=$terminalName
		echo fileId=$fileId

		if [[ $terminalName = $labelA && $fileId = $labelB ]] || [[ $terminalName = $labelB && $fileId = $labelA ]]; then
			echo find success!! $labelA 与 $labelB 之间转账
			return 1
		else
			echo find fail!!
			return 2
		fi
	done
}


blockCount=`bitcoin-cli -regtest getblockcount`
logCount=0 #日志条数
#遍历每个块
for (( i = 102; i <= ${blockCount}; i++ )); do
	blockHash=`bitcoin-cli -regtest getblockhash $i`
	blockInfo=`bitcoin-cli -regtest getblock $blockHash`
	nTx=`echo $blockInfo | jq '.nTx'`
	txArray=`echo $blockInfo | jq '.tx'`

	echo 第 $i 块中交易数：$nTx
	#遍历块中所有交易,获取交易双方label
	for (( j = 0; j < ${nTx}; j++ )); do
		tx=`echo ${txArray} | jq '.['${j}']' | sed 's/\"//g'`
		transactionInfo=`bitcoin-cli -regtest gettransaction $tx`
		details=`echo $transactionInfo | jq '.details'`
		echo 交易 $j 详细信息：$details
		category=`echo $details | jq '.[0]' | grep "category" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g'`
		#如果category是immature 则该交易非日志上链交易
		if [[ $category = "immature" ]]; then
			echo category is immature
		else
			#获取广告屏和广告的label
			index=1
			label=`echo $details | jq '.[0]' | grep "label" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g'`
			labelA=$label
			labelB=""
			echo labelA=$labelA
			while true
			do
				label=`echo $details | jq '.['${index}']' | grep "label" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g'`
				echo chaxun==$label
				if [[ $label = "" ]]; then
					echo label---null
					break
				fi
				#查到第二个label
				if [[ "$label" != "$labelA" ]]; then
					labelB=$label
					break
				fi
				index=`expr $index + 1`
			done
			
			echo labelA=$labelA
			echo labelB=$labelB

			if [[ $labelA = "boss" || $labelB = "boss" ]]; then
				echo 该交易为boss给终端转账
				continue
			fi

			logCount=`expr $logCount + 1`
			isExist $labelA $labelB
			if [[ $? -ne 1 ]]; then
				echo find fail:日志中不存在该交易 $tx
			fi
			
		fi
	done
done

echo 交易数：$logCount
