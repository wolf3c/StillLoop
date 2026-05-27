# LLM 总评估编排文档

## 功能目标

LLM 总评估编排负责把本机上下文转成专注状态，并决定是否提醒。它是专注运行中的核心判断流程。

当前实现优先使用拆分评估：

- 用户在场状态评估。
- 屏幕任务匹配评估。
- 任务进展评估。

之后由 `FocusDecisionSynthesizer` 合成最终 `FocusState`、reason、nudge 和返回目标。

## 输入

每轮评估输入：

- 当前任务文本。
- 最近约 1 分钟的文本上下文。
- 抽样后的截图。
- 抽样后的摄像头帧。
- 最近专注事件。
- 当前 app/window/browser 使用时间线。
- 已缓存的任务相关目标判断。
- 电源状态和视觉样本上限。

上下文来自 `ContextSnapshot`，包含前台应用、bundle identifier、窗口标题、浏览器标题、去 query/fragment 后的 URL、窗口编号、截图压缩数据、摄像头压缩数据和视觉元数据。

## 采样策略

评估前会区分不同用途的视觉样本：

- 用户在场：使用 camera frames。
- 任务匹配：使用最新一张任务截图。
- 任务进展：使用最多三张按时间均匀抽样的当前轮截图。

电池或低电量状态会影响视觉样本上限和下一轮间隔。

## 模型来源

评估编排支持三种运行状态：

- 自带模型：启动 bundled runtime，并通过 Unix socket 访问。
- 手动模型：访问用户配置的 OpenAI-compatible HTTP 服务。
- 基础规则：模型不可用、用户跳过下载或请求失败时的 fallback。

自带模型和手动模型都使用同一套 LLMFocusEvaluator 逻辑。

## 拆分评估并发

当三个 engine 都可用时，以下评估并发执行：

1. `userPresenceOutcome`
2. `taskAlignmentOutcome`
3. `taskProgressOutcome`

任务进展失败不会必然导致整轮失败，会被规范化为 unclear。用户在场或任务匹配失败时，编排会根据剩余结果决定是否能合成，或抛出拆分评估错误。

## 合成规则

合成逻辑大致遵循：

- 用户离开：away。
- 用户休息：resting。
- 屏幕任务匹配且进展为 progressing 或 unclear：focused。
- 屏幕任务匹配但进展停滞：stuck。
- 屏幕明确不匹配：distracted。
- 证据不足或不明确：uncertain。

最终 nudge 只在非 focused 且需要提醒时生成。

## 旧版单体评估

代码仍保留 legacy 单体评估路径。该路径把截图、摄像头、元数据、任务和历史放入一个 prompt，直接输出 state、analysis、reason、focusTargetID 和 nudge。

当前产品应优先维护拆分评估，避免把用户在场、任务匹配和进展判断混在一个 prompt 中。

## 诊断指标

每个 LLM 请求都会尽可能记录：

- visualCaptureCount。
- imageCount。
- textSnapshotCount。
- previousEventCount。
- payloadBytes。
- responseChars。
- inputTextCharacterCount。
- inputTextTokenCount。
- powerStatus。
- visualSampleLimit。
- llama.cpp usage/timings。

这些指标用于解释模型延迟、缓存命中、图片数量和上下文大小。

## fallback 行为

模型失败时：

- 记录 `model.evaluation.failed` 或 `model.evaluation.fallback`。
- 状态文案变为基础规则加失败原因。
- 仍然生成本轮规则评估结果。
- 必要时记录 `model_issue_detected`。
- 空闲时回到模型设置页。

基础规则不会使用图片，只基于任务关键词、前台上下文、常见分心应用和近期事件判断。

## 产品要求

- 当前截图证据优先于历史。
- 用户在场不能单独证明 focused。
- App 名、窗口标题或 URL 只能作为辅助证据，不能替代可见任务证据。
- 不逐字转录私人页面文本。
- nudge 必须短、温和、不批评。

## 当前拆分编排 System Prompt 说明

当前主路径本身不直接发送一个独立 LLM prompt。它会把同一轮上下文拆成三个 LLM 子请求，再合成最终结果：

- 用户在场状态评估：见 [用户在场状态评估](./user-presence-evaluation.md)。
- 屏幕任务匹配评估：见 [屏幕任务匹配评估](./task-alignment-evaluation.md)。
- 任务进展评估：见 [任务进展评估](./task-progress-evaluation.md)。

因此当前拆分编排没有自己的 system prompt 原文或中文翻译；system prompt 分别记录在三个子流程文档中。

