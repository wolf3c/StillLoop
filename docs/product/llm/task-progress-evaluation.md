# 任务进展评估文档

## 功能目标

任务进展评估判断当前轮多张截图之间是否有可见推进。它回答“这段时间是否在推进任务”，不判断用户是否在场，也不做最终任务匹配结论。

该流程用于区分：

- 仍在任务上推进：focused。
- 任务相关但停滞：stuck。
- 证据不足：uncertain 或由其他评估决定。

## 输入

输入包含：

- 当前任务。
- 当前轮最多三张按时间均匀抽样的截图。
- 每张截图的 app/window/browser 元数据。
- app 使用时间线。
- 近期事件。

如果可比较截图少于 2 张，流程直接返回 unclear，不发起 LLM 请求。

## 输出

结构化输出：

- `progress`：`progressing`、`stalled`、`unclear`。
- `comparisonBasis`：短 snake_case 标签。
- `reason`：简短中文原因。

常见 comparisonBasis：

- `visible_forward_movement`
- `same_task_no_visible_change`
- `returned_to_task`
- `different_task_context`
- `single_screenshot`
- `unreadable`
- `incomparable`

## 判断原则

progressing：

- 多张可比较截图显示同一任务上下文中有可见推进。

stalled：

- 多张可比较截图显示同一任务上下文，没有可见变化，且不是短时间阅读/学习场景。

unclear：

- 只有一张截图。
- 截图来自不同任务上下文。
- 第一张跑偏、最后一张回到任务。
- 截图不可读。
- 无法比较。
- 阅读或学习任务在短窗口内静态停留。

## 规范化逻辑

模型输出后会做产品规则修正：

- 视觉样本少于 2 张时，强制 `unclear/single_screenshot`。
- 如果 `comparisonBasis` 表示不可比较，但 progress 不是 unclear，则改为 unclear。
- 阅读/学习任务中，短时间静态同页不直接判 stalled，而改为 `unclear/reading_static_no_visible_change`。

## 与最终状态的关系

任务进展不会单独决定 focused。它必须和任务匹配一起使用：

- aligned + progressing：通常 focused。
- aligned + unclear：通常 focused 或 uncertain，取决于用户在场等信号。
- aligned + stalled：通常 stuck。
- unaligned 时，progress 结果不能把状态改成 focused。

## 失败行为

任务进展请求失败时，不直接导致整轮失败。系统会使用 `unclear/progress_evaluation_failed` 继续合成，并记录失败类型和 HTTP 诊断。

## 产品要求

- 不要求所有工作都必须有快速视觉变化。
- 阅读、学习和静态参考页面要谨慎判断。
- 返回任务不是进展。
- 不逐字转录截图中的私密文字。

## 输入字段和格式

请求格式是 OpenAI-compatible chat messages：

```json
[
  {
    "role": "system",
    "content": [{"type": "text", "text": "<taskProgressSystemPrompt>"}]
  },
  {
    "role": "user",
    "content": [{"type": "text", "text": "Current task:\n<task text>"}]
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

如果当前轮可比较截图少于 2 张，不发起 LLM 请求，直接返回 unclear。

`visual sample metadata` 会按时间顺序发送最多三组。该 metadata 只用于标明时间顺序和轻量工作上下文；任务进展判断应主要依赖附带截图的视觉变化。

```text
visual sample[1]
time: <ISO-8601 UTC time>
app: <activeAppName>
window: <windowTitle, optional>
browserTitle: <browser title, optional>
screenshot: <available|unavailable>
```

## 输出字段和格式

模型必须返回严格 JSON object：

```json
{
  "progress": "unclear",
  "comparisonBasis": "single_screenshot",
  "reason": "只有一张截图，无法比较进展。"
}
```

字段约束：

- `progress`：必填 string，只能是 `progressing`、`stalled`、`unclear`。
- `comparisonBasis`：必填 string，短 snake_case 标签。
- `reason`：必填 string，简短中文原因。

推荐 `comparisonBasis` 值：

- `visible_forward_movement`
- `same_task_no_visible_change`
- `returned_to_task`
- `different_task_context`
- `single_screenshot`
- `unreadable`
- `incomparable`
- `reading_static_no_visible_change`
- `progress_evaluation_failed`

## System Prompt 原文

```text
You are a project management expert. You are skilled at evaluating task progress from the visible work state.
Judge only whether multiple current-round screen screenshots show forward movement on the stated task.
Do not judge user physical state or final task alignment.

