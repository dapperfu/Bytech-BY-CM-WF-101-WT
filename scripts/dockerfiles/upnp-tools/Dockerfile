FROM alpine:latest

LABEL maintainer="IoT Pentest Suite"
LABEL description="UPnP tools for device discovery"

RUN apk add --no-cache \
    miniupnpc \
    python3 \
    py3-pip \
    && pip3 install --no-cache-dir \
    upnpclient \
    && rm -rf /var/cache/apk/*

WORKDIR /data

# Create wrapper script for UPnP tools
RUN echo '#!/bin/sh' > /usr/local/bin/upnp-scan && \
    echo 'python3 -c "import upnpclient; import sys; print(\"UPnP client available\")"' >> /usr/local/bin/upnp-scan && \
    chmod +x /usr/local/bin/upnp-scan

ENTRYPOINT ["sh"]

