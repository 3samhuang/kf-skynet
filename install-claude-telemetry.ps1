#requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Telemetry Setup (Windows / PowerShell)
.DESCRIPTION
    自動將 OpenTelemetry 設定加入 %USERPROFILE%\.claude\settings.json
.EXAMPLE
    $env:OTEL_TOKEN = 'glpat-xxx'
    iex (iwr -useb https://raw.githubusercontent.com/3samhuang/kf-skynet/main/install-claude-telemetry.ps1).Content
.NOTES
    Environment variables:
      OTEL_TOKEN     (required) GitLab/OTLP bearer token
      OTEL_ENDPOINT  (optional) OTLP endpoint URL, defaults to https://kf-opentelemetry.kf-test.com
#>

$ErrorActionPreference = 'Stop'

function info { param($m) Write-Host "[INFO] $m"  -ForegroundColor Blue }
function ok   { param($m) Write-Host "[OK] $m"    -ForegroundColor Green }
function warn { param($m) Write-Host "[WARN] $m"  -ForegroundColor Yellow }
function err  { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }

try {
    # ===== Config =====
    $ClaudeDir    = Join-Path $env:USERPROFILE '.claude'
    $SettingsFile = Join-Path $ClaudeDir 'settings.json'
    $BackupFile   = "$SettingsFile.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    $OtelToken    = $env:OTEL_TOKEN
    $OtelEndpoint = if ($env:OTEL_ENDPOINT) { $env:OTEL_ENDPOINT } else { 'https://kf-opentelemetry.kf-test.com' }

    # ===== Validate input =====
    if ([string]::IsNullOrWhiteSpace($OtelToken)) {
        err '缺少 OTEL_TOKEN 環境變數'
        Write-Host ''
        Write-Host '使用方式：'
        Write-Host '  $env:OTEL_TOKEN = ''glpat-xxx'''
        Write-Host '  iex (iwr -useb <script-url>).Content'
        Write-Host ''
        Write-Host '可選環境變數：'
        Write-Host '  OTEL_TOKEN     必填，OTLP bearer token'
        Write-Host '  OTEL_ENDPOINT  選填，預設 https://kf-opentelemetry.kf-test.com'
        throw 'OTEL_TOKEN not set'
    }

    if ($OtelToken -notmatch '^glpat-') {
        warn 'OTEL_TOKEN 不是 glpat- 開頭，請確認格式是否正確'
    }

    info "使用 endpoint: $OtelEndpoint"

    # ===== Prepare directory =====
    if (-not (Test-Path -LiteralPath $ClaudeDir)) {
        info "建立目錄 $ClaudeDir"
        New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    }

    # ===== Handle settings.json =====
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    if (-not (Test-Path -LiteralPath $SettingsFile)) {
        info 'settings.json 不存在，建立新檔案'
        [System.IO.File]::WriteAllText($SettingsFile, '{}', $utf8NoBom)
    }

    # 驗證現有 JSON 是否合法
    $rawJson = Get-Content -LiteralPath $SettingsFile -Raw
    if ([string]::IsNullOrWhiteSpace($rawJson)) { $rawJson = '{}' }

    try {
        $settings = $rawJson | ConvertFrom-Json
    } catch {
        err "現有的 $SettingsFile 不是合法 JSON，請先手動修復"
        throw
    }

    if ($null -eq $settings) { $settings = [PSCustomObject]@{} }
    if ($settings -is [Array]) {
        err "現有的 $SettingsFile 根層不是 JSON object，請先手動修復"
        throw 'settings.json root must be an object'
    }

    # 備份
    Copy-Item -LiteralPath $SettingsFile -Destination $BackupFile -Force
    ok "已備份至 $BackupFile"

    # ===== Merge env =====
    $newEnv = [ordered]@{
        'CLAUDE_CODE_ENABLE_TELEMETRY' = '1'
        'OTEL_METRICS_EXPORTER'        = 'otlp'
        'OTEL_LOGS_EXPORTER'           = 'otlp'
        'OTEL_EXPORTER_OTLP_PROTOCOL'  = 'http/protobuf'
        'OTEL_EXPORTER_OTLP_ENDPOINT'  = $OtelEndpoint
        'OTEL_EXPORTER_OTLP_HEADERS'   = "Authorization=Bearer $OtelToken"
    }

    if (-not $settings.PSObject.Properties['env']) {
        $settings | Add-Member -NotePropertyName 'env' -NotePropertyValue ([PSCustomObject]@{})
    }

    foreach ($k in $newEnv.Keys) {
        if ($settings.env.PSObject.Properties[$k]) {
            $settings.env.$k = $newEnv[$k]
        } else {
            $settings.env | Add-Member -NotePropertyName $k -NotePropertyValue $newEnv[$k]
        }
    }

    # ===== Write back（先寫 tmp 驗證，再 atomic move）=====
    $tmpFile = "$SettingsFile.tmp"
    $outJson = $settings | ConvertTo-Json -Depth 32

    [System.IO.File]::WriteAllText($tmpFile, $outJson, $utf8NoBom)
    try {
        Get-Content -LiteralPath $tmpFile -Raw | ConvertFrom-Json | Out-Null
    } catch {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
        err '產生的 JSON 不合法，已中止。原始檔案未變動。'
        throw
    }

    Move-Item -LiteralPath $tmpFile -Destination $SettingsFile -Force
    ok "成功更新 $SettingsFile"

    # ===== Show result (mask token) =====
    Write-Host ''
    info '目前的 env 設定（token 已遮罩）：'
    $maskedEnv = $settings.env | ConvertTo-Json -Depth 32 | ConvertFrom-Json
    $maskedEnv.OTEL_EXPORTER_OTLP_HEADERS = 'Authorization=Bearer ***REDACTED***'
    $maskedEnv | ConvertTo-Json -Depth 32

    Write-Host ''
    ok '完成！重新啟動 Claude Code 即可生效。'
    warn "如需還原，請執行：Move-Item -LiteralPath '$BackupFile' -Destination '$SettingsFile' -Force"
} catch {
    err $_.Exception.Message
    return
}