## 当前拆分编排输入字段和格式

编排层输入字段：

```json
{
  "task": "<current task text>",
  "textSnapshots": ["<ContextSnapshot>"],
  "visualSnapshots": ["<ContextSnapshot selected for presence>"],
  "taskVisualSnapshots": ["<ContextSnapshot selected for alignment/progress>"],
  "previousEvents": ["<FocusEvent>"],
  "powerStatus": {
    "powerSource": "battery|powerAdapter|unknown",
    "lowPowerMode": true,
    "thermalState": "nominal|fair|serious|critical|unknown"
  },
  "visualSampleLimit": 3,
  "taskVisualSampleLimit": 3,
  "appUsageIntervals": ["<AppUsageInterval>"],
  "evaluationWindowEnd": "<ISO-8601 date>",
  "targetJudgments": ["<TaskTargetJudgment>"]
}
```

关键对象字段：

- `ContextSnapshot.id`：UUID。
- `ContextSnapshot.timestamp`：Date。
- `ContextSnapshot.activeAppName`：string。
- `ContextSnapshot.activeAppBundleIdentifier`：string，可空。
- `ContextSnapshot.windowTitle`：string。
- `ContextSnapshot.browserTitle`：string，可空。
- `ContextSnapshot.browserURL`：sanitized string，可空。
- `ContextSnapshot.processIdentifier`：int，可空。
- `ContextSnapshot.windowNumber`：int，可空。
- `ContextSnapshot.screenshotAvailable`：bool。
- `ContextSnapshot.cameraFrameAvailable`：bool。
- `ContextSnapshot.screenshotPixelWidth` / `screenshotPixelHeight` / `screenshotCompressedBytes` / `screenshotMimeType` / `screenshotData`：截图视觉字段，可空。
- `ContextSnapshot.cameraPixelWidth` / `cameraPixelHeight` / `cameraCompressedBytes` / `cameraMimeType` / `cameraData`：摄像头视觉字段，可空。
- `FocusEvent.timestamp`：Date。
- `FocusEvent.state`：`focused|uncertain|distracted|stuck|resting|away`。
- `FocusEvent.context`：string。
- `FocusEvent.nudge`：string，可空。
- `AppUsageInterval.startedAt` / `endedAt`：Date。
- `AppUsageInterval.target`：ActiveWorkTarget。
- `TaskTargetJudgment.target`：ActiveWorkTarget。
- `TaskTargetJudgment.alignment`：`aligned|unaligned|unclear`。
- `TaskTargetJudgment.reason`：string。
- `TaskTargetJudgment.judgedAt`：Date。

## 当前拆分编排输出字段和格式

编排层输出字段：

```json
{
  "state": "focused",
  "reason": "当前屏幕内容支持任务。",
  "shouldNudge": false,
  "nudge": null,
  "evaluator": "自带模型",
  "modelRunDurationSeconds": 1.2,
  "analysis": {
    "userEngagement": "用户在场并保持参与。",
    "userEngaged": true,
    "screenContent": "当前屏幕内容支持任务。",
    "observedActivity": "任务进展不明确。",
    "taskAlignment": "当前屏幕内容支持任务。",
    "taskAligned": true
  },
  "returnTarget": "<FocusReturnTarget|null>",
  "splitAnalysis": {
    "userPresence": "<LLMUserPresenceEvaluation>",
    "taskAlignment": "<LLMTaskAlignmentEvaluation|null>",
    "taskProgress": "<LLMTaskProgressEvaluation|null>"
  },
  "requestDebugMetrics": "<LLMRequestDebugMetrics>"
}
```

字段约束：

- `state`：最终 FocusState，只能是 `focused`、`uncertain`、`distracted`、`stuck`、`resting`、`away`。
- `shouldNudge`：是否展示提醒。
- `nudge`：提醒文案；focused 时通常为 null。
- `evaluator`：`自带模型`、`手动模型` 或基础规则相关名称。
- `returnTarget`：仅在当前 focused 且目标可返回时存在。
- `requestDebugMetrics`：由各子请求指标合并。

## Legacy 单体评估输入字段和格式

legacy 单体路径仍存在，用于没有拆分 engine 时的兼容评估。请求格式是 OpenAI-compatible chat messages：

