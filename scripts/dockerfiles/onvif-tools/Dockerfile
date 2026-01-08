FROM python:3.11-alpine

LABEL maintainer="IoT Pentest Suite"
LABEL description="ONVIF CLI tools for camera enumeration"

RUN apk add --no-cache \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev \
    && pip install --no-cache-dir \
    onvif-zeep \
    && apk del gcc musl-dev libffi-dev

# Install onvif-cli if available via pip, otherwise create wrapper
RUN pip install --no-cache-dir onvif-cli || \
    (echo '#!/usr/bin/env python3' > /usr/local/bin/onvif-cli && \
     echo 'from onvif import ONVIFCamera' >> /usr/local/bin/onvif-cli && \
     echo 'import sys' >> /usr/local/bin/onvif-cli && \
     echo 'if __name__ == "__main__":' >> /usr/local/bin/onvif-cli && \
     echo '    print("ONVIF tools available via Python onvif-zeep")' >> /usr/local/bin/onvif-cli && \
     chmod +x /usr/local/bin/onvif-cli)

WORKDIR /data

ENTRYPOINT ["python3"]

