# 🚀 ssh-deploy

使用 shell 脚本通过 SSH 将代码打包并部署到远程服务器。

## 📦 功能简介

`ssh-deploy` 是一个 GitHub Action，可以自动打包本地代码，通过 SSH 登录远程服务器并部署到指定目录，同时支持部署后执行自定义命令。

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
| `project_version` | 否       | 20250522001509  | 部署版本                                                     |
| `tar_args`        | 否       | 无              | 打包时传给 `tar` 的额外参数（如 `--exclude='.git'`）         |
| `tar_contain`     | 否       | `.`             | 指定打包时包含的文件或目录（如 `dist .env config`）          |
| `deploy_hosts`    | ✅        | 无              | 部署目标主机，格式：`user:pass@host[:port]` 或 `user@host[:port]`，多个主机用空格分隔 |
| `remote_dir`      | 否       | `/data/apps`    | 远程部署根目录                                               |
| `post_deploy_cmd` | 否       | 无              | 部署完成后在服务器上执行的命令                               |

> `tar_args` 用于指定打包时要排除的文件或目录（如 `.git`、`node_modules`），而 `tar_contain` 用于指定只打包哪些内容（如 `dist`、`.env`）。两者可结合使用，实现灵活控制部署内容。

🧪 示例用法

~~~
name: Deploy Project

on:
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Clone private repo via HTTPS with username/password
        uses: chihqiang/checkout-action@main
        with:
          repo: https://github.com/owner/private-repo.git
          username: ${{ secrets.GIT_USERNAME }}
          password: ${{ secrets.GIT_PASSWORD }}
          branch: main
      - name: Deploy to Server
        uses: chihqiang/ssh-deploy-action@main
        with:
          project_path: repo
          project_name: my-app
          tar_args: --exclude .git
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

1. #### 非 root 用户部署流程补充说明

当使用非 root 用户进行远程部署时，为保证部署脚本能够正常上传和解压文件，以及更新软链接，请确保以下操作：

- 远程服务器上的部署根目录（默认 `/data/apps`）应当由部署用户拥有或具有写权限。
- 例如，假设部署用户为 `ubuntu`，请在远程服务器执行：

```bash
sudo mkdir -p /data/apps
sudo chown -R ubuntu:ubuntu /data/apps
```

2. ### 文件中出现`._`前缀的文件名或文件夹

~~~
export COPYFILE_DISABLE=1
~~~

3. ### 清理多余的releases

~~~
cd /data/apps/test/releases && \
ls -1d */ | grep -E '^[0-9]{14}/$' | sort -r | tail -n +4 | xargs -I {} rm -rf "{}"
~~~

> 命令说明：
>
> 1. `ls -1d */`：列出所有目录（按名称排序）
>
> 2. `grep -E '^[0-9]{14}/$'`：筛选出符合日期格式的目录（14 位数字）
>
> 3. `sort -r`：按名称逆序排列（最新的在前）
>
> 4. `tail -n +4`：从第 4 行开始截取（即排除前 3 个最新的）
>
> 5. `xargs -I {} rm -rf "{}"`：删除筛选出的目录
>
> 安全提示：
>
>   1. 执行前请确认当前目录是否正确（`cd /data/apps/test/releases`）
>   2. 先运行`ls -1d */ | grep -E '^[0-9]{14}/$' | sort -r | tail -n +4`查看会删除哪些目录
>   3. 确认无误后再添加`| xargs -I {} rm -rf "{}"`执行删除

## 🐚 使用原理

该 Action 使用 Docker 镜像运行内部 shell 脚本，流程如下：

1. 根据输入参数打包本地项目为 `.tar.gz`
2. 通过 `scp` 上传至远程服务器临时目录
3. 解压到指定目录（`remote_dir/project_name/project_version`）
4. 更新软链接指向最新版本
5. 可选：执行用户指定的部署后命令（如重启服务等）
