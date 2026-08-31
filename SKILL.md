---
name: dsh-mobile-remote
description: 让 Windows 桌面版 DSH 支持手机远程访问（Tailscale serve + trustedHosts 补丁）。遇到 403 forbidden、Host 头校验、tailscale serve、手机连不上 DSH、Use Tailscale DNS 时使用。
---

# DSH 手机远程访问（桌面端发行版）

> **v1 适配范围**：桌面端发行版（Deepseek-Harness-Desktop 类 Electron 壳）+ Tailscale 组网。
> CLI 版（`dsh web`）、Tailscale Funnel / cpolar 公网、LAN IP 直连 **不在 v1**——遇到这些场景，明确告知用户超出本技能范围，指向官方文档或仓库 README。
> 读者定位：PC 端 DSH 会话中的代理。手机端动作由用户执行，本技能负责检查配置、生成/校验补丁、给出用户步骤。
> 每个阶段完成后，用一句话向用户汇报结果；任何修改真实配置、重启进程、手机操作之前，必须先向用户确认。
> 深入原理见 `references/`（concepts / env-check / desktop-app / web-cli）；故障排查见 `troubleshooting.md`。

## 一、必需前置（不满足即停）

1. DSH 桌面版运行中，且 `$env:DSH_HOME` 指向桌面版 dsh-home（`echo $env:DSH_HOME` 验证）
2. 手机与电脑登录同一 Tailscale 账号（同一 tailnet）
3. 手机 Tailscale「Use Tailscale DNS」已开启（必需、一次性；不开启时域名解析失败，手机报 `NAME_NOT_RESOLVED` -105）

> 缺任何一项：**停止**，先处理前置，不要继续打补丁。

## 二、核心流程（阶段 0→6）

### 阶段 0：前置确认
- 依次核对"必需前置"三条；涉及手机的三条**问用户确认**，不要替用户假设。

### 阶段 1：Tailscale 组网（人工步骤，只检查不代做）
- 安装 / 登录 / 手机入网是**人工步骤**（外部依赖，本技能不打包、不代做）。
- 可运行 `scripts/check-tailscale.ps1`（只读）检查 CLI 与在线状态。
- 取域名：`(tailscale status --json | ConvertFrom-Json).Self.DNSName`（去掉末尾点），形如 `desktop-xxxx.tailxxx.ts.net`。

### 阶段 2：确认 serve 隧道
- 运行 `scripts/check-tailscale.ps1 -TailnetDomain <域名>`（只读）：
  - serve 配置在 → 记录 URL `https://<域名>/`，继续；
  - 缺失 → 请用户确认后运行 `scripts/serve-dsh.ps1`（幂等，只需一次；serve 配置重启后持久，已实测）。
- 涉及真实状态变更的命令（serve 开启）也先经用户确认。

### 阶段 3：trustedHosts 补丁（核心；改真实配置前必须获用户确认）
> 若检测到已安装 `dsh-remote-access` 插件：其 trustedHosts 管理与本补丁同源，**两种来源勿混用**（见 `references/desktop-app.md`）；此时补丁步骤可跳过，直接进入阶段 4。
1. 运行 `scripts/env-check.ps1 -TailnetDomain <域名>`（只读）：
   - 事实 1/2 必须 PASS（3080 属主 = 桌面版实例；若属主不是桌面版，见 troubleshooting「双实例」）；
   - 事实 3 PASS（补丁已在）→ 跳到阶段 4；
   - 事实 3 FAIL（补丁缺失）→ 继续下面。
2. **向用户确认**：「将修改 `<DSH_HOME>\profiles\web\cordis.patch.yml`（脚本自动备份），随后重启 dshd-web（GUI 闪断 1-3 秒自动恢复）。确认执行？」
3. 执行 `scripts/patch-trusted-host.ps1 -TailnetDomain <域名>`（自动：备份 → 写入 → `--dump-config` 离线验证 → 失败自动回滚）。
4. 重启 dshd-web：执行 `scripts/restart-dshd.ps1`（自动停进程并轮询等待 `harnessAutoRestart` 拉起，最多 25 秒）。⚠️ 若从 DSH 会话内执行，该脚本会中断当前会话宿主 1-3 秒（实测正常，见 troubleshooting）。
5. 重跑 `scripts/env-check.ps1 -TailnetDomain <域名>`，确认事实 3 PASS。

### 阶段 4：手机接入（涉及手机，问用户确认）
- 手机操作（用户执行）：打开 URL → 浏览器 / PWA / dsh-remote App → 选择工作区（每浏览器需选一次）→ 使用。
- 提示已知限制：**长历史会话手机端显示受限**（客户端渲染限制，桌面端完整；见 troubleshooting）。
- 用户确认手机可正常访问（页面 200、会话可见）后，流程继续。

### 阶段 5：自检清单
- 运行 `scripts/verify-access.ps1 -TailnetDomain <域名>`（HTTPS 200 + 补丁在位）。
- 逐项确认：serve status 非空 / HTTPS 200 / 会话可见 / 手机在线 / 补丁持久性（升级 DSH 后重跑）。

### 阶段 6：排查
- 见 `troubleshooting.md`。常见场景：403（补丁缺失或域名不匹配）、`NAME_NOT_RESOLVED` -105（手机 DNS）、Edge 慢（DoH 绕路）、双实例（3080 属主不是桌面版）、长历史（客户端限制）。

## 三、撤销访问（A9：必须与设置成对出现）

- 获用户确认后执行 `scripts/revoke-access.ps1`（可选 `-AlsoStopServe` 同时关隧道），随后 `scripts/restart-dshd.ps1` 重启，手机端应变 403。
- 本方案**无 token 可轮换**——撤销是唯一断电开关。设置完成后应把撤销方法告知用户。

## 四、安全红线（设置前必须告知用户）

1. **无认证模型**：信任边界 = tailnet 成员，无配对码/token。任何能加入该 tailnet 的设备都可控制 DSH。执行补丁前必须向用户说明此风险。
2. **远程 = 桌面会话权限**：手机端批准即桌面全权；审查严格度（只读 / 工作区可写 / 完全访问）与桌面会话一致。
3. 补丁只加 `trustedHosts`；settings/credentials/MCP 等高危接口仍在官方"仅本机"围栏内——**不要试图扩大围栏**。
4. 凭据（API Key/token）绝不写入本技能任何文件；走环境变量或 DSH 凭据管理。
5. 所有真实配置修改、进程重启、手机操作，一律先向用户确认。

## 五、版本自检（适配性）

- 本技能基于 DSH 0.2.x 实测。运行前确认：`$env:DSH_HOME` 布局存在；`scripts/env-check.ps1` 会**动态发现最新 `runtime\<版本>\`**，勿写死版本号。
- 升级 DSH 后：重跑 env-check 事实 3（补丁是否仍在、`trustedHosts` schema 是否仍为字符串数组）；异常见 troubleshooting「版本漂移」。
