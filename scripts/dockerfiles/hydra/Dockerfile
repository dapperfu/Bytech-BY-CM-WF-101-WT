FROM alpine:latest

LABEL maintainer="IoT Pentest Suite"
LABEL description="THC-Hydra for credential brute-forcing"

RUN apk add --no-cache \
    hydra \
    && rm -rf /var/cache/apk/*

WORKDIR /data

ENTRYPOINT ["hydra"]

