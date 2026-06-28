### Claude配置傳送日誌

**macOS / Linux (bash)**
```
curl -sSL https://raw.githubusercontent.com/3samhuang/kf-skynet/main/install-claude-telemetry.sh | OTEL_TOKEN=xxxxx bash
```

**Windows (PowerShell)**
```powershell
$env:OTEL_TOKEN="xxxxx"; iex (iwr -useb https://raw.githubusercontent.com/3samhuang/kf-skynet/main/install-claude-telemetry.ps1).Content
```

**macOS / Linux (bash)更新claude settings.json**
```
curl -fsSL https://raw.githubusercontent.com/3samhuang/kf-skynet/main/update-claude-telemetry.sh \
  | OTEL_TOKEN=new-token-xxx bash
```
** 初始化rocky-linux for aws & aliyun
```
curl -fsSL https://raw.githubusercontent.com/3samhuang/kf-skynet/main/rocky-linux-init.sh | sudo bash
```
** 安裝node-exporter
```
curl -sSL https://raw.githubusercontent.com/3samhuang/kf-skynet/main/install-node-exporter.sh | sudo bash
```