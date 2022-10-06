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

installGolang(){
    wget -N https://go.dev/dl/$(curl https://go.dev/VERSION?m=text).linux-$(archAffix).tar.gz
    tar -xf go*.linux-$(archAffix).tar.gz -C /usr/local/
    export PATH=$PATH:/usr/local/go/bin
    rm -f go*.linux-$(archAffix).tar.gz
}

buildCaddy(){
    go env -w GO111MODULE=on
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
    ~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive
    rm -rf go
    mv ./caddy /opt/naiveproxy/caddy
}

makeconfig(){
    read -rp "请输入需要用在NaiveProxy的域名：" domain

    read -rp "请输入NaiveProxy的用户名 [默认随机生成]：" proxyname
    [[ -z $proxyname ]] && proxyname=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "请输入NaiveProxy的密码 [默认随机生成]：" proxypwd
    [[ -z $proxypwd ]] && proxypwd=$(cat /proc/sys/kernel/random/uuid)

    yellow "正在写入配置文件，请稍等..."
    sleep 2
    cat > /opt/naiveproxy/Caddyfile <<EOF
:443, $domain
tls example@example.com
route {
 forward_proxy {
   basic_auth $proxyname $proxypwd
   hide_ip
   hide_via
   probe_resistance
  }
 reverse_proxy  https://demo.cloudreve.org  {
   header_up  Host  {upstream_hostport}
   header_up  X-Forwarded-Host  {host}
  }
}
EOF

    cat <<'TEXT' > /etc/systemd/system/naiveproxy.service
[Unit]
Description=Naiveproxy server, script by Misaka-blog
After=network.target
[Install]
WantedBy=multi-user.target
[Service]
Type=simple
WorkingDirectory=/root
ExecStart=/opt/naiveproxy/caddy run
Restart=always
TEXT

cat > /root/naive-client.json <<EOF
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://${proxyname}:${proxypwd}@${domain}",
  "log": ""
}
EOF
    qvurl="naive+https://${proxyname}:${proxypwd}@${domain}:443?padding=false#Naive"
    echo $qvurl > /root/naive-qvurl.txt
}

installProxy(){
    if [[ -z $(type -P go) ]]; then
        installGolang
    fi
    buildCaddy
    makeconfig
    systemctl start naiveproxy
    systemctl enable naiveproxy
    green "NaiveProxy 已安装成功！"
    yellow "客户端配置文件已保存至 /root/naive-client.json"
    yellow "Qv2ray 分享连接如下，并已保存至 /root/naive-qvurl.txt"
    green "${qvurl}"
}

uninstallProxy(){
    systemctl stop naiveproxy
    systemctl disable naiveproxy
    rm -f /opt/naiveproxy/caddy /etc/systemd/system/naiveproxy.service
    rm -f /root/naive-qvurl.txt /root/naive-client.json
}

startProxy(){
    systemctl start naiveproxy
    systemctl enable naiveproxy
    green "NaiveProxy 已启动成功！"
}

stopProxy(){
    systemctl stop naiveproxy
    systemctl disable naiveproxy
    green "NaiveProxy 已停止成功！"
}

restartProxy(){
    systemctl restart naiveproxy
    green "NaiveProxy 已重启成功！"
}

check_status(){
    if [[ -n $(service naiveproxy status 2>/dev/null | grep "inactive") ]]; then
        status="${RED}未启动${PLAIN}"
    elif [[ -n $(service naiveproxy status 2>/dev/null | grep "active") ]]; then
        status="${GREEN}已启动${PLAIN}"
    else
        status="${RED}未安装${PLAIN}"
    fi
}

menu() {
    clear
    check_status
    echo "#############################################################"
    echo -e "#                  ${RED}NaiveProxy  一键配置脚本${PLAIN}                 #"
    echo -e "# ${GREEN}作者${PLAIN}: MisakaNo の 小破站                                  #"
    echo -e "# ${GREEN}博客${PLAIN}: https://blog.misaka.rest                            #"
    echo -e "# ${GREEN}GitLab 项目${PLAIN}: https://gitlab.com/misakablog                #"
    echo -e "# ${GREEN}Telegram 频道${PLAIN}: https://t.me/misakablogchannel             #"
    echo -e "# ${GREEN}Telegram 群组${PLAIN}: https://t.me/+CLhpemKhaC8wZGIx             #"
    echo -e "# ${GREEN}YouTube 频道${PLAIN}: https://suo.yt/8EOkDib                      #"
    echo "#############################################################"
    echo ""
    echo -e "  ${GREEN}1.${PLAIN}  安装 NaiveProxy"
    echo -e "  ${GREEN}2.${PLAIN}  ${RED}卸载 NaiveProxy${PLAIN}"
    echo " -------------"
    echo -e "  ${GREEN}3.${PLAIN}  启动 NaiveProxy"
    echo -e "  ${GREEN}4.${PLAIN}  停止 NaiveProxy"
    echo -e "  ${GREEN}5.${PLAIN}  重启 NaiveProxy"
    echo " -------------"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo ""
    echo -e "NaiveProxy 状态：$status"
    echo ""
    read -rp " 请输入选项 [0-5] ：" answer
    case $answer in
        1) installProxy ;;
        2) uninstallProxy ;;
        3) startProxy ;;
        4) stopProxy ;;
        5) restartProxy ;;
        *) red "请输入正确的选项 [0-5]！" && exit 1 ;;
    esac
}

menu
