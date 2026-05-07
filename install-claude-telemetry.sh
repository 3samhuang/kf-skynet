#!/usr/bin/env bash
#
# Claude Code Telemetry Setup
# 自動將 OpenTelemetry 設定加入 ~/.claude/settings.json
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/<branch>/install-claude-telemetry.sh | OTEL_TOKEN=glpat-xxx bash
#
# Environment variables:
#   OTEL_TOKEN     (required) GitLab/OTLP bearer token
#   OTEL_ENDPOINT  (optional) OTLP endpoint URL, defaults to https://kf-opentelemetry.kf-test.com
#

set -euo pipefail

# ===== Colors =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ===== Config =====
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
BACKUP_FILE="${SETTINGS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"

# 從環境變數讀取，提供預設值
OTEL_TOKEN="${OTEL_TOKEN:-}"
OTEL_ENDPOINT="${OTEL_ENDPOINT:-https://kf-opentelemetry.kf-test.com}"

# ===== Validate input =====
if [[ -z "$OTEL_TOKEN" ]]; then
    error "缺少 OTEL_TOKEN 環境變數"
    echo ""
    echo "使用方式："
    echo "  curl -fsSL <script-url> | OTEL_TOKEN=glpat-xxx bash"
    echo ""
    echo "可選環境變數："
    echo "  OTEL_TOKEN     必填，OTLP bearer token"
    echo "  OTEL_ENDPOINT  選填，預設 https://kf-opentelemetry.kf-test.com"
    exit 1
fi

# 簡單檢查 token 格式（GitLab PAT 開頭多半是 glpat-）
if [[ ! "$OTEL_TOKEN" =~ ^glpat- ]]; then
    warn "OTEL_TOKEN 不是 glpat- 開頭，請確認格式是否正確"
fi

info "使用 endpoint: $OTEL_ENDPOINT"

# ===== Pre-checks =====
info "檢查相依套件..."
if ! command -v jq >/dev/null 2>&1; then
    error "找不到 jq，請先安裝："
    echo "  macOS:  brew install jq"
    echo "  Ubuntu: sudo apt-get install -y jq"
    echo "  RHEL:   sudo yum install -y jq"
    exit 1
fi
ok "jq 已安裝"

# ===== Build env JSON dynamically =====
# 用 jq 安全組合，避免 token 內含特殊字元造成 JSON 損壞
ENV_JSON="$(jq -n \
    --arg endpoint "$OTEL_ENDPOINT" \
    --arg token "$OTEL_TOKEN" \
    '{
        "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
        "OTEL_METRICS_EXPORTER": "otlp",
        "OTEL_LOGS_EXPORTER": "otlp",
        "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
        "OTEL_EXPORTER_OTLP_ENDPOINT": $endpoint,
        "OTEL_EXPORTER_OTLP_HEADERS": ("Authorization=Bearer " + $token)
    }')"

# ===== Prepare directory =====
if [[ ! -d "$CLAUDE_DIR" ]]; then
    info "建立目錄 $CLAUDE_DIR"
    mkdir -p "$CLAUDE_DIR"
fi

# ===== Handle settings.json =====
if [[ ! -f "$SETTINGS_FILE" ]]; then
    info "settings.json 不存在，建立新檔案"
    echo '{}' > "$SETTINGS_FILE"
fi

# 驗證現有 JSON 是否合法
if ! jq empty "$SETTINGS_FILE" >/dev/null 2>&1; then
    error "現有的 $SETTINGS_FILE 不是合法 JSON，請先手動修復"
    exit 1
fi

# 備份
cp "$SETTINGS_FILE" "$BACKUP_FILE"
ok "已備份至 $BACKUP_FILE"

# ===== Merge env into settings.json =====
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

jq --argjson newenv "$ENV_JSON" '
    .env = ((.env // {}) + $newenv)
' "$SETTINGS_FILE" > "$TMP_FILE"

# 驗證結果
if ! jq empty "$TMP_FILE" >/dev/null 2>&1; then
    error "產生的 JSON 不合法，已中止。原始檔案未變動。"
    exit 1
fi

mv "$TMP_FILE" "$SETTINGS_FILE"
trap - EXIT

ok "成功更新 $SETTINGS_FILE"

# ===== Show result (mask token) =====
echo ""
info "目前的 env 設定（token 已遮罩）："
jq '.env | .OTEL_EXPORTER_OTLP_HEADERS = "Authorization=Bearer ***REDACTED***"' "$SETTINGS_FILE"

echo ""
ok "完成！重新啟動 Claude Code 即可生效。"
warn "如需還原，請執行：mv \"$BACKUP_FILE\" \"$SETTINGS_FILE\""
