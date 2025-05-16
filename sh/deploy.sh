#!/bin/bash

# ==========================================================
# 自动化部署脚本
# 
# 功能：
#   - 打包当前项目（默认当前目录）
#   - 上传到一台或多台远程服务器
#   - 解压至指定版本目录并更新软链接
#   - 支持密码或 SSH Key 登录
#   - 支持部署后自定义命令执行（如重启服务）
#
# 使用方式：
#   设置环境变量后运行脚本：
#   export DEPLOY_HOSTS=ubuntu:123456@127.0.0.1:8022
#   export POST_DEPLOY_CMD="ls -al"
#   curl -sSL https://raw.githubusercontent.com/chihqiang/ssh-deploy-action/main/sh/deploy.sh | bash 
#
# 环境变量说明：
#   DEPLOY_HOSTS      多个部署目标，空格分隔，格式支持：
#                       user:pass@host
#                       user:pass@host:port
#                       user@host
#                       user@host:port
#   PROJECT_PATH      本地项目路径，默认当前目录
#   PROJECT_NAME      项目名称（用于目录命名），默认目录名
#   PROJECT_VERSION   发布版本号，默认使用当前时间戳
#   TAR_ARGS 使用tar压缩文件扩展参数 默认--exclude=".git" --exclude="node_modules"
#   REMOTE_DIR 部署目录
#   POST_DEPLOY_CMD   部署完成后执行的命令（可选）
#
# 依赖：
#   - tar
#   - ssh / scp
#   - sshpass（仅用于密码登录）
#
# ==========================================================

# 遇到错误立即退出
set -euo pipefail

# podman run -it --name ubuntu -p 8022:22 -d zhiqiangwang/proxy:ssh
# 非root账号
# sudo mkdir -p  /data/apps && sudo chown -R ubuntu:ubuntu /data/apps
# export DEPLOY_HOSTS=ubuntu:123456@127.0.0.1:8022
# export POST_DEPLOY_CMD="ls -al"

# ==== 彩色输出函数 ====
color_echo() {
  local color_code=$1; shift
  echo -e "\033[${color_code}m[$(date +'%H:%M:%S')] $@\033[0m"
}
info()    { color_echo "1;34" "ℹ️  $@"; }
success() { color_echo "1;32" "✅ $@"; }
warning() { color_echo "1;33" "⚠️  $@"; }
error()   { color_echo "1;31" "❌ $@"; }
step()    { color_echo "1;36" "🚀 $@"; }
divider() { echo -e "\033[1;30m--------------------------------------------------\033[0m"; }

# ==== 环境准备 ====
# 创建临时目录
TEMP_PATH="$(mktemp -d)"

# 脚本退出时自动清理临时目录
trap 'rm -rf "$TEMP_PATH"' EXIT INT

# 读取项目路径（默认当前目录）
PROJECT_PATH="${PROJECT_PATH:-$(pwd)}"

# 获取项目名（目录名）
PROJECT_NAME="${PROJECT_NAME:-"$(basename "$PROJECT_PATH")"}"

# 生成默认版本号（时间戳）
PROJECT_VERSION="${PROJECT_VERSION:-$(date +%Y%m%d%H%M%S)}"

# 打包文件名
TAR_FILE_NAME="${PROJECT_NAME}_${PROJECT_VERSION}.tar.gz"

# 打包时候args
TAR_ARGS="${TAR_ARGS:-""}"

# 本地 tar 包路径
TAR_LOCAL_FILE="$TEMP_PATH/$TAR_FILE_NAME"

# 远程基础路径
REMOTE_DIR="${REMOTE_DIR:-"/data/apps"}"
REMOTE_APP_DIR="$REMOTE_DIR/$PROJECT_NAME"
# 远程版本目录
REMOTE_RELEASE_DIR="$REMOTE_APP_DIR/releases/$PROJECT_VERSION"

# 远程 tar 包路径
REMOTE_TAR="$REMOTE_RELEASE_DIR/$TAR_FILE_NAME"

# 远程软链接路径
REMOTE_WEBSITE="$REMOTE_APP_DIR/website"
POST_DEPLOY_CMD=${POST_DEPLOY_CMD:-""}

info "项目路径: $PROJECT_PATH"
info "项目名称: $PROJECT_NAME"
info "项目版本: $PROJECT_VERSION"
info "打包文件名: $TAR_FILE_NAME"
info "打包参数: $TAR_ARGS"
info "本地 tar 路径: $TAR_LOCAL_FILE"
info "远程部署目录: $REMOTE_DIR"
info "远程项目目录: $REMOTE_APP_DIR"
info "远程版本目录: $REMOTE_RELEASE_DIR"
info "远程 tar 包路径: $REMOTE_TAR"
info "远程软链接路径: $REMOTE_WEBSITE"
info "部署后命令: ${POST_DEPLOY_CMD:-无}"

# ==== 打包 ====
step "打包项目"

# 检查项目目录是否存在
if [ ! -d "$PROJECT_PATH" ]; then
  error "项目路径不存在：$PROJECT_PATH"
  exit 1
fi

# 进入项目目录
cd "$PROJECT_PATH"

# 排除无用目录并打包
tar $TAR_ARGS -czf "$TAR_LOCAL_FILE" .

# 打包完成提示
success "项目打包完成"

