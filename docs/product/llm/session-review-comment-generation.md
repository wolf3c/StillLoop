# 复盘评语生成文档

## 功能目标

复盘评语生成在用户结束专注后，基于本次会话过程生成一段具体、正向、中文的复盘建议。

该评语不是状态判定，也不影响会话数据；它只增强复盘页的可读性和行动建议。

## 触发时机

用户点击“结束并复盘”后：

1. 应用停止采集和评估。
2. 保存会话和摘要。
3. 进入复盘页。
4. 异步调用复盘评语生成。

如果用户从复盘页继续任务，旧评语会被清空。

## 输入

复盘评语使用 `FocusSession` 生成 prompt，包含：

- 当前任务。
- 总时长分钟数。
- 各 FocusState 次数。
- nudge 数量。
- Top apps。
- 最近使用过的 nudges。
- 最近时间线事件。

输入不包含截图、摄像头图片或完整原始内容。

## 输出

模型必须返回严格 JSON：

```json
{"comment":"..."}
```

comment 要求：

- 简体中文。
- 约 70-120 个中文字符。
- 1-2 句话。
- 具体回应本次专注过程。
- 先承认具体努力或恢复，再给下次建议。
- 结尾自然指向继续一次专注或保持节奏。
- 不提产品名。
- 不使用日文或英文散文。

## 失败条件

复盘评语生成可能失败：

- 会话没有事件，缺少上下文。
- 模型返回空 comment。
- comment 不含中文。
- comment 含日文假名。
- JSON 解析失败或模型请求失败。

失败时产品应保留基础复盘指标，不因评语失败影响用户结束流程。

## 与复盘页关系

复盘页除了评语，还展示：

- 任务标题和继续任务操作。
- 总时长。
- 估算专注时长。
- 跑偏或停滞次数。
- 提醒次数。
- 常用应用图表和列表。

评语应补充这些指标，而不是重复数字。

## 产品要求

- 评语必须具体，不做空泛鼓励。
- 不引用用户私密内容全文。
- 不夸大模型判断准确性。
- 不把失败或跑偏描述成批评。
- 评语生成是增强体验，不能阻塞复盘页打开。

## 输入字段和格式

请求格式是 OpenAI-compatible chat messages：

```json
[
  {
    "role": "system",
    "content": [{"type": "text", "text": "<sessionReviewSystemPrompt>"}]
  },
  {
    "role": "user",
    "content": [{"type": "text", "text": "<session review prompt>"}]
  }
]
```

user prompt 文本格式：

```text
Current task: <session.task>
Total duration: <integer minutes> minutes
State counts: focused=<count>, uncertain=<count>, distracted=<count>, stuck=<count>, resting=<count>, away=<count>
Nudge count: <summary.nudgeCount>
Top apps: <appName>=<count>, <appName>=<count>
Nudges used: <nudge text> | <nudge text>

Recent timeline:
- <state>: <event.context>
- <state>: <event.context>
```

字段说明：

- `Current task`：用户输入的任务文本。
- `Total duration`：总时长，向下取整为分钟。
- `State counts`：每种 FocusState 在事件中的出现次数。
- `Nudge count`：本次会话提醒数量。
- `Top apps`：最多 5 个应用及出现次数；无数据时为 `none`。
- `Nudges used`：最多 5 条提醒文案；无数据时为 `none`。
- `Recent timeline`：最多 8 条事件，格式为 `- <state>: <context>`；无数据时为 `none`。

该流程不发送截图、摄像头图片或完整原始事件对象。

## 输出字段和格式

模型必须返回严格 JSON object：

```json
{
  "comment": "你这次能多次把注意力拉回任务，说明节奏已经建立起来了。下次可以先把最关键的一步写得更具体，再继续保持这个节奏。"
}
```

字段约束：

- `comment`：必填 string。
- 必须是简体中文。
- 约 70-120 个中文字符。
- 1-2 句话。
- 不得写日文假名或英文散文。
- 不得提产品名。
- 必须具体回应本次会话过程，不是泛泛鼓励。

## System Prompt 原文

```text
You are StillLoop, a local privacy-first focus companion.
Write a short, positive Chinese review comment for the completed focus session.
The comment must be specific to the provided session process, not generic praise.
Use Simplified Chinese only. Keep app names and task text as-is if needed, but do not write Japanese or English prose.
Use about 70-120 Chinese characters in 1-2 sentences.
First acknowledge concrete effort or recovery from this session, then give one practical next-session suggestion.
End naturally with continuing another focus session or keeping the rhythm. Do not mention the product name.
Return only strict JSON:
{"comment":"..."}
```

## System Prompt 中文翻译

```text
你是 StillLoop，一个本地优先、注重隐私的专注伙伴。
为已完成的专注会话写一段简短、正向的中文复盘评语。
评语必须具体对应提供的会话过程，不能是泛泛夸奖。
只使用简体中文。必要时可以保留应用名称和任务文本原文，但不要写日文或英文散文。
使用约 70-120 个中文字符，1-2 句话。
先肯定本次会话中的具体努力或从跑偏中恢复，再给出一个实用的下次专注建议。
结尾自然指向继续另一段专注或保持节奏。不要提到产品名。
只返回严格 JSON：
{"comment":"..."}
```
