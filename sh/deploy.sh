#!/bin/bash
set -euo pipefail

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
trap 'rm -rf "$TEMP_PATH"' EXIT INT TERM
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
TAR_CONTAIN="${TAR_CONTAIN:-"."}"
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

divider

info "rsync version: $(rsync --version)"
info "tar version: $(tar --version)"
info "Project path: $PROJECT_PATH"
info "Project name: $PROJECT_NAME"
info "Project version: $PROJECT_VERSION"
info "Package file name: $TAR_FILE_NAME"
info "Package exclude args: $TAR_ARGS"
info "Package include args: $TAR_CONTAIN"
info "Local tar file path: $TAR_LOCAL_FILE"

divider

info "Remote deploy base dir: $REMOTE_DIR"
info "Remote project dir: $REMOTE_APP_DIR"
info "Remote release dir: $REMOTE_RELEASE_DIR"
info "Remote tar file path: $REMOTE_TAR"
info "Remote symlink path: $REMOTE_WEBSITE"
info "Post deploy command: ${POST_DEPLOY_CMD:-None}"

divider

# ==== 打包 ====
step "Packaging project"

# 检查项目目录是否存在
if [ ! -d "$PROJECT_PATH" ]; then
  error "Project path does not exist: $PROJECT_PATH"
  exit 1
fi

# 进入项目目录
cd "$PROJECT_PATH"

# 排除无用目录并打包
tar -czf "$TAR_LOCAL_FILE" $TAR_ARGS $TAR_CONTAIN || {
  error "Packaging failed"
  exit 1
}

# 打包完成提示
success "Project packaging completed"

# 获取打包文件大小（以 MB 显示）
TAR_SIZE_MB=$(du -m "$TAR_LOCAL_FILE" | awk '{print $1}')
info "Package file size: ${TAR_SIZE_MB} MB"
# 从环境变量或交互输入读取主机信息
deploy_hosts_input="${DEPLOY_HOSTS:-}"
if [ -z "$deploy_hosts_input" ]; then
  read -p "Please enter multiple SSH infos (user:pass@host[:port] or user@host[:port]), separated by spaces: " deploy_hosts_input
  info "Input deploy hosts: $deploy_hosts_input"
else
  info "Using environment variable DEPLOY_HOSTS"
fi

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

rsync_cmd() {
  local user=$1 host=$2 port=$3 pass=$4 src=$5 dst=$6
  if [ -n "$pass" ]; then
    # Password mode wraps rsync with sshpass
    sshpass -p "$pass" rsync -avz --progress -e "ssh -p $port -o StrictHostKeyChecking=no" "$src" "$user@$host:$dst"
  else
    # SSH key login
    rsync -avz --progress -e "ssh -p $port -o StrictHostKeyChecking=no" "$src" "$user@$host:$dst"
  fi
}

# ==== 上传部署 ====
# 按空格拆分主机列表
IFS=' ' read -r -a ssh_list <<< "$deploy_hosts_input"
for ssh_info in "${ssh_list[@]}"; do
  divider
  step "Parsing host info: $ssh_info"

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
    error "Invalid SSH info format, skipping: $ssh_info"
    continue
  fi
  # 打印主机信息
  info "User: ${ssh_user:+***hidden***}"
  info "Host: $ssh_host"
  info "Port: ${ssh_port:+***hidden***}"
  info "Password: ${ssh_pass:+***hidden***}"
  # 创建远程目录并验证软链接
  step "Checking remote dir $REMOTE_RELEASE_DIR and symlink $REMOTE_WEBSITE"
  ssh_cmd "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_pass" "
    mkdir -p $REMOTE_RELEASE_DIR
    if [ -e '$REMOTE_WEBSITE' ] && [ ! -L '$REMOTE_WEBSITE' ]; then
      echo '❌ $REMOTE_WEBSITE is not a symlink, exiting'
      exit 1
    fi
  "

  # 上传打包文件（支持失败重试）
  step "Uploading package to remote $REMOTE_TAR"
  max_retries=3
  attempt=1
  while [ $attempt -le $max_retries ]; do
    if rsync_cmd "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_pass" "$TAR_LOCAL_FILE" "$REMOTE_TAR"; then
      success "Upload completed"
      break
    else
      warning "Upload attempt $attempt failed, retrying..."
      sleep 2
      ((attempt++))
    fi
  done

  if [ $attempt -gt $max_retries ]; then
    error "Upload failed after maximum retries, skipping this host"
    continue
  fi

  # 解压文件并删除 tar 包
  step "Remote untar"
  ssh_cmd "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_pass" "
    cd '$REMOTE_RELEASE_DIR' && tar -xzf '${TAR_FILE_NAME}' && rm -f '${TAR_FILE_NAME}'
  "

  # 更新软链接指向
  step "Updating symlink to $REMOTE_RELEASE_DIR"
  ssh_cmd "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_pass" "
    ln -snf '$REMOTE_RELEASE_DIR' '$REMOTE_WEBSITE'
  "

  # 执行后续命令
  if [ -n "$POST_DEPLOY_CMD" ]; then
    step "Executing post deploy command"
    ssh_cmd "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_pass" "
      cd '$REMOTE_WEBSITE' && $POST_DEPLOY_CMD
    "
  fi

  success "Deployment to $ssh_host succeeded"
done

divider
success "All deployments completed!"
