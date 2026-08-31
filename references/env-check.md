# 环境检测（env-check 三事实 + 双实例判定）

## 三事实（scripts/env-check.ps1，只读）

1. **3080 属主**：`Get-NetTCPConnection -LocalPort 3080 -State Listen` → `OwningProcess` → `Get-Process -Id <PID>` 看路径。
2. **dshd-web PID**：读 `<数据根>\dshd-web.pid`（数据根 = `$env:DSH_HOME` 的上级），进程存活且与 3080 属主一致。
3. **补丁在位**：`node <数据根>\runtime\<最新版本>\apps\cli\lib\bin.js --profile web --dump-config`，输出中同时含 `trustedHosts`、`patched by ...cordis.patch.yml`、目标域名。

## 手动等价命令

```powershell
# 事实1+2
Get-NetTCPConnection -LocalPort 3080 -State Listen | Select LocalAddress,OwningProcess
Get-Content "$(Split-Path $env:DSH_HOME -Parent)\dshd-web.pid"
# 事实3（输出约 18KB，不启动服务）
node "<数据根>\runtime\<最新版本>\apps\cli\lib\bin.js" --profile web --dump-config
```

## 双实例判定（A3）

- 网页版（`dsh web`）与桌面版是**独立实例、配置不互通**；3080 同一时刻只有一个进程在听。
- 属主路径含 `Deepseek-Harness-Desktop\resources\node.exe` → 桌面版实例；否则可能是 CLI/其他。
- 「网页版通、桌面版不通」= 先查谁占 3080，再查桌面 profile 有无补丁。

## 动态 runtime 路径

- `runtime\` 目录随版本增加（如 0.2.7 → 0.3.x）；脚本按 `^\d+\.\d+\.\d+` 过滤后取最新版本。
- **勿写死版本号**；升级后路径变化是正常现象，env-check 自动适配。
