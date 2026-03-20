FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99

# Install dependencies
RUN apt-get update && apt-get install -y \
    xvfb \
    x11vnc \
    ffmpeg \
    wget \
    curl \
    python3 \
    python3-pip \
    dbus-x11 \
    xauth \
    fluxbox \
    novnc \
    websockify \
    && rm -rf /var/lib/apt/lists/*

# Install Zoom (placeholder - user should add actual Zoom .deb)
# Download from: https://zoom.us/download?os=linux
# For now, we'll use a stub that explains the setup
RUN mkdir -p /opt/zoom /usr/bin/zoom

# Create startup script
COPY start-x11.sh /usr/local/bin/start-x11.sh
COPY start-recording.sh /usr/local/bin/start-recording.sh
COPY api-server.py /usr/local/bin/api-server.py
COPY noVNC-index.html /var/www/html/index.html

RUN chmod +x /usr/local/bin/start-x11.sh \
             /usr/local/bin/start-recording.sh \
             /usr/local/bin/api-server.py

# Create recordings directory
RUN mkdir -p /recordings
WORKDIR /recordings

# Expose VNC and noVNC
EXPOSE 6080 8554

# Start Xvfb and noVNC by default
CMD ["/usr/local/bin/start-x11.sh"]