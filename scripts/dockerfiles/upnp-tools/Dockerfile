FROM python:3.11-alpine

LABEL maintainer="IoT Pentest Suite"
LABEL description="UPnP tools for device discovery"

RUN apk add --no-cache \
    gcc \
    musl-dev \
    libffi-dev \
    && pip install --no-cache-dir \
    upnpclient \
    && apk del gcc musl-dev libffi-dev

WORKDIR /data

# Create wrapper script for UPnP tools
RUN echo '#!/bin/sh' > /usr/local/bin/upnp-scan && \
    echo 'python3 -c "import upnpclient; import sys; print(\"UPnP client available\")"' >> /usr/local/bin/upnp-scan && \
    chmod +x /usr/local/bin/upnp-scan

ENTRYPOINT ["python3"]

