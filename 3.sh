#!/bin/bash
# 脚本名称: setup_mysql.sh
# 版本: 1.0
# 日期: 2024-08-20
# 描述: 从远程主机下载 MySQL 安装包和配置文件，安装 MySQL，修改配置并设置初始密码。
#本机私钥
key1="$HOME/.ssh/id_rsa"
#本机公钥
key2="$HOME/.ssh/id_rsa.pub"
# 自定义数据库密码
db_password="Cbb@123456"

# 远程主机 IP 地址
remote_host="192.168.138.148"

# 远程主机用户名
remote_user="root"
# 远程主机密码
remote_password="123456"
#severid文件路径
server_id="/root/mysqlapp/server-id.txt"
# 本地存储下载文件的目录
local_dir="/root/mysqlapp"

# 远程主机上 MySQL 安装包的路径
remote_mysqlrpm="/root/mysqlapp/mysqlrpm.tar"

# 远程主机上 MySQL 安装包的 MD5 校验文件路径
remote_mysqlmd5="/root/mysqlapp/mysql.md5"

# 远程主机上 MySQL 配置文件的路径
remote_mysqlcnf="/root/mysqlapp/my.cnf"

# 远程主机上 MySQL 配置文件的 MD5 校验文件路径
remote_mysqlcnfmd5="/root/mysqlapp/mycnf.md5"

#检查远程主机是否能ping通
if ! ping -c 1 $remote_host > /dev/null
    then
        echo "无法连接到远程主机 $remote_host"
        exit 1
fi

# 检查本地存储目录是否存在，不存在则创建
if [ ! -d "$local_dir" ]
then
    echo "本地存储目录不存在，正在创建..."
    mkdir -p $local_dir
fi

# 检查 expect 是否安装
if ! yum list installed expect > /dev/null
then
    yum install -y expect
fi

#检查本地是否有密钥文件
if [[ -f "$key1" && -f "$key2" ]]
then
    echo "id_rsa & id_rsa.pub 存在"

else
    echo "id_rsa & id_rsa.pub 不存在"
expect << eof
set timeout 30
spawn ssh-keygen
expect "id_rsa):"
send "\r"
expect "passphrase):"
send "\r"
expect "again:"
send "\r"
expect eof
eof
fi
echo 6666
# 复制公钥到远程主机
expect << EOF
set timeout 10
spawn ssh-copy-id -i $key2 $remote_user@$remote_host
expect {
    "(yes/no)?" {
        send "yes\r"
        exp_continue
    }
    "password:" {
        send "$remote_password\r"
        exp_continue
    }
    "All keys were skipped" {
        send_user "公钥已经存在，无需再次复制。\n"
    }
    "Permission denied" {
        send_user "密码错误或权限不足，无法继续操作。\n"
        exit 1
    }
    timeout {
        send_user "操作超时，可能是防火墙问题。\n"
        exit 2
    }
}
expect eof
EOF
echo 6666复制公钥到远程主机
# 检查退出状态码，确保公钥成功复制
if [ $? -ne 0 ]
then
    echo "公钥复制失败，退出..."
    exit 3
fi

# 从远程主机下载文件
for remote_file in $server_id $remote_mysqlmd5 $remote_mysqlcnf $remote_mysqlcnfmd5 $remote_mysqlrpm
do
    expect << EOF
    set timeout 30
    spawn rsync -avzp $remote_user@$remote_host:$remote_file $local_dir
    expect {
        "rsync error" {
            send_user "rsync 传输错误:"
            exit 4
        }
        timeout {
            send_user "操作超时，可能是网络问题。\n"
            exit 5
        }
        eof {
            send_user "rsync 完成\n"
        }
    }
EOF

    # 检查退出状态码
    if [ $? -ne 0 ]
    then
        echo "文件下载失败: $remote_file"
        exit 255
    fi
done


    # 检查退出状态码
    if [ $? -ne 0 ]
    then
        echo "文件下载失败: $remote_file"
        exit 255
    fi

#进入到本地安装目录
cd $local_dir
# 校验下载的文件的 MD5 值
echo "校验 MD5 值..."
md5sum -c $(basename $remote_mysqlmd5)
if [ $? -ne 0 ]; then
    echo "MD5 校验失败，请检查下载的mysqlrpm."
    exit 1
fi
md5sum -c $(basename $remote_mysqlcnfmd5)
if [ $? -ne 0 ]; then
    echo "MD5 校验失败，请检查下载的mysql配置文件."
    exit 1
fi
# 解压 MySQL 安装包
echo "解压 MySQL 安装包..."
tar -xvf $(basename $remote_mysqlrpm)

# 卸载系统自动安装的mariadb，以免冲突
rpm -e --nodeps mariadb-libs
# 先安装依赖包
yum install ncurses-devel libaio-devel -y
# 安装 MySQL
echo "安装 MySQL..."
rpm -ivh mysql-community-common-5.7.38-1.el7.x86_64.rpm
rpm -ivh mysql-community-libs-5.7.38-1.el7.x86_64.rpm
rpm -ivh mysql-community-devel-5.7.38-1.el7.x86_64.rpm
rpm -ivh mysql-community-client-5.7.38-1.el7.x86_64.rpm
rpm -ivh mysql-community-server-5.7.38-1.el7.x86_64.rpm



# 读取 server-id.txt 中的数字
server_id=$(cat $local_dir/server-id.txt)

# 检查 server_id 是否读取成功
if [ -z "$server_id" ]
then
    echo "无法读取 server-id.txt"s
    exit 1
fi

# 替换 my.cnf 中的 server-id
sed -i "s/^server-id=.*/server-id=$server_id/" $local_dir/my.cnf

# 更新 server-id.txt 中的数字 +1
new_server_id=$((server_id + 1))
echo $new_server_id > $local_dir/server-id.txt

# 将更新后的 server-id.txt 上传回远程主机
expect << EOF
set timeout 30
spawn rsync -avzp $local_dir/server-id.txt $remote_user@$remote_host:/root/mysqlapp/
expect {
    "rsync error" {
        send_user "rsync 传输错误:\n"
        exit 4
    }
    timeout {
        send_user "操作超时，可能是网络问题。\n"
        exit 5
    }
    eof {
        send_user "rsync 完成\n"
    }
}
EOF

# 替换 MySQL 配置文件
echo "替换 MySQL 配置文件..."
cp $(basename $remote_mysqlcnf) /etc/my.cnf

# 修改配置文件权限
echo "修改配置文件权限..."
chown mysql:mysql /etc/my.cnf

# 创建配置中所需目录并修改权限
echo "创建配置目录并设置权限..."
mkdir -p /data /data/mysql-slow /data/mysql-bin
chown -R mysql:mysql /data

# 启动 MySQL 服务
echo "启动 MySQL 服务..."
systemctl start mysqld

# 查找 MySQL 初始密码
echo "查找 MySQL 初始密码..."
initial_password=$(grep 'temporary password' /var/log/mysqld.log | tail -n 1 | awk '{print $NF}')

if [ -z "$initial_password" ]
then
    echo "无法找到 MySQL 初始密码."
    exit 2
fi

# 修改 root 密码和权限
echo "修改 root 密码和权限..."
mysql -uroot -p"$initial_password" --connect-expired-password -e "
ALTER USER 'root'@'localhost' IDENTIFIED BY '$db_password';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;"

# 退出 MySQL
mysqladmin -uroot -p"$db_password" shutdown

# 重启 MySQL 服务
echo "重启 MySQL 服务..."
systemctl restart mysqld

echo "MySQL 安装和配置完成。"
