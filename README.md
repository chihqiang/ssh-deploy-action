# 🚀 ssh-releases-deploy

使用 shell 脚本通过 SSH 将代码打包并部署到远程服务器。

## 📦 功能简介

`ssh-releases-deploy` 是一个 GitHub Action，可以自动打包本地代码，通过 SSH 登录远程服务器并部署到指定目录，同时支持部署后执行自定义命令。

------

## ✨ 特性

- 支持多台主机同时部署
- 支持排除特定文件/目录打包
- 支持部署后执行自定义命令
- 支持密码

## 🧾 输入参数（Inputs）

| 参数名            | 是否必填 | 默认值          | 描述                                                         |
| ----------------- | -------- | --------------- | ------------------------------------------------------------ |
| `project_path`    | 否       | `.`（当前目录） | 本地项目路径                                                 |
| `project_name`    | 否       | 当前目录名      | 项目名称                                                     |
| `project_version` | 否       | 当前时间戳      | 部署版本                                                     |
| `tar_args`        | 否       | 无              | 打包时传给 `tar` 的额外参数（如 `--exclude='.git'`）         |
| `deploy_hosts`    | ✅        | 无              | 部署目标主机，格式：`user:pass@host[:port]` 或 `user@host[:port]`，多个主机用空格分隔 |
| `remote_dir`      | 否       | `/data/apps`     | 远程部署根目录                                               |
| `post_deploy_cmd` | 否       | 无              | 部署完成后在服务器上执行的命令                               |

🧪 示例用法

~~~
name: Deploy Project

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v3

      - name: Deploy to Server
        uses: chihqiang/ssh-deploy-action
        with:
          project_path: ./my-app
          project_name: my-app
          tar_args: "--exclude='.git' --exclude='node_modules'"
          deploy_hosts: root:123456@127.0.0.1:8022
          remote_dir: /data/apps
          post_deploy_cmd: "ls -al"

~~~

## 🏃‍♂️ 本地快速一键远程部署示例

你也可以直接在本地通过环境变量传入参数，一键远程执行官方部署脚本：

```
export DEPLOY_HOSTS=ubuntu:123456@127.0.0.1:8022
export POST_DEPLOY_CMD="ls -al"
curl -sSL https://raw.githubusercontent.com/chihqiang/ssh-deploy-action/main/sh/deploy.sh | bash
```

- `DEPLOY_HOSTS`：部署目标主机，支持多个主机用空格分隔，格式同 Action 输入参数中的 `deploy_hosts`
- `POST_DEPLOY_CMD`：部署完成后远程执行的命令（可选）

该命令会：

1. 下载并执行远程部署脚本
2. 自动打包当前目录代码上传远程
3. 解压并部署到远程服务器
4. 执行你指定的后置命令

## ❌ 常见问题

1. ### 非 root 用户部署流程补充说明

当使用非 root 用户进行远程部署时，为保证部署脚本能够正常上传和解压文件，以及更新软链接，请确保以下操作：

- 远程服务器上的部署根目录（默认 `/data/apps`）应当由部署用户拥有或具有写权限。
- 例如，假设部署用户为 `ubuntu`，请在远程服务器执行：

```bash
sudo mkdir -p /data/apps
sudo chown -R ubuntu:ubuntu /data/apps
```

2. ## 文件中出现`._`前缀的文件名或文件夹

~~~
export COPYFILE_DISABLE=1
~~~

## 🐚 使用原理

该 Action 使用 Docker 镜像运行内部 shell 脚本，流程如下：

1. 根据输入参数打包本地项目为 `.tar.gz`
2. 通过 `scp` 上传至远程服务器临时目录
3. 解压到指定目录（`remote_dir/project_name/project_version`）
4. 更新软链接指向最新版本
5. 可选：执行用户指定的部署后命令（如重启服务等）
