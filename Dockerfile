FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG GOST_VERSION=3.2.6

ENV TZ=Asia/Shanghai \
    DISPLAY=:1 \
    VNC_GEOMETRY=1440x900 \
    VNC_DEPTH=24 \
    HILLSTONE_HOME=/opt/apps/hillstonesecureconnect/files \
    LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN:zh \
    LC_ALL=zh_CN.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl dbus dbus-x11 dnsmasq-base flwm \
      fonts-wqy-microhei fonts-wqy-zenhei iproute2 iputils-ping libasound2 \
      libegl1 libfontconfig1 libgl1 libglib2.0-0 libgtk2.0-0 libnss3 \
      libpam0g libpcre2-16-0 libpolkit-agent-1-0 libx11-6 libx11-xcb1 \
      libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 \
      libxcb-render-util0 libxcb-shape0 libxcb-shm0 libxcb-xinerama0 \
      libxcb-xkb1 libxcb1 libxext6 libxi6 libxkbcommon-x11-0 libxrender1 \
      libxss1 libxtst6 locales net-tools iptables novnc \
      policykit-1 procps psmisc sudo supervisor tigervnc-standalone-server \
      tigervnc-tools tini websockify x11-utils xdg-utils xterm && \
    sed -i 's/^# *\(zh_CN.UTF-8 UTF-8\)/\1/' /etc/locale.gen && \
    locale-gen zh_CN.UTF-8 && \
    update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && \
    rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash desktop && \
    install -d -o desktop -g desktop /home/desktop/.vnc /home/desktop/.config && \
    install -d /run/dbus /run/hillstone-vpn /var/log/supervisor

RUN case "$TARGETARCH" in \
      amd64) gost_arch=amd64; expected=b39037b0380ea001fb3c0c28441c2e10bfc694f90682739a65b53e55dce5238b ;; \
      arm64) gost_arch=arm64; expected=f674c8f4a033dc1dfd4f0d5e9602fbe5b0d0f81307bf3794f44b5b5d6d622eae ;; \
      *) echo "Unsupported TARGETARCH for GOST: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    archive="gost_${GOST_VERSION}_linux_${gost_arch}.tar.gz" && \
    curl --fail --location --show-error --retry 3 \
      "https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}/${archive}" \
      --output "/tmp/${archive}" && \
    test "$(sha256sum "/tmp/${archive}" | cut -d' ' -f1)" = "$expected" && \
    tar -xzf "/tmp/${archive}" -C /tmp gost && \
    install -m 0755 /tmp/gost /usr/local/bin/gost && \
    /usr/local/bin/gost -V 2>&1 | grep -q "${GOST_VERSION}" && \
    rm -f "/tmp/${archive}" /tmp/gost

COPY vendor/hillstonesecureconnect_5.5.0.12175_amd64.deb /tmp/hillstone-amd64.deb
COPY vendor/hillstonesecureconnect_5.5.0.12186_arm64.deb /tmp/hillstone-arm64.deb
RUN case "$TARGETARCH" in \
      amd64) package=/tmp/hillstone-amd64.deb; expected=fe0cb6176a67c0fb682138aee9965486e085b498375fff97c0a52b99d9dbaf3e ;; \
      arm64) package=/tmp/hillstone-arm64.deb; expected=0e3428449537653fb07d6dadf06bb08b07db64b4c99c730d60731b3edf08bcca ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    test "$(sha256sum "$package" | cut -d' ' -f1)" = "$expected" && \
    test "$(dpkg-deb -f "$package" Architecture)" = "$TARGETARCH" && \
    dpkg-deb --extract "$package" / && \
    test -x "$HILLSTONE_HOME/bin/HillstoneSecureConnect" && \
    test -x "$HILLSTONE_HOME/bin/HillstoneSecureConnectService" && \
    test -x "$HILLSTONE_HOME/bin/HillstoneSecureConnect.sh" && \
    cp "$HILLSTONE_HOME/hillstonesecureconnect.policy" /usr/share/polkit-1/actions/HillstoneSecureConnect.policy && \
    rm -f /tmp/hillstone-amd64.deb /tmp/hillstone-arm64.deb

COPY config/supervisord.conf /etc/supervisor/conf.d/hillstone.conf
COPY scripts/ /usr/local/bin/
RUN chmod 0755 /usr/local/bin/*.sh

EXPOSE 6080 1080
HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
