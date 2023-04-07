#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "注意: 请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "目前暂不支持你的VPS的操作系统！" && exit 1

if [[ -z $(type -P curl) ]]; then
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl
fi

archAffix(){
    case "$(uname -m)" in
        x86_64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        s390x ) echo 's390x' ;;
        * ) red "不支持的CPU架构!" && exit 1 ;;
    esac
}

installProxy(){
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl wget sudo qrencode

    rm -f /usr/bin/caddy
    wget https://raw.githubusercontent.com/Misaka-blog/naiveproxy-script/main/files/caddy-linux-$(archAffix) -O /usr/bin/caddy
    chmod +x /usr/bin/caddy

    mkdir /etc/caddy
    
    read -rp "请输入需要用在NaiveProxy的端口 [回车随机分配端口]：" proxyport
    [[ -z $proxyport ]] && proxyport=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$proxyport") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$proxyport") ]]; then
            echo -e "${RED} $proxyport ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
            read -rp "请输入需要用在NaiveProxy的端口 [回车随机分配端口]：" proxyport
            [[ -z $proxyport ]] && proxyport=$(shuf -i 2000-65535 -n 1)
        fi
    done
    read -rp "请输入需要用在Caddy监听的端口 [回车随机分配端口]：" proxyport
    [[ -z $proxyport ]] && proxyport=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$proxyport") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$proxyport") ]]; then
            echo -e "${RED} $proxyport ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
            read -rp "请输入需要用在Caddy监听的端口 [回车随机分配端口]：" proxyport
            [[ -z $proxyport ]] && proxyport=$(shuf -i 2000-65535 -n 1)
        fi
    done
    yellow "将在NaiveProxy使用的端口是：$proxyport"
    read -rp "请输入需要使用在NaiveProxy的域名：" domain
    read -rp "请输入NaiveProxy的用户名 [回车随机生成]：" proxyname
    [[ -z $proxyname ]] && proxyname=$(date +%s%N | md5sum | cut -c 1-16)
    read -rp "请输入NaiveProxy的密码 [回车随机生成]：" proxypwd
    [[ -z $proxypwd ]] && proxypwd=$(date +%s%N | md5sum | cut -c 1-16)
    read -rp "请输入NaiveProxy的伪装网站地址 （去除https://） [回车世嘉maimai日本网站]：" proxysite
    [[ -z $proxysite ]] && proxysite="maimai.sega.jp"
    
    cat << EOF >/etc/caddy/Caddyfile
{
http_port $caddyport
}
:$proxyport, $domain
tls admin@seewo.com
route {
 forward_proxy {
   basic_auth $proxyname $proxypwd
   hide_ip
   hide_via
   probe_resistance
  }
 reverse_proxy  https://$proxysite  {
   header_up  Host  {upstream_hostport}
   header_up  X-Forwarded-Host  {host}
  }
}
EOF
    mkdir /root/naive
    cat <<EOF > /root/naive/naive-client.json
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://${proxyname}:${proxypwd}@${domain}:${proxyport}",
  "log": ""
}
EOF
    url="naive+https://${proxyname}:${proxypwd}@${domain}:${proxyport}?padding=true#Naive"
    echo $url > /root/naive/naive-url.txt
    
    cat << EOF >/etc/systemd/system/caddy.service
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
User=root
Group=root
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable caddy
    systemctl start caddy

    green "NaiveProxy 已安装成功！"
    yellow "客户端配置文件已保存至 /root/naive/naive-client.json"
    yellow "Qv2ray / SagerNet / Matsuri 分享链接已保存至 /root/naive/naive-url.txt"
    yellow "SagerNet / Matsuri 分享二维码如下："
    qrencode -o - -t ANSIUTF8 "$url"
}

uninstallProxy(){
    systemctl stop caddy
    rm -rf /etc/caddy
    rm -f /usr/bin/caddy /root/naive-client.json
    green "NaiveProxy 已彻底卸载成功！"
}

startProxy(){
    systemctl enable caddy
    systemctl start caddy
    green "NaiveProxy 已启动成功！"
}

stopProxy(){
    systemctl disable caddy
    systemctl stop caddy
    green "NaiveProxy 已停止成功！"
}

reloadProxy(){
    systemctl restart caddy
    green "NaiveProxy 已重启成功！"
}

changeport(){
    oldport=$(cat /etc/caddy/Caddyfile | sed -n 4p | awk '{print $1}' | sed "s/://g" | sed "s/,//g")
    read -rp "请输入需要用在NaiveProxy的端口 [回车随机分配端口]：" proxyport
    [[ -z $proxyport ]] && proxyport=$(shuf -i 2000-65535 -n 1)
    
    until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$proxyport") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$proxyport") ]]; then
            echo -e "${RED} $proxyport ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
            read -rp "请输入需要用在NaiveProxy的端口 [回车随机分配端口]：" proxyport
            [[ -z $proxyport ]] && proxyport=$(shuf -i 2000-65535 -n 1)
        fi
    done

    sed -i "s#$oldport#$proxyport#g" /etc/caddy/Caddyfile
    sed -i "s#$oldport#$proxyport#g" /root/naive/naive-client.json
    sed -i "s#$oldport#$proxyport#g" /root/naive/naive-url.txt
    reloadProxy
}