```json
[
  {
    "role": "system",
    "content": [{"type": "text", "text": "<legacyFocusSystemPrompt>"}]
  },
  {
    "role": "user",
    "content": [{"type": "text", "text": "<task and recent history>"}]
  },
  {
    "role": "user",
    "content": [{"type": "text", "text": "<text timeline, optional>"}]
  },
  {
    "role": "user",
    "content": [{"type": "text", "text": "<app usage timeline, optional>"}]
  },
  {
    "role": "user",
    "content": [
      {"type": "text", "text": "<visual sample metadata>"},
      {"type": "image", "mimeType": "image/jpeg", "data": "<compressed screenshot bytes>"},
      {"type": "image", "mimeType": "image/jpeg", "data": "<compressed camera frame bytes>"}
    ]
  }
]
```

`task and recent history` 格式：

```text
Current evidence checklist:
- Judge current captures first; use history only as background.
- App names, user presence, prior focused events, and capture metadata are not enough for focused.
- Focused requires current visible task evidence: relevant content, work artifacts, or progress signals.
- Do not use prior focused records to justify focused.
- Social feeds, X/Home, or generic browser home pages are unrelated unless the task is to use that site or visible content directly supports the task.
- Internal evaluator labels only: targetID, visual sample, visualOrder, screenshot, camera, pixel sizes, and byte counts are not user-visible activity.

Current task:
<task text>

Recent state log (background only; current captures have priority and prior decisions may be wrong):
- <state>: <context> nudge=<nudge|none>
```

`visual sample metadata` 格式：

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
visualOrder: screenshot image first, then camera image for this same capture timestamp
screenshot: <available|unavailable|WIDTHxHEIGHT,BYTESB>
camera: <available|unavailable|WIDTHxHEIGHT,BYTESB>
```

## Legacy 单体评估输出字段和格式

模型必须返回严格 JSON object：

```json
{
  "analysis": {
    "userEngagement": "用户在场并保持参与。",
    "userEngaged": true,
    "screenContent": "当前屏幕内容支持任务。",
    "observedActivity": "可见内容显示正在推进任务。",
    "taskAlignment": "当前活动与任务匹配。",
    "taskAligned": true
  },
  "reason": "当前可见工作内容支持任务。",
  "state": "focused",
  "focusTargetID": "T1",
  "nudge": null
}
```

字段约束：

- `analysis.userEngagement`：string，用户参与状态说明。
- `analysis.userEngaged`：boolean，不明确时 false。
- `analysis.screenContent`：string，高层屏幕内容概述。
- `analysis.observedActivity`：string，可见操作或进展信号。
- `analysis.taskAlignment`：string，任务匹配说明。
- `analysis.taskAligned`：boolean，不明确或弱相关时 false。
- `reason`：string，最终判断原因。
- `state`：`focused|uncertain|distracted|stuck|resting|away`。
- `focusTargetID`：focused 时必须是当前 targetID，否则为 null。
- `nudge`：focused 时应为 null；否则为简短中文提醒或 null。

## Legacy System Prompt 原文

```text
You are a focus-session evaluator.
Your job is to judge whether the user's current visible activity supports the stated session goal.

Choose the single state that best describes the current situation.
Consider the screenshot, camera image, app/window/browser metadata, current task, and recent state log together.

State definitions (choose exactly one):
- focused: current screenshot/metadata visibly supports the task.
- uncertain: signals are ambiguous or only weakly connected to the task.
- distracted: one of:
  a) current content is clearly unrelated to the task;
  b) attention appears repeatedly split without clear task progress.
- stuck: task context is present, but there are no visible forward progress signals.
- resting: intentional short break or non-task pause.
- away: user appears to have left the computer or is not physically present.

Current captures are the source of truth. The recent state log is only background and may contain earlier mistakes; never preserve or repeat a prior "focused" judgement when current captures do not support it.
User engagement alone is not enough; judge whether the visible activity appears to support the task.
If the visible text is unreadable or ambiguous, do not invent task-specific content. Use only observable evidence.
App names, user presence, prior focused events, and capture metadata are not enough for focused.
For focused, current captures must show task-relevant content, work artifacts, or progress signals.
If taskAligned is false or unclear, state cannot be focused; choose uncertain, distracted, or stuck based on the current captures.
For StillLoop development tasks, developer tools count only when current visible content shows StillLoop development, debugging, tests, code, project discussion, or release work.

Use the analysis object to briefly explain the judgement:
- userEngagement: whether the user is present and appears attentive.
- screenContent: high-level summary of visible page/app content.
- observedActivity: visible operation or progress signals across captures.
- taskAlignment: whether visible content matches the current task.
- userEngaged: boolean, whether the user appears present and active; use false if unclear.
- taskAligned: boolean, whether visible work appears to support the current task; use false if unclear or weak.