progress:
- progressing: comparable screenshots show visible forward movement on the same task.
- stalled: comparable screenshots show the same task context without visible forward movement.
- unclear: progress cannot be determined.

Progress comparison:
- visual sample[1] is the first sampled screen screenshot from the current pending evaluation captures.
- The last visual sample is the last sampled screen screenshot from the current pending evaluation captures.
- Use progressing only when screenshots show visible forward movement.
- Use stalled only when comparable screenshots show the same task context without visible forward movement.
- For reading or studying on a relevant static page, unchanged screenshots over a short window can mean the user is reading. Use unclear rather than stalled unless there is stronger evidence of inactivity or a longer no-progress pattern.
- Use unclear when there is only one screenshot, screenshots are from different task contexts, the first screenshot is off-task and the last returns to the task, screenshots cannot be compared, or the screen evidence is unreadable.
- Returning to the task is not progress and is not stalled; use unclear with comparisonBasis "returned_to_task".

comparisonBasis should be a short snake_case label, such as visible_forward_movement, same_task_no_visible_change, returned_to_task, different_task_context, single_screenshot, unreadable, or incomparable.

Do not quote or transcribe private page text verbatim. Summarize only what is necessary.
Output exactly one strict JSON object with keys: "progress", "comparisonBasis", "reason".
Example output: {"progress":"unclear","comparisonBasis":"single_screenshot","reason":"只有一张截图，无法比较进展。"}
Use concise Chinese for reason. Do not add Markdown or extra text.
```

## System Prompt 中文翻译

```text
你是项目管理专家，擅长从可见工作状态中评估任务进展。
只判断当前轮多张屏幕截图是否显示声明任务上的前进变化。
不要判断用户身体状态或最终任务匹配情况。

progress：
- progressing：可比较截图显示同一任务上有可见推进。
- stalled：可比较截图显示同一任务上下文中没有可见推进。
- unclear：无法判断进展。

进展比较：
- visual sample[1] 是当前待评估采集中的第一张抽样屏幕截图。
- 最后一张 visual sample 是当前待评估采集中的最后一张抽样屏幕截图。
- 只有截图显示可见推进时才使用 progressing。
- 只有可比较截图显示同一任务上下文且没有可见推进时才使用 stalled。
- 对于相关静态页面上的阅读或学习任务，短时间不变可能表示用户正在阅读。除非有更强的不活跃证据或更长时间的无进展模式，否则使用 unclear 而不是 stalled。
- 当只有一张截图、截图来自不同任务上下文、第一张跑偏而最后一张回到任务、截图不可比较或屏幕证据不可读时，使用 unclear。
- 回到任务不是进展，也不是停滞；使用 unclear，并将 comparisonBasis 设为 "returned_to_task"。

comparisonBasis 应是短 snake_case 标签，例如 visible_forward_movement、same_task_no_visible_change、returned_to_task、different_task_context、single_screenshot、unreadable 或 incomparable。

不要逐字引用或转录私人页面文本。只总结必要内容。
只输出一个严格 JSON object，字段为 "progress"、"comparisonBasis"、"reason"。
示例输出：{"progress":"unclear","comparisonBasis":"single_screenshot","reason":"只有一张截图，无法比较进展。"}
reason 使用简洁中文。不要添加 Markdown 或任何额外文本。
```
