# 隐私说明（Privacy）

Tokenitor 是一个**纯本地**的 macOS 菜单栏工具。它不含任何自有服务器,**不向开发者或任何第三方上传你的信息**。所有处理都在你本机完成。

## 一句话总结

读取你本机已有的 AI 工具用量/凭证文件 → 在本地展示 → 把少量统计数字落盘到 `~/.tokenitor/`。仅此而已。**不读取、不存储你的对话内容(prompt / 回复)。**

## 存了哪些数据、在哪、多久

| 数据 | 位置 | 格式 | 含个人身份信息? | 保留 |
|---|---|---|---|---|
| Token 用量统计(按工具/模型的数量、估算成本) | `~/.tokenitor/token-history.json` | 明文 JSON | 否,仅数字 | 约 70 天滚动 |
| 用量百分比缓存 | `~/.tokenitor/claude-cache.json` | 明文 JSON | 否,仅百分比 | 覆盖式,失效清理 |
| Claude 续期后 OAuth 凭证 | **macOS 钥匙串**(条目 `com.tokenitor.app`) | 系统加密存储(非明文) | **是**(access/refresh token 可关联你的 Anthropic 账号) | 直到失效/手动清除 |
| 调试转储(需你手动开启) | `~/.tokenitor/debug/*.json` | 明文 JSON | 可能(含订阅计划名等账户级字段) | 手动清除 |
| 启动/运行日志 | `~/.tokenitor/launch.log` | 纯文本 | 否,仅技术事件 | 追加式 |

**只读、不复制**的数据(不进入 `~/.tokenitor/`):各 AI 工具的本地会话文件,如 `~/.claude/projects/`、`~/.codex/sessions/`、`~/.gemini/`、OpenCode 的 `opencode.db`。Tokenitor 只从中读取 token 计数/用量字段,不保存其内容。

## 网络行为

联网只发生在「用量页」且对应工具开启时,**只直连各厂商官方域名**读取你自己的用量:

- `api.anthropic.com`(Claude)、`api.github.com`(Copilot)。
- Codex / Gemini / OpenCode 以及所有 Token 页数据**完全本地、零联网**。

凭证只用于向上述官方域名证明「这是你本人」,不发往别处。

## 关于非官方端点(重要)

Claude、Copilot 两项用量走的是各厂商的**社区通用接口**(官方未文档化),可能不符合其服务条款、且随时可能失效。因此这两项**默认关闭**,需你在设置里手动开启并知悉风险。Codex / Gemini / OpenCode 为纯本地读取,不涉及此问题。

## 你的控制权

- **随时清空全部数据**:退出应用后删除 `~/.tokenitor/` 目录;Claude 凭证在钥匙串里,可用「钥匙串访问.app」搜索并删除 `com.tokenitor.app` 条目。
- **关闭任一工具**:设置页对应开关关掉,即不再读取/请求该工具。
- **关闭调试转储**:默认就是关的;开启过可随时关闭并删除 `~/.tokenitor/debug/`。
- **凭证**:Tokenitor 从不索取你的密码;它复用你本机已有的登录会话/凭证。

## 不收集

Tokenitor **不**收集:对话内容、账号密码、姓名/手机号/邮箱等身份信息、设备指纹、使用行为遥测。项目开源(MIT),你可自行审阅全部源码。

---

如对隐私有疑问,可在 GitHub 仓库提 issue。本说明随功能变更同步更新。
