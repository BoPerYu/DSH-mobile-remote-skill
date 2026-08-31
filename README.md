# dsh-mobile-remote

让 Windows 桌面版 DeepSeek Harness（DSH）在手机上远程访问——Tailscale serve + `trustedHosts` 补丁。
Remote control for the Windows desktop build of DeepSeek Harness (DSH) from your phone: Tailscale serve + a `trustedHosts` patch.

> 解决的问题：官方 README 的 `--trusted-host` + Caddy 方案在**桌面端发行版**上走不通——
> 桌面端没有 `--trusted-host` 参数，且 DSH `/api` 有 Host 头校验（DNS 重绑定防护），
> 手机经 tailnet 域名访问必然 403。本技能用 `connection.trustedHosts` 补丁打通信任墙（核心价值，README 没写的一步）。

## 适配范围（v1）

| ✅ 支持 | ❌ 明确出范围 |
|---|---|
| Windows 桌面端发行版（Deepseek-Harness-Desktop 类 Electron 壳） | CLI 版（`dsh web`，走官方 `--trusted-host` 文档） |
| Tailscale 组网（局域网 / 任意网络） | Tailscale Funnel / cpolar 等公网穿透（v2 计划） |
| 手机浏览器 / PWA / dsh-remote App | LAN IP 直连（桌面端只绑定 127.0.0.1，端口未被监听） |

## 安装

环境要求：**Windows + PowerShell 5.1+**（脚本为 ASCII-only，跨代码页可解析）。建议以 `pwsh -ExecutionPolicy Bypass -File <脚本>` 运行，避免执行策略拦截。

把 `dsh-mobile-remote/` 目录放到以下任一位置：

- 项目级：`<项目根>/.dsh/skills/dsh-mobile-remote/`
- 用户级：`<DSH_HOME>/skills/dsh-mobile-remote/`（`$DSH_HOME` 未设时为 `~/.dsh`）

之后新会话的「可用技能」里会出现 `dsh-mobile-remote`。

## 使用

- 在 DSH 会话中说：「用 dsh-mobile-remote 技能配置手机远程访问」。
- 核心流程：前置确认 → Tailscale 组网（人工）→ serve 确认 → trustedHosts 补丁 → 手机接入 → 自检 → 排查。
- 涉及真实配置修改、进程重启、手机操作时，代理会先征求你的确认。
- 撤销：`scripts/revoke-access.ps1`（移除白名单 + 可选关闭隧道）。

## 与官方方案（dsh-remote README）对比

| 维度 | 本技能（零插件 Tailscale 路线） | 官方 README（`--trusted-host` + Caddy） |
|---|---|---|
| 适用 | 桌面端发行版（已实测） | CLI 版（`dsh web`） |
| 信任机制 | `trustedHosts` 白名单（tailnet 成员） | `--trusted-host` + 可选反代 |
| 鉴权 | 无 token（信任边界 = tailnet 成员） | 依部署方式 |
| dsh-remote-access 插件 | 可选竞争路径：装了插件则补丁步骤可跳过（两者勿混用） | 插件自带 |

## 常见问题（FAQ）

- **手机端功能与桌面端一致吗？** 引擎同（同一 DSH 内核、前端、推理）；分发不同（trustedHosts 配置方式、HMR 禁用、自动重启机制）。功能一致，交互受手机屏幕限制。
- **手机看不了长历史会话？** 已知限制：客户端渲染/大历史加载受限（服务端亦有大历史加载问题），桌面端完整。长会话请在桌面端查看。
- **需要装 dsh-remote-access 插件吗？** 不需要（本技能零插件路线）；若已装，补丁步骤可跳过，但两种 trustedHosts 管理来源勿混用。

## 目录结构

```
dsh-mobile-remote/
├── SKILL.md                  # 技能正文：阶段 0-6 + 安全红线 + 撤销 + 版本自检
├── references/
│   ├── concepts.md           # 原理：403 机制 / trustedHosts / 无认证模型 / 版本风险
│   ├── env-check.md          # 环境检测三事实 + 双实例判定
│   ├── desktop-app.md        # 桌面版补丁（A/B 取舍）+ 重启机制 + 撤销
│   └── web-cli.md            # CLI 版说明（v1 不做）
├── scripts/
│   ├── env-check.ps1         # 三事实检查（只读）
│   ├── check-tailscale.ps1   # Tailscale 隧道检查（只读，含 serve/域名一致性）
│   ├── serve-dsh.ps1         # 启 serve 隧道（幂等）
│   ├── patch-trusted-host.ps1# 打补丁（备份+原子写入+离线验证+失败自愈回滚）
│   ├── revoke-access.ps1     # 撤销访问（备份+写后验证+可选关隧道）
│   ├── restart-dshd.ps1      # 重启 dshd-web（停进程+轮询等待拉起）
│   └── verify-access.ps1     # 端到端验证（HTTPS 200 + 可选 -ApiProbe 围栏探针）
├── troubleshooting.md        # 排查表
├── README.md
└── LICENSE
```

## 安全

- 本方案**无配对码/token**：信任边界 = tailnet 成员，任何能加入该 tailnet 的设备都可控制 DSH——设置前请知悉。
- 高危接口（settings/credentials/MCP）仍在官方"仅本机"围栏内，本技能不扩大围栏。
- 撤销 = 移除 trustedHosts + 关 serve（唯一断电开关）。

## 已知限制 / 已踩的坑（差异化价值）

- 桌面端绑定 `127.0.0.1`：LAN IP 直连不可用（非 403，是端口未被监听）→ 统一走 tailnet 域名。
- `!!js` 流式序列会让 DSH 整个起不来（js-yaml 崩溃）→ 用纯静态 YAML（A 方案）。
- dsh-mobile（客户端插件型）在桌面端不可用（前端模块表固定）；独立客户端（dsh-remote App / PWA）可用。
- 手机必须开启 Tailscale「Use Tailscale DNS」（必需，一次性）；浏览器安全 DNS（DoH）会绕路导致慢/无法解析。
- serve 配置重启后持久（已实测），无需每次重开。

## 许可

MIT。参考与署名：Tailscale、chrome-devtools-mcp、saya-ch、SCSpotato（仅参考思路，代码为原创）。
