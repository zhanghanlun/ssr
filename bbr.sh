#!/bin/sh

kernel_ubuntu_url="http://kernel.ubuntu.com/~kernel-ppa/mainline/v4.10.2/linux-image-4.10.2-041002-generic_4.10.2-041002.201703120131_amd64.deb"
kernel_ubuntu_file="linux-image-4.10.2-041002-generic_4.10.2-041002.201703120131_amd64.deb"



install_bbr() {
	[[ -d "/proc/vz" ]] && echo -e "[${red}错误${plain}] 你的系统是OpenVZ架构的，不支持开启BBR。" && exit 1
	check_os
	check_bbr_status
	if [ $? -eq 0 ]
	then
		echo -e "[${green}提示${plain}] TCP BBR加速已经开启成功。"
		exit 0
	fi
	check_kernel_version
	if [ $? -eq 0 ]
	then
		echo -e "[${green}提示${plain}] 你的系统版本高于4.9，直接开启BBR加速。"
		sysctl_config
		echo -e "[${green}提示${plain}] TCP BBR加速开启成功"
		exit 0
	fi
	    
	if [[ x"${os}" == x"centos" ]]; then
        	install_elrepo
        	yum --enablerepo=elrepo-kernel -y install kernel-ml kernel-ml-devel
        	if [ $? -ne 0 ]; then
            		echo -e "[${red}错误${plain}] 安装内核失败，请自行检查。"
            		exit 1
        	fi
    	elif [[ x"${os}" == x"debian" || x"${os}" == x"ubuntu" ]]; then
        	[[ ! -e "/usr/bin/wget" ]] && apt-get -y update && apt-get -y install wget
        	#get_latest_version
        	#[ $? -ne 0 ] && echo -e "[${red}错误${plain}] 获取最新内核版本失败，请检查网络" && exit 1
       		 #wget -c -t3 -T60 -O ${deb_kernel_name} ${deb_kernel_url}
        	#if [ $? -ne 0 ]; then
            	#	echo -e "[${red}错误${plain}] 下载${deb_kernel_name}失败，请自行检查。"
            	#	exit 1
       		#fi
        	#dpkg -i ${deb_kernel_name}
        	#rm -fv ${deb_kernel_name}
		wget ${kernel_ubuntu_url}
		if [ $? -ne 0 ]
		then
			echo -e "[${red}错误${plain}] 下载内核失败，请自行检查。"
			exit 1
		fi
		dpkg -i ${kernel_ubuntu_file}
    	else
       	 	echo -e "[${red}错误${plain}] 脚本不支持该操作系统，请修改系统为CentOS/Debian/Ubuntu。"
        	exit 1
    	fi

    	install_config
    	sysctl_config
    	reboot_os
}

check_os() {
        source /etc/os-release
	local os_tmp=$(echo $ID | tr [A-Z] [a-z])
        case $os_tmp in
                ubuntu|debian)
                os='ubuntu'
                ;;
                centos)
                os='centos'
                ;;
                *)
                echo -e "[${red}错误${plain}] 本脚本暂时只支持Centos/Ubuntu/Debian系统，如需用本脚本，请先修改你的系统类型"
                exit 1
                ;;
        esac
}

check_bbr_status() {
    local param=$(sysctl net.ipv4.tcp_available_congestion_control | awk '{print $3}')
    if [[ x"${param}" == x"bbr" ]]; then
        return 0
    else
        return 1
    fi
}
check_kernel_version() {
    local kernel_version=$(uname -r | cut -d- -f1)
    if version_ge ${kernel_version} 4.9; then
        return 0
    else
        return 1
    fi
}
version_ge(){
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"
}

install_elrepo() {
    if centosversion 5; then
        echo -e "[${red}错误${plain}] 脚本不支持CentOS 5。"
        exit 1
    fi

    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org

    if centosversion 6; then
        rpm -Uvh http://www.elrepo.org/elrepo-release-6-8.el6.elrepo.noarch.rpm
    elif centosversion 7; then
        rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
    fi

    if [ ! -f /etc/yum.repos.d/elrepo.repo ]; then
        echo -e "[${red}错误${plain}] 安装elrepo失败，请自行检查。"
        exit 1
    fi
}

centosversion(){
    if [ ${os} == 'centos' ]
    then
        local code=$1
        local version="$(getversion)"
        local main_ver=${version%%.*}
        if [ "$main_ver" == "$code" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

getversion(){
    if [[ -s /etc/redhat-release ]]; then
        grep -oE  "[0-9.]+" /etc/redhat-release
    else
        grep -oE  "[0-9.]+" /etc/issue
    fi
}

sysctl_config() {
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
}

install_config() {
    if [[ x"${os}" == x"centos" ]]; then
        if centosversion 6; then
            if [ ! -f "/boot/grub/grub.conf" ]; then
                echo -e "[${red}错误${plain}] 没有找到/boot/grub/grub.conf文件。"
                exit 1
            fi
            sed -i 's/^default=.*/default=0/g' /boot/grub/grub.conf
        elif centosversion 7; then
            if [ ! -f "/boot/grub2/grub.cfg" ]; then
                echo -e "[${red}错误${plain}] 没有找到/boot/grub2/grub.cfg文件。"
                exit 1
            fi
            grub2-set-default 0
        fi
    elif [[ x"${os}" == x"debian" || x"${os}" == x"ubuntu" ]]; then
        /usr/sbin/update-grub
    fi
}

reboot_os() {
    echo
    echo -e "[${green}提示${plain}] 系统需要重启BBR才能生效。"
    read -p "是否立马重启 [y/n]" is_reboot
    if [[ ${is_reboot} == "y" || ${is_reboot} == "Y" ]]; then
        reboot
    else
        echo -e "[${green}提示${plain}] 取消重启。其自行执行reboot命令。"
        exit 0
    fi
}

install_bbr



