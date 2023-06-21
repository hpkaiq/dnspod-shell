#!/bin/sh

export arToken
export arErrCodeUnchanged=0

################################################################### logger ##

# Output log to stderr

arLog() {
    #>&2 echo "$@"
    echo "$@"
}

################################################################### http client ##
arRequest() {

    url="$1"
    data="$2"

    params=""
    agent="AnripDdns/6.4.0(wang@rehiy.com)"

    if type curl >/dev/null 2>&1; then
        if echo $url | grep -q https; then
            params="$params -k"
        fi
        if [ -n "$data" ]; then
            params="$params -d $data"
        fi
        curl -s -A "$agent" $params $url
        return $?
    fi

    if type wget >/dev/null 2>&1; then
        if echo $url | grep -q https; then
            params="$params --no-check-certificate"
        fi
        if [ -n "$data" ]; then
            params="$params --post-data $data"
        fi
        wget -qO- -U "$agent" $params $url
        return $?
    fi

    return 1

}

################################################################### ipv4 util ##
# Get IPv4 by ip route or network

arIp() {
    hostIp=$(awk -F ',' 'NR==2 {print $1}' ${ip_result})
    echo $hostIp
}

################################################################### dnspod api ##

# Dnspod Bridge
# Args: interface data

arDdnsApi() {

    dnsapi="https://dnsapi.cn/${1:?'Info.Version'}"
    params="login_token=$arToken&format=json&lang=en&$2"

    arRequest "$dnsapi" "$params"

}

# Fetch Record Id
# Args: domain subdomain recordType

arDdnsLookup() {
    # Get Record Id
    recordId=$(arDdnsApi "Record.List" "domain=$1&sub_domain=$2&record_type=$3&record_line=$4")
    recordId=$(echo $recordId | sed 's/.*"id":"\([0-9]*\)".*/\1/')

    if ! [ "$recordId" -gt 0 ] 2>/dev/null ;then
        errMsg=$(echo $recordId | sed 's/.*"message":"\([^\"]*\)".*/\1/')
        arLog "> arDdnsLookup - $errMsg"
        return 1
    fi

    echo $recordId
}

# Update Record Value
# Args: domain subdomain recordId recordType [hostIp]

arDdnsUpdate() {
    yys_line=$6

    arLastRecordFile=/run/ardnspod_last_record_"$2"."$1"."$4"."$yys_line"

    # fetch last ip
    lastRecordIp=""
    recordRs=""
    recordCd=""

    if [ -f $arLastRecordFile ]; then
        lastRecordIp=$(cat $arLastRecordFile)
    fi

    # fetch from api
    if [ -z "$lastRecordIp" ]; then
        recordRs=$(arDdnsApi "Record.Info" "domain=$1&record_id=$3")
        recordCd=$(echo $recordRs | sed 's/.*{"code":"\([0-9]*\)".*/\1/')
        lastRecordIp=$(echo $recordRs | sed 's/.*,"value":"\([0-9a-fA-F\.\:]*\)".*/\1/')
    fi

    # update ip
    if [ -z "$5" ]; then
        recordRs=$(arDdnsApi "Record.Ddns" "domain=$1&sub_domain=$2&record_id=$3&record_type=$4&record_line=$yys_line")
    else
        if [ "$5" = "$lastRecordIp" ]; then
            arLog "> arDdnsUpdate - unchanged: $5" # unchanged event
            return $arErrCodeUnchanged
        fi
        recordRs=$(arDdnsApi "Record.Ddns" "domain=$1&sub_domain=$2&record_id=$3&record_type=$4&value=$5&record_line=$yys_line")
    fi

    # parse result
    recordCd=$(echo $recordRs | sed 's/.*{"code":"\([0-9]*\)".*/\1/')
    recordIp=$(echo $recordRs | sed 's/.*,"value":"\([0-9a-fA-F\.\:]*\)".*/\1/')

    # check result
    if [ "$recordCd" != "1" ]; then
        errMsg=$(echo $recordRs | sed 's/.*,"message":"\([^"]*\)".*/\1/')
        arLog "> arDdnsUpdate - error: $errMsg"
        return 1
    else
        arLog "> arDdnsUpdate - updated: $recordIp" # updated event
        if [ -n "$arLastRecordFile" ]; then
            echo $recordIp > $arLastRecordFile
        fi
        return 0
    fi

}

################################################################### task hub ##

# DDNS Check
# Args: domain subdomain [6|4] interface

arDdnsCheck() {
    hostIp=$(arIp)
    if   [ "$4" = "6" ] ; then
        recordType=AAAA
    elif [ "$4" = "4" ] ; then
        recordType=A
    else
        recordType=A
    fi

    arLog "=== Check $2.$1 $recordType $(printf $(echo -n "$3" | sed 's/\\/\\\\/g;s/\(%\)\([0-9a-fA-F][0-9a-fA-F]\)/\\x\2/g'))"

    arLog "Fetching RecordId"
    recordId=$(arDdnsLookup "$1" "$2" "$recordType" "$3")

    errCode=$?
    if [ $errCode -eq 0 ]; then
        arLog "> Record Id: $recordId"
    else
        arLog "$recordId"
        return $errCode
    fi

    arLog "Updating Record value"
    arDdnsUpdate "$1" "$2" "$recordId" "$recordType" "$hostIp" "$3"

}

################################################################### end ##
ip_type="4"
ip_file=ip.txt
ip_result=/opt/cloudflareST/result.csv
yys="联通,移动,电信"

##二级域名
sub="$1"
if [ -z "$sub" ]; then
    echo "请输入二级域名"
    exit 2
fi

##ipv4 ipv6
if [ "$2" = "ipv6" ]; then
    ip_type=6
    ip_file=ipv6.txt
    ip_result=/opt/cloudflareST/result_ipv6.csv
fi

##运营商线路
## 联通 %E8%81%94%E9%80%9A
## 移动 %E7%A7%BB%E5%8A%A8
## 电信 %E7%94%B5%E4%BF%A1
## 默认 %e9%bb%98%e8%ae%a4
if [ -n "$3" ]; then
    yys="$3"
fi

cd /opt/cloudflareST
# https://github.com/XIU2/CloudflareSpeedTest
# 即需要找到 10 个平均延迟低于 300 ms 且下载速度高于 15MB/s 的 IP 才会停止测速

/opt/cloudflareST/CloudflareST -tl 300 -sl 15 -dn 10 -url https://cf.xiu2.xyz/url -f ${ip_file} -o ${ip_result}

# Combine your token ID and token together as follows
arToken="123456,xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

yys_lines=(${yys//,/ })
sub_domains=(${sub//,/ })

# 使用循环遍历数组
for yys_line in "${yys_lines[@]}"
do
    yys_line=$(echo -n "$yys_line" | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
    for sub_domain in "${sub_domains[@]}"
    do
        arDdnsCheck "xxx.com" "$sub_domain" "$yys_line" "${ip_type}"
    done
done
