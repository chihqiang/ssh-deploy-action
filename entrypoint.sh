#!/bin/bash

set -euo pipefail

# 读取环境变量 INPUT_PROJECT_PATH，若未设置则为空，赋值给 PROJECT_PATH
export PROJECT_PATH="${INPUT_PROJECT_PATH:-}"

# 读取环境变量 INPUT_PROJECT_NAME，若未设置则为空，赋值给 PROJECT_NAME
export PROJECT_NAME="${INPUT_PROJECT_NAME:-}"

# 读取环境变量 INPUT_PROJECT_VERSION，若未设置则为空，赋值给 PROJECT_VERSION
export PROJECT_VERSION="${INPUT_PROJECT_VERSION:-$(date +%Y%m%d%H%M%S)}"

# 读取环境变量 INPUT_TAR_ARGS，若未设置则使用默认排除.git和node_modules，赋值给 TAR_ARGS
export TAR_ARGS="${INPUT_TAR_ARGS:-}"

# 读取环境变量 INPUT_TAR_CONTAIN，若未设置则使用默认当前目录，赋值给 TAR_CONTAIN
export TAR_CONTAIN="${INPUT_TAR_CONTAIN:-"."}"

# 读取环境变量 INPUT_DEPLOY_HOSTS，若未设置则为空，赋值给 DEPLOY_HOSTS
export DEPLOY_HOSTS="${INPUT_DEPLOY_HOSTS:-}"

# 读取环境变量 INPUT_REMOTE_DIR，若未设置则使用默认目录 /data/apps，赋值给 REMOTE_DIR
export REMOTE_DIR="${INPUT_REMOTE_DIR:-}"

# 读取环境变量 INPUT_POST_DEPLOY_CMD，若未设置则为空，赋值给 POST_DEPLOY_CMD
export POST_DEPLOY_CMD="${INPUT_POST_DEPLOY_CMD:-}"

# 判断 DEPLOY_HOSTS 是否为空，如果为空则打印错误信息并退出脚本
if [ -z "$DEPLOY_HOSTS" ]; then
  echo "❌ ERROR: DEPLOY_HOSTS is empty. Please provide at least one deploy host."
  exit 1
fi
# 引入并执行 /sh/deploy.sh 脚本，执行具体的部署逻辑
source /sh/deploy.sh