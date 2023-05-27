#!/bin/sh
#

###################################################################
# AnripDdns v6.4.0
#
# Dynamic DNS using DNSPod API
#
# Author: Rehiy, https://github.com/rehiy
#                https://www.rehiy.com/?s=dnspod
#
# Collaborators: https://github.com/rehiy/dnspod-shell/graphs/contributors
#
# Usage: please refer to `ddnspod.sh`
#
################################################################### params ##

export arToken

# The url to be used for querying public ip address.

export arIp4QueryUrl="http://ipv4.rehi.org/ip"
export arIp6QueryUrl="http://ipv6.rehi.org/ip"

# The temp file to store the last record ip

# The error code to return when a ddns record is not changed
# By default, report unchanged event as success

export arErrCodeUnchanged=0

################################################################### logger ##

# Output log to stderr

arLog() {

    >&2 echo "$@"

}

################################################################### http client ##

# Use curl or wget open url
# Args: url postdata

arRequest() {

    local url="$1"
    local data="$2"

    local params=""
    local agent="AnripDdns/6.4.0(wang@rehiy.com)"

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



# Get IPv4 by ip route or network

arWanIp4() {

    local hostIp
    hostIp=$(awk -F ',' 'NR==2 {print $1}' /opt/cloudflareST/result.csv)
    echo $hostIp

}


################################################################### dnspod api ##

# Dnspod Bridge
# Args: interface data

arDdnsApi() {

    local dnsapi="https://dnsapi.cn/${1:?'Info.Version'}"
    local params="login_token=$arToken&format=json&lang=en&$2"

    arRequest "$dnsapi" "$params"

}

# Fetch Record Id
# Args: domain subdomain recordType

arDdnsLookup() {

    local errMsg
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

    local errMsg

    local recordRs
    local recordCd
    local recordIp

    local lastRecordIp

    yys_line=$6

    arLastRecordFile=/run/ardnspod_last_record_"$2"."$1"."$yys_line"

    if [ -f $arLastRecordFile ]; then
        lastRecordIp=$(cat $arLastRecordFile)
    fi

    # fetch the last record ip from api
    if [ -z "$lastRecordIp" ]; then
        recordRs=$(arDdnsApi "Record.Info" "domain=$1&record_id=$3")
        recordCd=$(echo $recordRs | sed 's/.*{"code":"\([0-9]*\)".*/\1/')
        lastRecordIp=$(echo $recordRs | sed 's/.*,"value":"\([0-9a-fA-F\.\:]*\)".*/\1/')
    fi

    if [ "$5" = "$lastRecordIp" ]; then
        arLog "> arDdnsUpdate - unchanged: $recordIp" # unchanged event
        return $arErrCodeUnchanged
    fi
    recordRs=$(arDdnsApi "Record.Ddns" "domain=$1&sub_domain=$2&record_id=$3&record_type=$4&value=$5&record_line=$yys_line")


    # parse result
    recordCd=$(echo $recordRs | sed 's/.*{"code":"\([0-9]*\)".*/\1/')
    recordIp=$(echo $recordRs | sed 's/.*,"value":"\([0-9a-fA-F\.\:]*\)".*/\1/')

    if [ "$recordCd" != "1" ]; then
        errMsg=$(echo $recordRs | sed 's/.*,"message":"\([^"]*\)".*/\1/')
        arLog "> arDdnsUpdate - error: $errMsg"
        return 1
    elif [ "$recordIp" = "$lastRecordIp" ]; then
        arLog "> arDdnsUpdate - unchanged: $recordIp" # unchanged event
        echo $recordIp
        return $arErrCodeUnchanged
    else
        arLog "> arDdnsUpdate - updated: $recordIp" # updated event
        echo $recordIp > $arLastRecordFile
        echo $recordIp
        return 0
    fi

}

################################################################### task hub ##

# DDNS Check
# Args: domain subdomain [6|4] interface

arDdnsCheck() {

    local errCode

    local hostIp

    local recordType

    arLog "=== Check $2.$1 $(printf $(echo -n "$3" | sed 's/\\/\\\\/g;s/\(%\)\([0-9a-fA-F][0-9a-fA-F]\)/\\x\2/g')) line==="
    arLog "Fetching Host Ip"


    recordType=A
    hostIp=$(arWanIp4)


    errCode=$?
    if [ $errCode -eq 0 ]; then
        arLog "> Host Ip: $hostIp"
        arLog "> Record Type: $recordType"
    elif [ $errCode -eq 2 ]; then
        arLog "> Host Ip: Auto"
        arLog "> Record Type: $recordType"
    else
        arLog "$hostIp"
        return $errCode
    fi

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

cd /opt/cloudflareST
# https://github.com/XIU2/CloudflareSpeedTest
# 即需要找到 10 个平均延迟低于 300 ms 且下载速度高于 15MB/s 的 IP 才会停止测速
/opt/cloudflareST/CloudflareST -tl 300 -sl 15 -dn 10 -url https://cf.xiu2.xyz/url -o /opt/cloudflareST/result.csv     

# Combine your token ID and token together as follows
arToken="12345,xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Web endpoint to be used for querying the public IPv6 address
# Set this to override the default url provided by ardnspod
# arIp4QueryUrl="http://ipv4.rehi.org/ip"
# arIp6QueryUrl="http://ipv6.rehi.org/ip"

# Return code when the last record IP is same as current host IP
# Set this to a value other than 0 to distinguish with a successful ddns update
# arErrCodeUnchanged=0

# Place each domain you want to check as follows
# you can have multiple arDdnsCheck blocks

## 联通 %E8%81%94%E9%80%9A
## 移动 %E7%A7%BB%E5%8A%A8
## 电信 %E7%94%B5%E4%BF%A1
yys_lines=("%E8%81%94%E9%80%9A" "%E7%A7%BB%E5%8A%A8" "%E7%94%B5%E4%BF%A1")
# 使用循环遍历数组
for yys_line in "${yys_lines[@]}"
do
    arDdnsCheck "xx.yy" "sub1" "$yys_line"
    arDdnsCheck "xx.yy" "sub2" "$yys_line"
done

