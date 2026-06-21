#!/usr/bin/env bash
#
# Rocky Linux 初始化腳本 (Rocky 8 / 9 通用)
# 用途: 全新機器基礎初始化 + Docker + 常用工具
# 適用平台: AWS EC2 / Aliyun ECS (其他平台會中止)
#
# 遠程執行:
#   sudo bash <(curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/init.sh)
#
# 可用環境變數覆蓋:
#   ROOT_PUBKEY  自訂 root SSH 公鑰
#   TIMEZONE     自訂時區 (預設 Asia/Taipei)
#   FORCE_CLOUD  強制指定平台 aws|aliyun (略過自動偵測, 方便測試)
#
set -euo pipefail

# ====== 可調整參數 (可由環境變數覆蓋) ======
TIMEZONE="${TIMEZONE:-Asia/Taipei}"
ROOT_PUBKEY="${ROOT_PUBKEY:-ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDWuZZCkYdD+tt6/9s6Cz5gEKiF9XKi1VlV1syGiiUaenA9Zs6UVgzbdOZ171gAHq4WpW/AdCgupXxgXVoVYz7tBkyfFIm49zSsqFTu8ej3sfP3i0fFMUQF8R4ErzSoVMEuzPzjeDMPx2e/s9bV9TDVcAL5R7FLH4Dco5i3w12rammj0yubfOnHRPdABg2IngiGm3j54b8QGQC4blznSnuMrEjIaJ+chCFu8yWJMNHfoPwxxgE2qWs3WIMwxL8VAjTNu77on8UnZwuqj1t5BfjqkgpVQPwY+tgWMmUL2XXLIk36tX64+cD3fRf+qE+IcmHpSW/ujtrfDAhewJIsQR6KQKZQJCA226bYZn8/PPcM2v724HxGNYJ3gibZX4a2HVTS70JzyDNzaweDz6+erpg9gwYJ7uqJBY5ZKLWt8Js6RpnjFLRWpVfYayZRHI88SKW6+WQtFN/4OtsClTbYU9M3HqXo/dJds+2VNY5J+ObSpC8dXQLFQDhho6KtJqOtHqSFFEsIpkJfMG441oL9Ejf+K3BjXlg1nbWY9LaYe1IhzFBlIB5VzaXnlRKkXDO1SON+KpFvuURxHApOQXLuUmKVzBUOdZ0e2JweGFuFgcWFDI3sfV9at/MroatmVozx6X7C9zc/oqx035fA9dSBtTa0j5/qYFplzmXEXokFoPES9Q== noname}"

log()  { echo -e "\033[1;32m[$(date '+%F %T')] $*\033[0m"; }
err()  { echo -e "\033[1;31m[$(date '+%F %T')] $*\033[0m" >&2; }

# ====== 雲平台偵測 ======
# 回傳: aws / aliyun / unknown
detect_cloud() {
  # 允許用 FORCE_CLOUD 手動覆蓋 (方便測試)
  if [[ -n "${FORCE_CLOUD:-}" ]]; then
    echo "${FORCE_CLOUD}"; return
  fi

  local vendor=""

  # 先用 DMI/SMBIOS 判斷 (最快, 不需網路)
  if [[ -r /sys/class/dmi/id/sys_vendor ]]; then
    vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  fi
  if echo "${vendor}" | grep -qi "alibaba"; then echo "aliyun"; return; fi
  if echo "${vendor}" | grep -qiE "amazon|ec2"; then echo "aws"; return; fi

  # 後備: metadata service 確認
  local token aws_check
  token="$(curl -s --max-time 2 -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)"
  if [[ -n "${token}" ]]; then
    aws_check="$(curl -s --max-time 2 -H "X-aws-ec2-metadata-token: ${token}" \
      "http://169.254.169.254/latest/meta-data/instance-id" 2>/dev/null || true)"
    [[ -n "${aws_check}" ]] && { echo "aws"; return; }
  fi

  if curl -s --max-time 2 "http://100.100.100.200/latest/meta-data/instance-id" 2>/dev/null | grep -q .; then
    echo "aliyun"; return
  fi

  echo "unknown"
}