# ==== 读取部署主机 ====

# 从环境变量或交互输入读取主机信息
deploy_hosts_input="${DEPLOY_HOSTS:-}"
if [ -z "$deploy_hosts_input" ]; then
  read -p "请输入多个 SSH 信息 (user:pass@host[:port] 或 user@host[:port])，空格分隔: " deploy_hosts_input
  info "输入部署主机：$deploy_hosts_input"
else
  info "使用环境变量 DEPLOY_HOSTS"
fi

# 按空格拆分主机列表
IFS=' ' read -r -a ssh_list <<< "$deploy_hosts_input"

# ==== SSH/上传命令封装 ====

ssh_cmd() {
  local user=$1 host=$2 port=$3 pass=$4 cmd=$5
  local remote_cmd="set -euo pipefail; $cmd"
  if [ -n "$pass" ]; then
    sshpass -p "$pass" ssh -o StrictHostKeyChecking=no -p "$port" "$user@$host" "$remote_cmd"
  else
    ssh -o StrictHostKeyChecking=no -p "$port" "$user@$host" "$remote_cmd"
  fi
}

scp_cmd() {
  local user=$1 host=$2 port=$3 pass=$4 src=$5 dst=$6
  if [ -n "$pass" ]; then
    sshpass -p "$pass" scp -P "$port" "$src" "$user@$host:$dst"
  else
    scp -P "$port" "$src" "$user@$host:$dst"
  fi
}

# ==== 上传部署 ====
for ssh_info in "${ssh_list[@]}"; do
  divider
  step "解析主机信息：$ssh_info"

  # 正则匹配解析 SSH 信息
  if [[ "$ssh_info" =~ ^([^:]+):([^@]+)@([^:]+):([0-9]+)$ ]]; then
    ssh_user="${BASH_REMATCH[1]}"
    ssh_pass="${BASH_REMATCH[2]}"
    ssh_host="${BASH_REMATCH[3]}"
    ssh_port="${BASH_REMATCH[4]}"
  elif [[ "$ssh_info" =~ ^([^:]+):([^@]+)@([^@]+)$ ]]; then
    ssh_user="${BASH_REMATCH[1]}"
    ssh_pass="${BASH_REMATCH[2]}"
    ssh_host="${BASH_REMATCH[3]}"
    ssh_port=22
  elif [[ "$ssh_info" =~ ^([^@]+)@([^:]+):([0-9]+)$ ]]; then
    ssh_user="${BASH_REMATCH[1]}"
    ssh_host="${BASH_REMATCH[2]}"
    ssh_port="${BASH_REMATCH[3]}"
    ssh_pass=""
  elif [[ "$ssh_info" =~ ^([^@]+)@([^@]+)$ ]]; then
    ssh_user="${BASH_REMATCH[1]}"
    ssh_host="${BASH_REMATCH[2]}"
    ssh_port=22
    ssh_pass=""
  else
    error "SSH 信息格式错误，跳过：$ssh_info"
    continue
  fi

  # 打印主机信息
  info "用户: $ssh_user"
  info "主机: $ssh_host"
  info "端口: $ssh_port"
  info "密码: ${ssh_pass:+***隐藏***}"

  # 创建远程目录并验证软链接
  step "检查远程目录 $REMOTE_RELEASE_DIR 和软链接 $REMOTE_WEBSITE"
  ssh_cmd "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_pass" "
    mkdir -p $REMOTE_RELEASE_DIR
    if [ -e '$REMOTE_WEBSITE' ] && [ ! -L '$REMOTE_WEBSITE' ]; then
      echo '❌ $REMOTE_WEBSITE 不是软链接，退出'
      exit 1
    fi
  "

  # 上传打包文件（支持失败重试）
  step "上传包到远程 $REMOTE_TAR"
  max_retries=3
  attempt=1
  while [ $attempt -le $max_retries ]; do
    if scp_cmd "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_pass" "$TAR_LOCAL_FILE" "$REMOTE_TAR"; then
      success "上传完成"
      break
    else
      warning "第 $attempt 次上传失败，重试中..."
      sleep 2
      ((attempt++))
    fi
  done

  if [ $attempt -gt $max_retries ]; then
    error "上传失败超过最大重试次数，跳过该主机"
    continue
  fi

  # 解压文件并删除 tar 包
  step "远程解压"
  ssh_cmd "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_pass" "
    cd '$REMOTE_RELEASE_DIR' && tar -xzf '${TAR_FILE_NAME}' && rm -f '${TAR_FILE_NAME}'
  "

  # 更新软链接指向
  step "更新软链接指向 $REMOTE_RELEASE_DIR"
  ssh_cmd "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_pass" "
    ln -sfn '$REMOTE_RELEASE_DIR' '$REMOTE_WEBSITE'
    echo '当前链接指向：' && readlink -f '$REMOTE_WEBSITE'
  "
  #  执行部署后命令
  if [ -n "$POST_DEPLOY_CMD" ]; then
    step "执行部署后命令"
    ssh_cmd "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_pass" "
      cd '$REMOTE_WEBSITE' && $POST_DEPLOY_CMD
    "
    success "部署后命令执行完毕"
  fi

   success "部署成功：$ssh_host:$REMOTE_WEBSITE"
done

# 打印完成提示
divider
success "全部部署完成 🎉"
