# 桌面版实现（cordis.patch.yml 补丁 + 重启）

## 补丁位置与格式

- 文件：`<DSH_HOME>\profiles\web\cordis.patch.yml`（web profile 的补丁清单）。
- **静态替换（A 方案，v1 默认，适用于 DSH 0.2.x / `trustedHosts: z.array(String)`）**：

```yaml
# --- dsh-mobile-remote-begin ---
- id: connection
  config:
    trustedHosts:
      - <机器名>.<tailnet>.ts.net
# --- dsh-mobile-remote-end ---
```

- **`!!js` 标量合并（B 方案，仅 CLI / 0.0.0.0 绑定场景）**：`!!js '[...ctx.webRuntime.trustedHosts, "域名"]'`
  - 语法底线：`!!js` 只能接 YAML **标量**；流式序列（`!!js ['...', ...]`）会让 js-yaml 解析崩溃 → **整个 DSH 起不来**（实测）。
  - 收益：保留运行时派生条目（LAN/`--trusted-host`）；代价：耦合内部服务名，版本易碎。
- **取舍结论（2026-08-31）**：桌面版绑定 127.0.0.1 → 派生集为空 → A 零损失，为默认；B 留给未来 CLI/0.0.0.0 场景。

## 与 dsh-remote-access 插件的关系（A6）

- 插件 v2.4.1 用 `!!js` 标量合并管理**同一** `trustedHosts`；**装了插件则本技能补丁步骤可跳过**。
- 警告：两种来源**不要混用**（v2.3.0 整体替换曾静默清掉 `--trusted-host` 条目，后废弃并自动迁移）。

## 重启机制（HMR 被官方禁用）

- web profile 的 HMR 被禁用（`- id: hmr, disabled: true`）→ 改补丁后**必须重启** dshd-web。
- 桌面端 `harnessAutoRestart: true`：杀 `<数据根>\dshd-web.pid` 指向的进程 → 1-3 秒自动拉起（最多 3 次）。
- 重启后验证：`scripts/env-check.ps1` 事实 3 / 手机 200。

## 撤销（A9）

- `scripts/revoke-access.ps1`（备份先行；可选 `-AlsoStopServe` 同时关隧道）→ 重启 dshd-web → 手机应变 403。
- 无 token 可轮换：撤销 = 唯一断电开关，设置完成后务必告知用户。
