# cc-provider-add

> 把第三方 Anthropic 兼容 API 端点接入 Claude Code 的 skill。每个 provider 完全隔离，零二进制依赖，纯 shell + JSON。**永远不动** `~/.claude/`。

[English](README.md) | [中文](README_ZH.md)

## 这是什么

一句话调用就能把 MiMo、GLM、Kimi、AWS Bedrock，或任意自部署的 Anthropic 兼容网关接入 Claude Code 的 skill。每个 provider 跑在独立的 `CLAUDE_CONFIG_DIR` 里：

- 会话、插件、设置互不污染
- 两个终端可以**同时**跑两个 provider
- 用户主目录 `~/.claude/` 完全不动
- 切换 = 新开 shell + 跑别名，没有 GUI，没有全局状态突变

## 为什么存在

直接改 `~/.claude/settings.json` 这种 hack 用单 provider 还行，多 provider 立刻就崩：

- 一份配置文件意味着切换 provider 时覆盖前一个 provider 的会话状态
- 新建 `CLAUDE_CONFIG_DIR` 会被 Claude Code 当作新账号，强制走 OAuth 登录，挡住 API key 路径。绕过办法不直观（需要写一份特定结构的 `.claude.json`，把 key 指纹预先标记为 approved）
- cc-switch 这类 GUI 工具解决了切换问题，但带来新问题——最关键的是它每次切换都改写用户的 live `~/.claude/settings.json`

这个 skill 把最小、透明的方案固化下来：用 `CLAUDE_CONFIG_DIR` 做 per-provider 隔离 + OAuth 绕过 trick + 一行 shell alias 启动。

## 快速开始

装好 skill 之后，用自然语言描述 provider 就行，缺啥它会问你：

> "帮我接入 MiMo，Base URL 看我账号 dashboard，API key `tp-…`，模型 `mimo-v2.5-pro`，用 `ANTHROPIC_AUTH_TOKEN`"

Skill 会自动：

1. 把 key 写到 `~/.config/ai-secrets/<name>.env`（chmod 600），按 provider 要求用 `ANTHROPIC_API_KEY` 或 `ANTHROPIC_AUTH_TOKEN`
2. 建 `~/.claude-<name>/`，含 `settings.json`（base URL + 模型 + 4 个必需的 `ANTHROPIC_*_MODEL` env vars）和 `.claude.json`（绕过引导，API_KEY 模式额外预批 key 指纹）
3. 在 `~/.local/bin/claude-provider-launch` 里加 case 分支（不存在则新建）
4. 在 rc 文件里加 shell 函数（`cmimo`、`cglm` 等）
5. **打一个真实 API 请求验证端到端通**——只有真响应回来了才算配置成功

## 工作原理

### 四件套

| 文件 | 作用 |
| --- | --- |
| `~/.zshrc` 里的 shell 函数（如 `cmimo`） | 一键启动指向该 provider 的 CC |
| `~/.local/bin/claude-provider-launch` | 调度器：根据 provider 名加载对应 secrets 和 config dir，然后 `exec claude` |
| `~/.config/ai-secrets/<name>.env` | 只存 API key，权限 600 |
| `~/.claude-<name>/` | 该 provider 的隔离 home：`settings.json`（base URL + 模型）和 `.claude.json`（OAuth 绕过） |

### OAuth 绕过 trick

新建的 `CLAUDE_CONFIG_DIR` 会被判定为新账号、强制走 OAuth 登录。要在不动 `~/.claude/` 的前提下绕过，skill 写一份最小的 `.claude.json`，结构因 auth header 而异：

**`ANTHROPIC_AUTH_TOKEN` 类 provider（如 MiMo）**——AUTH_TOKEN 模式不触发"信任 key"弹窗：

```json
{
  "hasCompletedOnboarding": true
}
```

**`ANTHROPIC_API_KEY` 类 provider（如 GLM）**——预先把 key 指纹写进 approved 跳过弹窗：

```json
{
  "hasCompletedOnboarding": true,
  "customApiKeyResponses": {
    "approved": ["<API key 后 20 位>"],
    "rejected": []
  }
}
```

那 20 位指纹就是你点"信任这个 key"时 Claude Code 存下来的。如果你之前误启动过一次并点了 No，指纹会卡在 `rejected` 里——skill 内置 `scripts/recover-rejected.py` 把它挪回 `approved`。

### 为什么要写 4 个 `ANTHROPIC_*_MODEL` env vars