Also choose focusTargetID:
- Each current capture includes a targetID such as T1 or T2.
- If state is focused, focusTargetID must be exactly one targetID from the current captures.
- If state is not focused, focusTargetID must be null.
- Never invent a targetID from the task or history.

Do not quote or transcribe private page text verbatim. Summarize only what is necessary for diagnosis.
The state value must stay one English token exactly. Use concise Chinese for analysis, reason, and nudge. Keep every analysis string to one short sentence.
String fields must be actual concise observations, not copied labels, placeholders, template values, or instructions.
Output exactly one JSON object. Do not add Markdown, comments, or explanatory text outside JSON.
Be gentle and non-judgmental.
Return only strict JSON:
Return a JSON object with keys: "analysis", "reason", "state", "focusTargetID", "nudge".
"analysis" must contain keys: "userEngagement", "userEngaged", "screenContent", "observedActivity", "taskAlignment", "taskAligned".
"state" must be one of: focused, uncertain, distracted, stuck, resting, away.
"focusTargetID" must be a current targetID when state is focused; otherwise null.
"nudge" should be null when state is focused; otherwise use a concise Chinese return cue or null.
```

## Legacy System Prompt 中文翻译

```text
你是专注会话评估器。
你的任务是判断用户当前可见活动是否支持声明的会话目标。

选择最能描述当前情况的单一状态。
综合考虑截图、摄像头图片、应用/窗口/浏览器元数据、当前任务和最近状态日志。

状态定义（只能选择一个）：
- focused：当前截图/元数据明显支持任务。
- uncertain：信号模糊或只与任务弱相关。
- distracted：以下之一：
  a) 当前内容清楚地与任务无关；
  b) 注意力反复分裂，且没有清晰任务进展。
- stuck：任务上下文存在，但没有可见的前进进展信号。
- resting：有意短暂休息或非任务暂停。
- away：用户似乎离开电脑或身体不在场。

当前采集是事实来源。最近状态日志只是背景，且可能包含早先错误；当当前采集不支持时，绝不要保留或重复之前的 "focused" 判断。
只有用户参与状态还不够；要判断可见活动是否支持任务。
如果可见文本不可读或模糊，不要编造任务特定内容。只使用可观察证据。
应用名称、用户在场、历史 focused 事件和采集元数据都不足以证明 focused。
对于 focused，当前采集必须显示任务相关内容、工作产物或进展信号。
如果 taskAligned 为 false 或 unclear，state 不能是 focused；应根据当前采集选择 uncertain、distracted 或 stuck。
对于 StillLoop 开发任务，只有当前可见内容显示 StillLoop 开发、调试、测试、代码、项目讨论或发布工作时，开发工具才算相关。

使用 analysis object 简要解释判断：
- userEngagement：用户是否在场且看起来注意力集中。
- screenContent：可见页面/应用内容的高层摘要。
- observedActivity：采集中的可见操作或进展信号。
- taskAlignment：可见内容是否匹配当前任务。
- userEngaged：boolean，用户是否看起来在场且活跃；不明确时使用 false。
- taskAligned：boolean，可见工作是否支持当前任务；不明确或弱相关时使用 false。

还要选择 focusTargetID：
- 每个当前采集都包含类似 T1 或 T2 的 targetID。
- 如果 state 是 focused，focusTargetID 必须是当前采集中的一个准确 targetID。
- 如果 state 不是 focused，focusTargetID 必须是 null。
- 不要根据任务或历史编造 targetID。

不要逐字引用或转录私人页面文本。只总结诊断所需内容。
state 值必须保持一个英文 token。analysis、reason 和 nudge 使用简洁中文。每个 analysis 字符串保持一句短句。
字符串字段必须是真实简洁观察，不得是复制的标签、占位符、模板值或指令。
只输出一个 JSON object。不要在 JSON 外添加 Markdown、注释或解释文本。
保持温和，不要评判用户。
只返回严格 JSON：
返回字段为 "analysis"、"reason"、"state"、"focusTargetID"、"nudge" 的 JSON object。
"analysis" 必须包含 "userEngagement"、"userEngaged"、"screenContent"、"observedActivity"、"taskAlignment"、"taskAligned"。
"state" 必须是 focused、uncertain、distracted、stuck、resting、away 之一。
"focusTargetID" 在 state 为 focused 时必须是当前 targetID，否则为 null。
"nudge" 在 state 为 focused 时应为 null；否则使用简洁中文回到任务提示或 null。
```
