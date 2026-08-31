# 排查表（通用层，可跨引擎）

| 症状 | 根因 | 处置 |
|---|---|---|
| 手机访问 403 forbidden | trustedHosts 缺域名 / 域名不匹配 / 补丁未生效 | `scripts/env-check.ps1` 事实 3；重打补丁；确认域名与 serve URL 一致 |
| 整个 DSH 起不来 | 补丁用了 `!!js` 流式序列（js-yaml 崩溃） | 恢复备份 `cordis.patch.yml.bak-*`；改纯静态 YAML（A 方案） |
| 手机 `NAME_NOT_RESOLVED` (-105) | MagicDNS 未生效（VPN 挂起 / 浏览器 DoH 绕路） | 手机开「Use Tailscale DNS」/ 强停重开 / 换网络 |
| 手机访问慢 | Edge 安全 DNS（DoH）绕过 VPN DNS / relay 中继 | 关 Edge「使用安全的 DNS」；同 Wi-Fi 恢复 direct（`tailscale status` 看 direct/relay） |
| 网页版通、桌面版不通 | 3080 被 CLI 实例占用；桌面 profile 无补丁 | 查 3080 属主（`Get-NetTCPConnection`）；确认桌面实例在服务 |
| 手机能进但长历史不显示 | 客户端渲染/大历史加载限制（服务端 [deepseek-harness #1550](https://github.com/deepseek-ai/deepseek-harness/discussions/1550) 同源问题） | 桌面端查看；README FAQ「已知限制」 |
| 补丁打了没生效 | HMR 禁用、未重启 | 杀 dshd-web（PID 文件）等自动重启，再验 |
| 升级 DSH 后手机 403 | 补丁被覆盖 / schema 变化 | 重跑 env-check 事实 3；重打补丁 |
| 执行 `restart-dshd.ps1` 时当前会话被中断 | 脚本杀掉的是承载当前会话的 dshd-web（预期副作用，1-3s 自动恢复） | 重启前后保存状态（交接文档/备份）；等待自动拉起后重跑 env-check |
| GitHub 下载超时 | release CDN 不稳定 | 手机直下或镜像（ghfast.top / gh-proxy.com） |

## 变体边界（dsh-mobile）

- 桌面版前端 `__DSH_BOOT__` 模块表固定 → **客户端插件型**（dsh-mobile）不可用；
- **独立客户端型**（dsh-remote App / 浏览器 PWA）可用。