main() {
  if [[ $EUID -ne 0 ]]; then err "請以 root 執行"; exit 1; fi

  # ====== 0. 雲平台偵測 ======
  local CLOUD
  CLOUD="$(detect_cloud)"
  log "偵測到雲平台: ${CLOUD}"

  if [[ "${CLOUD}" != "aws" && "${CLOUD}" != "aliyun" ]]; then
    err "[錯誤] 無法辨識的平台 (${CLOUD})。本腳本僅適用於 Aliyun ECS & AWS EC2 的 Rocky Linux。"
    exit 1
  fi

  # ====== 1. 系統更新 ======
  log "更新系統套件..."
  dnf update -y
  dnf install -y epel-release

  # ====== 2. 常用工具安裝 ======
  log "安裝常用工具..."
  dnf install -y \
    traceroute nmap-ncat gcc wget tcpdump net-tools htop iftop \
    psmisc bind-utils vim screen lrzsz rsync unzip \
    curl tar bash-completion git jq lsof chrony

  # ====== 3. 時區設定 ======
  log "設定時區為 ${TIMEZONE}..."
  timedatectl set-timezone "${TIMEZONE}"

  # ====== 4. 時間同步 (chrony) ======
  log "啟用時間同步..."
  systemctl enable --now chronyd
  timedatectl set-ntp true

  # ====== 5. SSH: root pubkey + 允許 root 登入 ======
  log "設定 root SSH 金鑰與登入..."
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  if ! grep -qF "${ROOT_PUBKEY}" /root/.ssh/authorized_keys 2>/dev/null; then
    echo "${ROOT_PUBKEY}" >> /root/.ssh/authorized_keys
  fi
  chmod 600 /root/.ssh/authorized_keys

  local SSHD_CONF="/etc/ssh/sshd_config.d/99-init.conf"
  cat > "${SSHD_CONF}" <<'EOF'
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
EOF
  sshd -t && systemctl restart sshd

  # ====== 6. Docker 安裝 ======
  log "安裝 Docker CE..."
  dnf install -y dnf-plugins-core
  dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # 依雲平台決定 Docker DNS 設定
  local DOCKER_DNS=""
  case "${CLOUD}" in
    aws)    DOCKER_DNS='"dns": ["169.254.169.253", "8.8.8.8", "1.1.1.1"],' ;;
    aliyun) DOCKER_DNS='"dns": ["100.100.2.136", "8.8.8.8", "1.1.1.1"],' ;;
  esac

  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<EOF
{
  ${DOCKER_DNS}
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m", "max-file": "3" },
  "live-restore": true
}
EOF

  # 驗證 JSON 合法性
  jq empty /etc/docker/daemon.json || { err "daemon.json 格式錯誤!"; exit 1; }

  systemctl enable --now docker
  systemctl restart docker

  # ====== 7. 防火牆 — 不使用 firewalld, 改用雲平台安全組 ======
  log "停用 firewalld, 改由雲平台安全組管理..."
  systemctl disable --now firewalld 2>/dev/null || true

  # ====== 8. SELinux — 僅 AWS EC2 改為 permissive; Aliyun 不動 ======
  if [[ "${CLOUD}" == "aws" ]]; then
    log "AWS EC2: 將 SELinux 設為 permissive..."
    setenforce 0 2>/dev/null || true
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
  else
    log "SELinux 不更動, 目前狀態: $(getenforce)"
  fi

  # ====== 9. 系統限制 / kernel 參數優化 ======
  log "調整系統限制與 kernel 參數..."
  cat > /etc/security/limits.d/99-init.conf <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc  65535
* hard nproc  65535
EOF

  cat > /etc/sysctl.d/99-init.conf <<'EOF'
net.ipv4.ip_forward = 1
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
vm.swappiness = 10
vm.max_map_count = 262144
fs.file-max = 2097152
EOF
  sysctl --system

  # ====== 10. 基礎清理 (選用) ======
  log "停用不必要的服務..."
  systemctl disable --now postfix 2>/dev/null || true

  log "初始化完成! 雲平台=${CLOUD}, 請重新登入以套用 limits 設定。"
  log "Docker 版本: $(docker --version)"
}

main "$@"