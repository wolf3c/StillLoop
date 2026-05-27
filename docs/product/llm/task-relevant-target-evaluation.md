# 任务相关目标判断文档

## 功能目标

任务相关目标判断用于识别某个前台 app/window/browser 目标是否属于当前任务。它不是当前轮专注状态判断，而是一个独立、可缓存的目标判断流程。

该流程解决的问题：

- 用户可能在同一任务中长期使用某个窗口或网页。
- 单轮截图可能不足以判断该目标是否相关。
- nudge 点击需要尽量回到真正的工作目标，而不是 StillLoop 或无关窗口。

## 输入来源

目标来自 `MacActiveWorkTargetProvider`，包含：

- app 名称。
- bundle identifier。
- process identifier。
- window title。
- browser title。
- sanitized browser URL。
- window number。
- Space identifier。
- 当前目标截图。

浏览器 URL 会去除 query 和 fragment。

## 候选规则

目标必须先是可判断候选：

- StillLoop 自己不是候选。
- 浏览器目标必须有有效 http/https URL。
- 非浏览器应用通常可作为候选。

## 触发条件

目标判断由独立监控循环触发。监控循环使用事件驱动加低频兜底：

- `NSWorkspace` 前台 app 激活事件用于捕获 app 切换。
- Accessibility focused-window 事件用于捕获同一 app 内窗口切换。
- 低频 fallback 轮询用于补漏、浏览器 tab/URL 变化和 AX 不可用场景。

核心条件：

- 目标变化事件只记录 app/window/browser/Space 元数据，不立刻截图。
- 同一目标停留至少 5 秒后，才采集一张目标证据截图。
- 目标持续停留时，按同一 dwell cadence 继续追加轻量截图证据。
- 当前会话中该目标尚未判断过，或已有判断已过期。
- 没有同一目标的判断正在进行。
- 证据缓冲达到要求。

当前默认判断过期时间为 300 秒。

如果 Accessibility observer 不可用或辅助功能权限未授权，应用记录降级诊断并继续使用 `NSWorkspace` 事件和 fallback 轮询；目标判断优化不阻塞专注流程。

## 证据缓冲

证据缓冲按目标 identityKey 管理。它会记录：

- 首次观察时间。
- 最近观察时间。
- 累计前台停留时长。
- dwell 满 5 秒后的第一张证据截图。
- 约 15 秒附近的中间截图。
- 最新截图。

当满足以下条件时，证据可用于 LLM 判断：

- 累计前台停留至少 30 秒。
- 至少 3 张证据。
- 证据跨度至少 20 秒。

超过 300 秒未更新的缓冲会被清理。

## LLM 请求

任务相关目标判断调用 `TaskRelevantTargetEvaluator`。请求包含：

- 当前任务。
- 前台目标元数据。
- 累计前台秒数。
- 证据跨度秒数。
- 多张按时间排序的证据截图。

系统 prompt 要求只判断该目标是否属于当前任务，不判断用户在场或任务进展。

## 输出

结构化输出：

- `alignment`：`aligned`、`unaligned`、`unclear`。
- `reason`：简短中文原因。

输出会被记录为 `TaskTargetJudgment`，并在 aligned 时更新 `TaskRelevantTarget`。

## 与主评估的关系

任务相关目标判断是主评估的辅助上下文：

- 它不直接改变当前 FocusState。
- 它会作为任务匹配评估的参考信息。
- 它会影响 nudge 返回目标选择。
- 它保存在当前 `FocusSession` 中。

## 与 nudge 返回目标的关系

当一轮评估产生 nudge 时，返回目标优先级为：

1. 最近任务相关目标。
2. 最近 focused 事件的 return target。
3. 无目标时只展示提醒或打开 StillLoop。

这种优先级避免用户点击提醒后只激活一个无关窗口。

## 诊断

成功时记录 `target.judgment.completed`，包含：

- sessionID。
- target。
- alignment。
- reason。
- targetEvidenceCount。
- targetEvidenceSpanSeconds。
- targetCumulativeForegroundSeconds。
- targetLLM 请求指标。

失败时记录 `target.judgment.failed`。

目标观察和 dwell 截图会记录安全诊断：

- `target.observation.changed`：目标 identityKey 变化，包含 target 和 source。
- `target.dwell.screenshot.captured`：dwell 截图成功，包含 target 和图片尺寸/压缩大小。
- `target.event_source.degraded`：事件源降级原因。

诊断不记录截图内容、原始用户输入、完整带 query 的 URL 或私密文本。

## 产品要求

