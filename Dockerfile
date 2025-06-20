FROM ubuntu:latest
# 更新包列表，安装必要软件，清理缓存
RUN apt-get update && apt-get install -y \
    bash \
    sshpass \
    openssh-client \
    rsync \
  && rm -rf /var/lib/apt/lists/*

# 拷贝你的脚本
COPY sh/*.sh /sh/
RUN find /sh/ -type f -name "*.sh" -exec chmod +x {} \;

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
