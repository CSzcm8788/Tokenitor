# 字体规范（Typography）

全 app 只用 **两种 Apple 系统字体**，无任何第三方字体：

- **SF Pro（系统无衬线）** —— 所有文字：标题、名称、标签、说明。
- **SF Mono（系统等宽，`design: .monospaced`）** —— 所有数字/数据：token 数、成本、百分比、图表数值、倒计时。

字号采用**固定字号阶梯**（紧凑仪表盘，不随系统动态字体缩放）。唯一定义在 `Sources/Tokenitor/Typography.swift`，想全局调整只改那一处。

> SF Symbol 图标的 `.font(.system(size:))` 属"图标尺寸"、不是排版字体，不纳入本阶梯（`IconButton`、`FlatIcon`、Token 页工具 Tab 的图标尺寸保持独立）。

## 字号阶梯

### 文字（SF Pro）

| Token | pt / 字重 | 用途 |
|---|---|---|
| `.pageTitle`    | 17 semibold | 页面标题（Token usage / 设置 / Tokenitor） |
| `.sectionTitle` | 13 semibold | 工具名（Codex）、卡片/分区标题 |
| `.uiLabel`      | 10 semibold | 全大写小标签（TOTAL TOKENS / TOKENS BY MODEL …） |
| `.uiBody`       | 13 regular  | 正文 / 说明（说明页、免责、Help 正文） |
| `.uiCaption`    | 11 regular  | 次要说明 / 更新时间 / 副标题 |
| `.uiMicro`      | 9 medium    | 极小注解 / 坐标轴文字标签 |

### 数字（SF Mono，等宽）

| Token | pt / 字重 | 用途 |
|---|---|---|
| `.numHero`  | 26 semibold mono | 大数字（124.31M） |
| `.numTitle` | 16 semibold mono | 成本 / 关键值（$89.96、449） |
| `.num`      | 11 medium mono   | 常规数据 / 百分比 / 模型数值 / 剩余% |
| `.numMicro` | 9 medium mono    | 图表轴数字 / 极小数值 |

## 旧 → 新 映射（收敛前后）

| 旧写法 | 新 token |
|---|---|
| `.title2.bold()` | `.pageTitle` |
| `.headline` | `.sectionTitle` |
| `.system(size: 13[, .medium])` | `.sectionTitle` / `.uiBody` |
| `.system(size: 10, .medium/.semibold)` | `.uiLabel` |
| `.callout` / `.system(size: 13)` 正文 | `.uiBody` |
| `.caption` / `.caption2` / `.system(size: 11/11.5)` | `.uiCaption` |
| `.system(size: 9/9.5[, .medium])` 文字 | `.uiMicro` |
| `.system(size: 26, mono)` | `.numHero` |
| `.system(size: 16/17, mono)` | `.numTitle` |
| `.system(size: 10/10.5/11, mono)`、`.monospacedDigit()` | `.num` |
| `.system(size: 9/9.5, mono)` | `.numMicro` |
| `NSFont.systemFont/boldSystemFont(12/13/15)`（Help/免责/下拉） | 按同档位对齐 pt |

### 统一要点

1. **数字全部改为完整 SF Mono**：原先用量页 / 刘海的"剩 X%"只是 SF Pro + `.monospacedDigit()`（字体仍是 SF Pro），现统一为 `.num`（SF Mono），与 Token 页/图表一致。
2. **收敛字号**：原 12+ 个离散字号 + 语义字号 → 上表 10 档；个别元素挪 0.5–1pt / 一档字重，视觉几乎无感。
3. **AppKit（Help / 免责 / 设置下拉的 `NSFont`）** 按同档位对齐字号（13 正文 / 11 副文）。

改字体只改 `Typography.swift`；本文件记录规范与映射，改动时同步更新。