某些 provider（尤其 MiMo）拒绝 Claude Code 请求里出现的官方模型名（`claude-sonnet-X` / `claude-opus-X` / `claude-haiku-X`）。设全 `ANTHROPIC_DEFAULT_SONNET_MODEL` / `ANTHROPIC_DEFAULT_OPUS_MODEL` / `ANTHROPIC_DEFAULT_HAIKU_MODEL`（再加 `ANTHROPIC_MODEL` 兜底）让 CC 把每个请求都路由到 provider 实际支持的模型 ID。冗余设置无害，缺失会 400，所以 skill 一律全设。

### 端到端验证

Skill 总是以一次真实 API 请求收尾（`-p "Reply with PONG"`）。**Claude Code 能正常启动 ≠ API 调通**——只能证明本地配置 parse 没问题。跳过这步是配置看似 OK 实则 400 错误的最大来源。

## vs cc-switch

[cc-switch](https://github.com/farion1231/cc-switch) 是一个成熟的 Tauri 桌面 GUI，覆盖 5 个 CLI 工具（Claude Code、Codex、Gemini CLI、OpenCode、OpenClaw），50+ provider 预设、系统托盘、MCP/Skills 同步、用量看板、云端同步。**两者是不同形态的产品，不是替代关系**——可以共存。

|  | cc-provider-add（本 skill） | cc-switch |
| --- | --- | --- |
| 安装包 | 零，纯 shell + JSON | Tauri 桌面应用（30MB+） |
| 是否动 `~/.claude/settings.json` | **从不** | 切换时改写 live config |
| 并发 provider | ✅ 两个 shell 跑两个 provider | ❌ 全局单活 |
| 会话隔离 | ✅ 独立 `CLAUDE_CONFIG_DIR` | ❌ 共用 |
| 切换速度 | 新开 shell + 跑别名 | 托盘点击（更快） |
| 支持工具 | 仅 Claude Code | CC + Codex + Gemini + OpenCode + OpenClaw |
| Provider 预设 | 自己填 | 50+ 内置 |
| MCP / Skills 集中管理 | ❌ | ✅ |
| 用量看板 | ❌ | ✅ |
| 云端同步 | ❌ | ✅（Dropbox / OneDrive / iCloud / WebDAV） |
| 可远程 / SSH / CI | ✅ | ❌ |
| 可审计 | 全是明文 JSON，可 git diff | SQLite 数据库 |
| 学习曲线 | 需要懂基础 shell + JSON | GUI 拖拽 |
| 跨平台 | macOS / Linux（Windows 需改 shell） | Win / Mac / Linux 原生 |

**选本 skill 如果**：你长在终端里、不想要二进制依赖、不喜欢 GUI 应用改你的 dotfiles、想要真正的多 shell 并发 provider、或者只用 Claude Code 不用其他 CLI。

**选 cc-switch 如果**：想一个工具管 5 个 CLI、偏好 GUI、需要 preset 库、想开箱即用的用量看板和云端同步。

## 不用 skill 手动接入

完整手动流程见 [SKILL.md](SKILL.md)——skill 只是把那份流程做成 agent 可执行版本。

## 安全

- Secrets 存在 `~/.config/ai-secrets/*.env`，权限 600
- `~/.claude-<name>/.claude.json` 含本地 `userID`，建议把 `~/.claude-*/` 加进全局 `.gitignore`
- Skill **永远不写** `~/.claude/` 或 `~/.claude/settings.json`
- 信任第三方端点 = 把所有 prompt 都发给该 provider，请自行评估隐私与合规

## 安装

把仓库 clone 到任意位置，然后 symlink 进 Claude Code 的 skills 目录：

```bash
git clone https://github.com/huasan2025/cc-provider-add.git ~/cc-provider-add
ln -s ~/cc-provider-add ~/.claude/skills/cc-provider-add
```

或者，如果你按本仓库开发约定把 skill 源码放在 `~/.agents/skills/`：

```bash
git clone https://github.com/huasan2025/cc-provider-add.git ~/.agents/skills/cc-provider-add
ln -s ~/.agents/skills/cc-provider-add ~/.claude/skills/cc-provider-add
```

重启 Claude Code，用自然语言描述你的 provider 即可触发 skill（见上方"快速开始"）。

## 测试

运行内置测试（24 个检查，在隔离 tmpdir 里模拟两个 provider，不联网）：

```bash
bash tests/run.sh
```
