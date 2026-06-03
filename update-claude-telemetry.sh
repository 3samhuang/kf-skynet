#!/usr/bin/env bash
#
# update-claude-telemetry-token.sh
#
# 更新 ~/.claude/settings.json 裡 env.OTEL_EXPORTER_OTLP_HEADERS 的 token。
# 只覆蓋 token，其他設定（model、permissions、其他 env 變數）完全不動。
#
# 用法：
#   curl -fsSL <script-url> | OTEL_TOKEN=glpat-新token bash
#
set -euo pipefail

SETTINGS_FILE="${HOME}/.claude/settings.json"

# ---- 1. 檢查 token ----
if [[ -z "${OTEL_TOKEN:-}" ]]; then
  echo "錯誤：未提供 OTEL_TOKEN" >&2
  echo "用法： curl -fsSL <script-url> | OTEL_TOKEN=glpat-xxxxx bash" >&2
  exit 1
fi

case "${OTEL_TOKEN}" in
  glpat-*) ;;
  *) echo "警告：token 不是以 glpat- 開頭，仍會繼續寫入。" >&2 ;;
esac

# ---- 2. 檢查依賴 ----
if ! command -v jq >/dev/null 2>&1; then
  echo "錯誤：需要 jq，請先安裝：" >&2
  echo "  macOS : brew install jq" >&2
  echo "  Ubuntu: sudo apt-get install -y jq" >&2
  exit 1
fi

# ---- 3. 檢查檔案存在且 JSON 合法 ----
if [[ ! -f "${SETTINGS_FILE}" ]]; then
  echo "錯誤：找不到 ${SETTINGS_FILE}" >&2
  echo "看起來還沒裝過 telemetry，請先跑安裝腳本 install-claude-telemetry.sh" >&2
  exit 1
fi

if ! jq empty "${SETTINGS_FILE}" >/dev/null 2>&1; then
  echo "錯誤：${SETTINGS_FILE} 不是合法 JSON，已中止（未做任何修改）。" >&2
  exit 1
fi

# ---- 4. 備份 ----
BACKUP="${SETTINGS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
cp "${SETTINGS_FILE}" "${BACKUP}"

# ---- 5. 用 jq 覆蓋 token（不碰其他任何欄位）----
NEW_HEADER="Authorization=Bearer ${OTEL_TOKEN}"
TMP="$(mktemp)"

jq --arg h "${NEW_HEADER}" \
   '.env."OTEL_EXPORTER_OTLP_HEADERS" = $h' \
   "${SETTINGS_FILE}" > "${TMP}"

# ---- 6. 驗證產生的 JSON 後原子寫入 ----
if ! jq empty "${TMP}" >/dev/null 2>&1; then
  echo "錯誤：產生的 JSON 不合法，已中止。原檔未變動，備份在 ${BACKUP}" >&2
  rm -f "${TMP}"
  exit 1
fi

mv "${TMP}" "${SETTINGS_FILE}"

# ---- 7. 完成（token 遮罩輸出）----
MASKED="${OTEL_TOKEN:0:10}***REDACTED***"
echo "✅ Token 已更新"
echo "   檔案： ${SETTINGS_FILE}"
echo "   備份： ${BACKUP}"
echo "   新 token： ${MASKED}"
