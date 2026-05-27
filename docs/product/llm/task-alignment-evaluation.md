# 屏幕任务匹配评估文档

## 功能目标

屏幕任务匹配评估判断当前可见屏幕活动是否支持用户写下的任务。它只回答“当前屏幕是否与任务相关”，不判断用户是否在场，也不判断任务是否有进展。

## 输入

输入包含：

- 当前任务文本。
- 最新一张当前轮截图。
- 对应 app/window/browser 元数据。
- targetID。
- 已有任务相关目标判断上下文。

元数据可能包括：

- 前台应用名称。
- bundle identifier。
- 窗口标题。
- 浏览器标题。
- 去 query/fragment 后的 URL。
- 窗口编号。
- Space 标识。
- 截图尺寸和压缩大小。

## 输出

结构化输出：

- `alignment`：`aligned`、`unaligned`、`unclear`。
- `focusTargetID`：当 aligned 时选择当前截图中的一个 targetID，否则为 null。
- `reason`：简短中文原因。

## 判断原则

aligned：

- 可见屏幕内容直接支持当前任务。
- 或明确的 app/window/browser 元数据支持任务，且截图不矛盾。

unaligned：

- 可见内容清楚与任务无关。
- 社交流、通用首页或无关浏览内容不应因用户在场而被判 aligned。

unclear：

- 屏幕证据模糊。
- 截图不可读。
- 只有弱相关的应用或标题。

阅读或学习类任务的静态页面可以是 aligned，不应仅因没有滚动或编辑动作判为 unaligned。

## 任务相关目标判断的使用

如果某个 app/window/browser 目标已被长期证据判断为任务相关，该判断会作为屏幕任务匹配的上下文输入。但它不能覆盖当前截图明显矛盾的证据。

## 与返回目标的关系

当 aligned 且选择了 focusTargetID，最终 focused 结果可以把对应 snapshot 转成 `FocusReturnTarget`。后续 nudge 点击会优先回到任务相关目标，其次回到最近 focused 目标。

## 失败行为

如果任务匹配失败：

- 若用户在场评估明确为 away 或 resting，仍可合成 away/resting。
- 否则整轮 LLM 评估失败并回退基础规则。

## 产品要求

- 不逐字转录私人页面文本。
- 不把 app 名或用户在场当作充分证据。
- 不为非 aligned 状态编造 focusTargetID。
- reason 应解释任务相关性，不描述无关视觉细节。

## 输入字段和格式

请求格式是 OpenAI-compatible chat messages：

```json
[
  {
    "role": "system",
    "content": [{"type": "text", "text": "<taskAlignmentSystemPrompt>"}]
  },
  {
    "role": "user",
    "content": [{"type": "text", "text": "Current task:\n<task text>"}]
  },
  {
    "role": "user",
    "content": [{"type": "text", "text": "<target judgment context, optional>"}]
  },
  {
    "role": "user",
    "content": [
      {"type": "text", "text": "<visual sample metadata>"},
      {"type": "image", "mimeType": "image/jpeg", "data": "<compressed screenshot bytes>"}
    ]
  }
]
```

`Current task` 文本格式：

```text
Current task:
<用户输入的当前任务>
```

`visual sample metadata` 字段格式：

```text
visual sample[1]
targetID: T1
time: <ISO-8601 UTC time>
app: <activeAppName>
bundleIdentifier: <bundle id, optional>
window: <windowTitle, optional>
browserTitle: <browser title, optional>
browserURL: <sanitized http/https URL, optional>
windowNumber: <window number, optional>
space: <space identifier, optional>
screenshot: <available|unavailable|WIDTHxHEIGHT,BYTESB>
```

`target judgment context` 可选，只有存在 aligned 历史目标判断时发送：

```text
Target judgment context (context only; 主评估仍以当前截图和当前 metadata 为准，不能硬复制历史判断。)

judgment[1]
target: <target display text>
alignment: aligned
judgedAt: <ISO-8601 UTC time>
reason: <truncated Chinese reason>
```

## 输出字段和格式

模型必须返回严格 JSON object：

```json
{
  "alignment": "aligned",
  "focusTargetID": "T1",
  "reason": "当前屏幕内容支持任务。"
}
```

字段约束：

- `alignment`：必填 string，只能是 `aligned`、`unaligned`、`unclear`。
- `focusTargetID`：当 `alignment` 为 `aligned` 时，应为当前输入中存在的 targetID；否则必须是 `null`。
- `reason`：必填 string，简短中文原因，不逐字转录隐私文本。

## System Prompt 原文

```text
You are a project management expert. You are skilled at evaluating whether the current work matches the stated task.
Judge only whether the latest visible screen activity supports the stated task.
Use the latest screenshot, app/window/browser metadata, and current task only.
Do not judge task progress, user physical state, or recent focus history.

alignment:
- aligned: visible screen content or specific current app/window/browser metadata directly supports the task and screenshots do not contradict it.
- unaligned: visible screen content is clearly unrelated to the task.
- unclear: screen evidence is ambiguous or weak.

For reading or studying tasks, a relevant static page can still be aligned. Do not mark it unaligned only because no click, scroll, or edit is visible.
Matching app, title, or URL metadata can support aligned when the screenshot does not contradict it.
Generic UI stability or coherence is not task evidence. If the reason cannot identify task-specific visible content or matching current metadata, use unaligned or unclear.

Also choose focusTargetID:
- If alignment is aligned, focusTargetID should be one current targetID when a specific capture best represents the aligned work.
- Otherwise use null.
- Never invent a targetID.

Do not quote or transcribe private page text verbatim. Summarize only what is necessary.
Output exactly one strict JSON object with keys: "alignment", "focusTargetID", "reason".
Example output: {"alignment":"aligned","focusTargetID":"T1","reason":"当前屏幕内容支持任务。"}
Use concise Chinese for reason. Do not add Markdown or extra text.
```

## System Prompt 中文翻译

```text
你是项目管理专家，擅长评估当前工作是否匹配声明的任务。
只判断最新可见屏幕活动是否支持该任务。
只使用最新截图、应用/窗口/浏览器元数据和当前任务。
不要判断任务进展、用户身体状态或最近专注历史。

alignment：
- aligned：可见屏幕内容或明确的当前应用/窗口/浏览器元数据直接支持任务，并且截图不矛盾。
- unaligned：可见屏幕内容清楚地与任务无关。
- unclear：屏幕证据模糊或较弱。

对于阅读或学习任务，相关的静态页面仍然可以是 aligned。不要只因为没有点击、滚动或编辑就判为 unaligned。
当截图不矛盾时，匹配的应用、标题或 URL 元数据可以支持 aligned。
通用 UI 稳定性或页面结构不是任务证据。如果 reason 不能指出任务特定的可见内容或匹配的当前元数据，请使用 unaligned 或 unclear。

还要选择 focusTargetID：
- 如果 alignment 是 aligned，focusTargetID 应该是当前 targetID 中最能代表该 aligned 工作的一项。
- 否则使用 null。
- 不要编造 targetID。

不要逐字引用或转录私人页面文本。只总结必要内容。
只输出一个严格 JSON object，字段为 "alignment"、"focusTargetID"、"reason"。
示例输出：{"alignment":"aligned","focusTargetID":"T1","reason":"当前屏幕内容支持任务。"}
reason 使用简洁中文。不要添加 Markdown 或任何额外文本。
```
