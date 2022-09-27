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
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
    ~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive
    rm -rf go
    mv ./caddy /usr/bin/caddy
}

makesite(){
    rm -rf /var/www/html
    mkdir -p /var/www/html
    cd /var/www/html
    wget -N --no-check-certificate https://gitlab.com/misakablog/naiveproxy-script/-/raw/main/mikutap.zip
    if [[ -z $(type -P unzip) ]]; then
        if [[ ! $SYSTEM == "CentOS" ]]; then
            ${PACKAGE_UPDATE[int]}
        fi
        ${PACKAGE_INSTALL[int]} unzip
    fi
    unzip mikutap.zip
}

makeconfig(){
    acmeDomain=$(bash ~/.acme.sh/acme.sh --list | sed -n 2p | awk -F ' ' '{print $1}')
    if [[ -n $acmeDomain ]]; then
        domain=$acmeDomain
    else
        read -rp "请输入需要用在NaiveProxy的域名：" domain
        [[ -z $domain ]] && read -rp "请输入需要用在NaiveProxy的域名：" domain

        if [[ ! $SYSTEM == "CentOS" ]]; then
            ${PACKAGE_UPDATE[int]}
        fi
        ${PACKAGE_INSTALL[int]} curl wget sudo socat
        if [[ $SYSTEM == "CentOS" ]]; then
            ${PACKAGE_INSTALL[int]} cronie
            systemctl start crond
            systemctl enable crond
        else
            ${PACKAGE_INSTALL[int]} cron
            systemctl start cron
            systemctl enable cron
        fi

        curl https://get.acme.sh | sh -s email=$(date +%s%N | md5sum | cut -c 1-16)@gmail.com
        source ~/.bashrc
        bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

        WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        domainIP=$(curl -sm8 ipget.net/?ip="${domain}")
        if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
            wg-quick down wgcf >/dev/null 2>&1
            ipv4=$(curl -s4m8 api64.ipify.org -k)
            ipv6=$(curl -s6m8 api64.ipify.org -k)
            wg-quick up wgcf >/dev/null 2>&1
        else
            ipv4=$(curl -s4m8 api64.ipify.org -k)
            ipv6=$(curl -s6m8 api64.ipify.org -k)
        fi

        if [[ $domainIP == $ipv6 ]]; then
            bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --listen-v6 --insecure
        fi
        if [[ $domainIP == $ipv4 ]]; then
            bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --insecure
        fi
        if [[ $domainIP != $ipv4 ]] && [[ $domainIP != $ipv6 ]]; then
            red "当前域名解析的IP与当前VPS使用的真实IP不匹配"
            green "建议如下："
            yellow "1. 请确保CloudFlare小云朵为关闭状态(仅限DNS), 其他域名解析或CDN网站设置同理"
            yellow "2. 请检查DNS解析设置的IP是否为VPS的真实IP"
            yellow "3. 脚本可能跟不上时代, 建议截图发布到GitHub Issues、GitLab Issues、论坛或TG群询问"
            exit 1
        fi
        bash ~/.acme.sh/acme.sh --install-cert -d ${domain} --key-file /root/private.key --fullchain-file /root/cert.crt --ecc

        if [[ -f /root/cert.crt && -f /root/private.key ]]; then
            if [[ -s /root/cert.crt && -s /root/private.key ]]; then
                sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
                echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab
                green "证书申请成功! 脚本申请到的证书 (cert.crt) 和私钥 (private.key) 文件已保存到 /root 文件夹下"
                yellow "证书crt文件路径如下: /root/cert.crt"
                yellow "私钥key文件路径如下: /root/private.key"
            else
                red "很抱歉，证书申请失败"
                green "建议如下: "
                yellow "1. 自行检测防火墙是否打开, 如使用80端口申请模式时, 请关闭防火墙或放行80端口"
                yellow "2. 同一域名多次申请可能会触发Let's Encrypt官方风控, 请尝试使用脚本菜单的9选项更换证书颁发机构, 再重试申请证书, 或更换域名、或等待7天后再尝试执行脚本"
                yellow "3. 脚本可能跟不上时代, 建议截图发布到GitHub Issues询问"
                exit 1
            fi
        fi
    fi
    read -rp "请输入NaiveProxy的用户名 [默认随机生成]：" proxyname
    [[ -z $proxyname ]] && proxyname=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "请输入NaiveProxy的密码 [默认随机生成]：" proxypwd
    [[ -z $proxypwd ]] && proxypwd=$(cat /proc/sys/kernel/random/uuid)

    yellow "正在写入配置文件，请稍等..."
    sleep 2
    cat > /usr/bin/naive.json <<EOF
{
    "admin": {
        "disabled": true
    },
    "logging": {
        "sink": {
            "writer": {
                "output": "discard"
            }
        },
        "logs": {
            "default": {
                "writer": {
                    "output": "discard"
                }
            }
        }
    },
    "apps": {
        "http": {
            "servers": {
                "srv0": {
                    "listen": [
                        ":443"
                    ],
                    "routes": [
                        {
                            "handle": [
                                {
                                    "handler": "subroute",
                                    "routes": [
                                        {
                                            "handle": [
                                                {
                                                    "auth_pass_deprecated": "${proxypwd}",
                                                    "auth_user_deprecated": "${proxyname}",
                                                    "handler": "forward_proxy",
                                                    "hide_ip": true,
                                                    "hide_via": true,
                                                    "probe_resistance": {}
                                                }
                                            ]
                                        },
                                        {
                                            "match": [
                                                {
                                                    "host": [
                                                        "${domain}"
                                                    ]
                                                }
                                            ],
                                            "handle": [
                                                {
                                                    "handler": "file_server",
                                                    "root": "/var/www/html",
                                                    "index_names": [
                                                        "index.html"
                                                    ]
                                                }
                                            ],
                                            "terminal": true
                                        }
                                    ]
                                }
                            ]
                        }
                    ],
                    "experimental_http3": true,
                    "tls_connection_policies": [
                        {
                            "match": {
                                "sni": [
                                    "${domain}"
                                ]
                            }
                        }
                    ],
                    "automatic_https": {
                        "disable": true
                    }
                }
            }
        },
        "tls": {
            "certificates": {
                "load_files": [
                    {
                        "certificate": "/root/cert.crt",
                        "key": "/root/private.key"
                    }
                ]
            }
        }
    }
}
EOF

    cat <<'TEXT' > /etc/systemd/system/naiveproxy.service
[Unit]
Description=Naiveproxy server, script by taffychan
After=network.target
[Install]
WantedBy=multi-user.target
[Service]
Type=simple
WorkingDirectory=/root
ExecStart=/usr/bin/caddy run -config /usr/bin/naive.json
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
    makesite
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
    rm -rf /var/www/html
    rm -f /usr/bin/caddy /etc/systemd/system/naiveproxy.service /usr/bin/naive.json
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
    echo -e "# ${GREEN}GitLab${PLAIN}: https://gitlab.com/misakablog                     #"
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
