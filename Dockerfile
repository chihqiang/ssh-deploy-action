FROM alpine:latest

RUN apk add sshpass openssh-client

COPY sh/*.sh /sh/
RUN find /sh/ -type f -name "*.sh" -exec chmod +x {} \;

ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh


ENTRYPOINT ["/entrypoint.sh"]
