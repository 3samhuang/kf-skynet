#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "請用 root 或 sudo 執行" >&2
    exit 1
fi

if ! id -u node_exporter &>/dev/null; then
    useradd --system --no-create-home --shell /sbin/nologin node_exporter
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *)       echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name"' | head -1 | cut -d '"' -f4 | sed 's/^v//')

if [ -z "$LATEST_VERSION" ]; then
    echo "無法取得版本號" >&2
    exit 1
fi

echo "Installing node_exporter v${LATEST_VERSION} (${ARCH})"

TARBALL="node_exporter-${LATEST_VERSION}.linux-${ARCH}.tar.gz"
URL="https://github.com/prometheus/node_exporter/releases/download/v${LATEST_VERSION}/${TARBALL}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL "$URL" -o "${TMPDIR}/${TARBALL}"
tar -xzf "${TMPDIR}/${TARBALL}" -C "$TMPDIR"
install -m 0755 -o node_exporter -g node_exporter "${TMPDIR}/node_exporter-${LATEST_VERSION}.linux-${ARCH}/node_exporter" /usr/local/bin/node_exporter

if [ ! -f /etc/sysconfig/node_exporter ]; then
    echo 'OPTIONS="--web.listen-address=:9100"' > /etc/sysconfig/node_exporter
fi

cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
EnvironmentFile=-/etc/sysconfig/node_exporter
ExecStart=/usr/local/bin/node_exporter $OPTIONS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node_exporter
systemctl status node_exporter --no-pager