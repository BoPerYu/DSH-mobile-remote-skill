# 概念与原理（可迁移，与发行版无关）

## 403 根因：Host 头校验（DNS 重绑定防护）

- DSH 的 `/api` 拒绝"非本机 Host 头"的请求（403 forbidden）——防 DNS 重绑定攻击的**安全设计，不是 bug**。
- 手机经 tailnet 域名访问时，Host 头是域名 → 必然触发。
- 解法：`connection` 插件的 `trustedHosts` 白名单（schema：`z.array(String)`）。
- 官方代码注释："Phone remote shares this Host"——目录选择器官方固定为网页版以支持手机。

## 运行时派生 trustedHosts 的构成（resolveLanTrust）

- `@deepseek-ai/dsh-web-app` 的 `resolveLanTrust(bindHost, extra)`：
  - 服务器绑定 `0.0.0.0` 时：自动加入所有非内网 IPv4（局域网直连用）；
  - 再拼接显式 `--trusted-host` 条目。
- 桌面版绑定 `127.0.0.1` → 派生集为空 → **静态替换零损失**（交接文档 4.12）。
- `--dump-config` 输出里基础层显示为 `!!js ctx.webStartup.trustedHosts`（启动时才求值，dump 时看不到具体值）。

## 无认证安全模型（A2）

- 本方案（Tailscale serve + trustedHosts）：信任边界 = **tailnet 成员**，无配对码/token。
- 对比 dsh-remote 官方模型：配对码 + Bearer token + 吊销/审计。
- 取舍：免配对、免 Caddy；代价是"tailnet 成员即全权"——**设置前必须告知用户**。
- 撤销 = 移除 trustedHosts + 关 serve（唯一断电开关，无 token 可轮换）。

## 版本风险（A7）

- trustedHosts 写法有版本先例：dsh-remote-access 插件 v2.3.0（整体替换，导致 `--trusted-host` 静默失效）→ v2.4.1（`!!js` 标量合并 + 自动迁移清理）。
- 本技能补丁模板标注适用版本；升级 DSH 后跑 `scripts/env-check.ps1` 事实 3 比对 schema 是否仍为字符串数组。
