#!/bin/bash
set -e
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq curl unzip >/dev/null 2>&1
curl -fsSL -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36' -e 'https://developer.huawei.com/' -o clt.zip 'https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_package_901_9/de/v3/kICkkkAeThGTxoJ0yD55vA/commandline-tools-linux-x64-26.0.0.851.zip?HW-CC-KV=V1&HW-CC-Date=20261008T224128Z&HW-CC-Expire=315360000&HW-CC-Sign=D79C52B0D96FD1D57EFB93061EC69A026AE031EE98B85BBE00B54E7B82C3309A'
unzip -q clt.zip
export DEVECO_SDK_HOME=$PWD/command-line-tools/sdk
export PATH=$PWD/command-line-tools/bin:$PWD/command-line-tools/tool/node/bin:$PATH
ohpm config set strict_ssl false
ohpm config set registry https://ohpm.openharmony.cn/ohpm/
npm config set strict-ssl false
npm config set registry=https://repo.huaweicloud.com/repository/npm/
npm config set @ohos:registry=https://repo.harmonyos.com/npm/
ohpm install
hvigorw assembleHap --mode module -p product=default -p debuggable=true --no-daemon
ls -la entry/build/default/outputs/default/