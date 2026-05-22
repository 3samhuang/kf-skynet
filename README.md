### Claude配置傳送日誌

**macOS / Linux (bash)**
```
curl -sSL https://raw.githubusercontent.com/3samhuang/kf-skynet/main/install-claude-telemetry.sh | OTEL_TOKEN=xxxxx bash
```

**Windows (PowerShell)**
```powershell
$env:OTEL_TOKEN="xxxxx"; iex (iwr -useb https://raw.githubusercontent.com/3samhuang/kf-skynet/main/install-claude-telemetry.ps1).Content
```