- 保持目标判断与主专注评估分离。
- 先保存 raw app/window/browser/Space 使用事实，再派生 LLM 输入。
- URL 只使用 sanitized 版本。
- 不逐字转录截图私密内容。
- 缓存 cadence 应明确，避免每次窗口切换都发 LLM。

## 输入字段和格式

请求格式是 OpenAI-compatible chat messages：

```json
[
  {
    "role": "system",
    "content": [{"type": "text", "text": "<taskRelevantTargetSystemPrompt>"}]
  },
  {
    "role": "user",
    "content": [
      {"type": "text", "text": "<targetPromptText>"},
      {"type": "image", "mimeType": "image/jpeg", "data": "<evidence screenshot 1 bytes>"},
      {"type": "image", "mimeType": "image/jpeg", "data": "<evidence screenshot 2 bytes>"},
      {"type": "image", "mimeType": "image/jpeg", "data": "<evidence screenshot 3 bytes>"}
    ]
  }
]
```

`targetPromptText` 格式：

```text
Current task:
<用户输入的当前任务>

Foreground target:
app: <target.appName>
cumulativeForegroundSeconds: <rounded seconds>
evidenceSpanSeconds: <rounded seconds>
bundleIdentifier: <bundle id, optional>
window: <window title, optional>
browserTitle: <browser title, optional>
browserURL: <sanitized http/https URL, optional>
windowNumber: <window number, optional>
space: <space identifier, optional>

evidence[1]
time: <ISO-8601 UTC time>
app: <evidence target appName>
bundleIdentifier: <bundle id, optional>
window: <window title, optional>
browserTitle: <browser title, optional>
browserURL: <sanitized http/https URL, optional>
windowNumber: <window number, optional>
space: <space identifier, optional>
screenshot: <WIDTH>x<HEIGHT>,<BYTES>B
```

输入字段说明：

- `task`：当前会话任务，string。
- `target`：当前被判断的 `ActiveWorkTarget`。
- `evidence`：按时间排序的截图证据，至少 3 张。
- `cumulativeForegroundSeconds`：该目标累计前台停留秒数，number。
- `evidenceSpanSeconds`：证据首尾跨度秒数，number。
- `browserURL`：只允许 sanitized http/https URL，不含 query 和 fragment。
- `screenshot`：实际图片作为 image content 附加，文本里只放尺寸和压缩大小。

## 输出字段和格式

模型必须返回严格 JSON object：

```json
{
  "alignment": "aligned",
  "reason": "该窗口持续显示与当前任务直接相关的工作内容。"
}
```

字段约束：

- `alignment`：必填 string，只能是 `aligned`、`unaligned`、`unclear`。
- `reason`：必填 string，简短中文原因，不逐字转录隐私文本。

评估成功后，应用会在模型输出之外补充内部字段：

- `evidenceCount`：证据数量。
- `evidenceSpanSeconds`：证据跨度。
- `cumulativeForegroundSeconds`：累计前台秒数。
- `requestDebugMetrics`：请求诊断指标。

## System Prompt 原文

```text
You judge whether one foreground app/window/browser target belongs to the user's current task across multiple time-ordered evidence frames.
Use only the current task, app/window/browser metadata, Space metadata, cumulative foreground duration, observation span, and attached screenshots.
Do not judge user presence or task progress.
Do not quote or transcribe private visible text verbatim.
Treat the frames as evidence of sustained or cumulative use of the same target.
Prefer unclear when the evidence is too thin or ambiguous after considering all frames.

alignment:
- aligned: the target directly supports the current task.
- unaligned: the target is clearly unrelated to the current task.
- unclear: the target may be related but the evidence is weak or ambiguous.

Output exactly one strict JSON object with keys: "alignment", "reason".
Use concise Chinese for reason. Do not add Markdown or extra text.
```

## System Prompt 中文翻译

```text
你需要根据多张按时间排序的证据帧，判断一个前台应用/窗口/浏览器目标是否属于用户当前任务。
只使用当前任务、应用/窗口/浏览器元数据、Space 元数据、累计前台时长、观察跨度和附加截图。
不要判断用户是否在场，也不要判断任务进展。
不要逐字引用或转录私人可见文本。
把这些帧视为同一目标持续或累计使用的证据。
综合所有帧后，如果证据太薄或模糊，优先使用 unclear。

alignment：
- aligned：该目标直接支持当前任务。
- unaligned：该目标清楚地与当前任务无关。
- unclear：该目标可能相关，但证据较弱或模糊。

只输出一个严格 JSON object，字段为 "alignment"、"reason"。
reason 使用简洁中文。不要添加 Markdown 或任何额外文本。
```