changedomain(){
    olddomain=$(cat /etc/caddy/Caddyfile | sed -n 4p | awk '{print $2}')
    read -rp "请输入需要使用在NaiveProxy的域名：" domain

    sed -i "s#$olddomain#$domain#g" /etc/caddy/Caddyfile
    sed -i "s#$olddomain#$domain#g" /root/naive/naive-client.json
    sed -i "s#$olddomain#$domain#g" /root/naive/naive-url.txt
    reloadProxy
}

changeusername(){
    oldproxyname=$(cat /etc/caddy/Caddyfile | grep "basic_auth" | awk '{print $2}')
    read -rp "请输入NaiveProxy的用户名 [回车随机生成]：" proxyname
    [[ -z $proxyname ]] && proxyname=$(date +%s%N | md5sum | cut -c 1-16)

    sed -i "s#$oldproxyname#$proxyname#g" /etc/caddy/Caddyfile
    sed -i "s#$oldproxyname#$proxyname#g" /root/naive/naive-client.json
    sed -i "s#$oldproxyname#$proxyname#g" /root/naive/naive-url.txt
    reloadProxy
}

changepassword(){
    oldproxypwd=$(cat /etc/caddy/Caddyfile | grep "basic_auth" | awk '{print $3}')
    read -rp "请输入NaiveProxy的密码 [回车随机生成]：" proxypwd
    [[ -z $proxypwd ]] && proxypwd=$(date +%s%N | md5sum | cut -c 1-16)

    sed -i "s#$oldproxypwd#$proxypwd#g" /etc/caddy/Caddyfile
    sed -i "s#$oldproxypwd#$proxypwd#g" /root/naive/naive-client.json
    sed -i "s#$oldproxypwd#$proxypwd#g" /root/naive/naive-url.txt
    reloadProxy
}

changeproxysite(){
    oldproxysite=$(cat /etc/caddy/Caddyfile | grep "reverse_proxy" | awk '{print $2}' | sed "s/https:\/\///g")
    read -rp "请输入NaiveProxy的伪装网站地址 （去除https://） [回车世嘉maimai日本网站]：" proxysite
    [[ -z $proxysite ]] && proxysite="maimai.sega.jp"

    sed -i "s#$oldproxysite#$proxysite#g" /etc/caddy/Caddyfile
    reloadProxy
}

modifyConfig(){
    green "NaiveProxy 配置变更选择如下:"
    echo -e " ${GREEN}1.${PLAIN} 修改端口"
    echo -e " ${GREEN}2.${PLAIN} 修改域名"
    echo -e " ${GREEN}3.${PLAIN} 修改用户名"
    echo -e " ${GREEN}4.${PLAIN} 修改密码"
    echo -e " ${GREEN}5.${PLAIN} 修改伪装站地址"
    echo ""
    read -p " 请选择操作[1-5]：" confAnswer
    case $confAnswer in
        1 ) changeport ;;
        2 ) changedomain ;;
        3 ) changeusername ;;
        4 ) changepassword ;;
        5 ) changeproxysite ;;
        * ) exit 1 ;;
    esac
}

menu(){
    clear
    echo "#############################################################"
    echo -e "#                  ${RED}NaiveProxy  一键配置脚本${PLAIN}                 #"
    echo -e "# ${GREEN}作者${PLAIN}: MisakaNo の 小破站                                  #"
    echo -e "# ${GREEN}博客${PLAIN}: https://blog.misaka.rest                            #"
    echo -e "# ${GREEN}GitHub 项目${PLAIN}: https://github.com/Misaka-blog               #"
    echo -e "# ${GREEN}GitLab 项目${PLAIN}: https://gitlab.com/Misaka-blog               #"
    echo -e "# ${GREEN}Telegram 频道${PLAIN}: https://t.me/misakanocchannel              #"
    echo -e "# ${GREEN}Telegram 群组${PLAIN}: https://t.me/misakanoc                     #"
    echo -e "# ${GREEN}YouTube 频道${PLAIN}: https://www.youtube.com/@misaka-blog        #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 安装 NaiveProxy"
    echo -e " ${GREEN}2.${PLAIN} ${RED}卸载 NaiveProxy${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} 启动 NaiveProxy"
    echo -e " ${GREEN}4.${PLAIN} 停止 NaiveProxy"
    echo -e " ${GREEN}5.${PLAIN} 重载 NaiveProxy"
    echo " -------------"
    echo -e " ${GREEN}6.${PLAIN} 修改 NaiveProxy 配置"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} 退出"
    echo ""
    read -rp " 请输入选项 [0-6] ：" answer
    case $answer in
        1) installProxy ;;
        2) uninstallProxy ;;
        3) startProxy ;;
        4) stopProxy ;;
        5) reloadProxy ;;
        6) modifyConfig ;;
        *) red "请输入正确的选项 [0-6]！" && exit 1 ;;
    esac
}

menu
