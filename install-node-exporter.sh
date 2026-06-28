  #!/bin/bash
  set -e

  if ! id -u node_exporter &>/dev/null; then
      sudo useradd --system --shell /bin/false node_exporter || echo "Failed to add user"
  fi

  ARCH=$(uname -m)
  case "$ARCH" in
      x86_64)  ARCH="amd64" ;;
      aarch64) ARCH="arm64" ;;
      *)       echo "Unsupported arch: $ARCH"; exit 1 ;;
  esac

  LATEST_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest \
      | grep "tag_name" | awk '{print $2}' | tr -d '",' | sed 's/^v//')

  echo "Installing node_exporter v${LATEST_VERSION} (${ARCH})"

  curl -sSL "https://github.com/prometheus/node_exporter/releases/download/v${LATEST_VERSION}/node_exporter-${LATEST_VERSION}.linux-${ARCH}.tar.gz" | \
    sudo tar -xz -C /usr/local/bin --strip-components=1 \
    "node_exporter-${LATEST_VERSION}.linux-${ARCH}/node_exporter"

  sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

  # 注意：用 <<'EOF' 防止 $OPTIONS 被 bash 展開
  sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
  [Unit]
  Description=Node Exporter
  After=network.target

  [Service]
  User=node_exporter
  Group=node_exporter
  Environment=OPTIONS=
  EnvironmentFile=-/etc/sysconfig/node_exporter
  ExecStart=/usr/local/bin/node_exporter $OPTIONS
  Restart=on-failure
  RestartSec=5

  [Install]
  WantedBy=multi-user.target
  EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now node_exporter
  sudo systemctl status node_exporter