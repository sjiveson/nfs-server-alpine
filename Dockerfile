FROM golang:alpine as builder

ARG CONFD_VERSION=v0.14.0

ENV ROOT=$GOPATH/src/github.com/kelseyhightower
RUN apk add --no-cache git make
RUN mkdir -p $ROOT
RUN git clone https://github.com/kelseyhightower/confd.git $ROOT/confd
RUN git -C $ROOT/confd checkout -q $CONFD_VERSION
RUN make --directory $ROOT/confd
RUN cp $ROOT/confd/bin/confd /


FROM alpine:latest
LABEL maintainer "Steven Iveson <steve@iveson.eu>"
LABEL source "https://github.com/sjiveson/nfs-server-alpine"
LABEL branch "master"
COPY Dockerfile /Dockerfile
COPY README.md /README.md

RUN apk add --update --verbose nfs-utils bash iproute2 && \
    rm -rf /var/cache/apk/* /tmp/* && \
    rm -f /sbin/halt /sbin/poweroff /sbin/reboot && \
    mkdir -p /var/lib/nfs/rpc_pipefs && \
    mkdir -p /var/lib/nfs/v4recovery && \
    echo "rpc_pipefs    /var/lib/nfs/rpc_pipefs rpc_pipefs      defaults        0       0" >> /etc/fstab && \
    echo "nfsd  /proc/fs/nfsd   nfsd    defaults        0       0" >> /etc/fstab

COPY --from=builder /confd /usr/bin/confd
COPY confd/confd.toml /etc/confd/confd.toml
COPY confd/toml/* /etc/confd/conf.d/
COPY confd/tmpl/* /etc/confd/templates/

COPY nfsd.sh /usr/bin/nfsd.sh
COPY .bashrc /root/.bashrc

RUN chmod +x /usr/bin/nfsd.sh /usr/bin/confd

ENTRYPOINT ["/usr/bin/nfsd.sh"]
