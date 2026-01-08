FROM alpine:latest

LABEL maintainer="IoT Pentest Suite"
LABEL description="Nikto web server scanner"

RUN apk add --no-cache \
    nikto \
    perl \
    perl-net-ssleay \
    && rm -rf /var/cache/apk/*

WORKDIR /data

ENTRYPOINT ["nikto"]

