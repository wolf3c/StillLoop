# 用户在场状态评估文档

## 功能目标

用户在场状态评估只判断摄像头证据中的人是否在场、离开、休息或不明确。它不判断任务内容、屏幕内容或工作进展。

该拆分是为了避免把“人在电脑前”误当成“正在专注完成任务”。

## 输入

输入只包含当前轮抽样得到的摄像头图片。不会向该评估发送：

- 当前任务。
- 屏幕截图。
- App 名称。
- 窗口标题。
- 浏览器 URL。
- 近期专注历史。

如果没有可用摄像头帧，流程直接返回 unclear，不发起 LLM 请求。

## 输出

结构化输出：

- `presence`：`present`、`away`、`resting`、`unclear`。
- `engagement`：`engaged`、`disengaged`、`unclear`。
- `reason`：简短中文原因。

## 状态含义

- present：用户可见，并看起来可继续工作。
- away：摄像头帧中用户不在。
- resting：用户可见，但像是在有意短暂停顿。
- unclear：摄像头缺失、不可读或证据模糊。

engagement 是辅助信号，不能单独决定最终 focused。

## 与最终状态的关系

用户在场评估会影响最终状态：

- away 通常合成为 away。
- resting 通常合成为 resting。
- present 只说明用户在电脑前，仍必须结合屏幕任务匹配和任务进展。
- unclear 不应强行推断用户离开或专注。

## 隐私要求

- 摄像头图片只在内存中作为压缩图片输入。
- 原始照片不写磁盘。
- reason 不应描述敏感个人细节。
- 不把摄像头状态用于员工监控或团队统计。

## 失败行为

如果该 LLM 请求失败，而任务匹配评估成功，系统可用 unclear 的用户状态继续合成。如果用户在场和任务匹配都失败，整轮 LLM 评估失败并回退基础规则。

## 验收标准

- 没有摄像头帧时不发起不必要的 LLM 请求。
- 用户在场不能让 off-task 屏幕被判为 focused。
- 用户离开时，应优先避免继续用屏幕活动推断专注。

## 输入字段和格式

请求格式是 OpenAI-compatible chat messages。当前流程只发送 system message 和可选 user image message。

```json
[
  {
    "role": "system",
    "content": [{"type": "text", "text": "<userPresenceSystemPrompt>"}]
  },
  {
    "role": "user",
    "content": [
      {"type": "image", "mimeType": "image/jpeg", "data": "<compressed camera frame bytes>"},
      {"type": "image", "mimeType": "image/jpeg", "data": "<compressed camera frame bytes>"}
    ]
  }
]
```

字段说明：

- `role`：固定为 `system` 或 `user`。
- `content[].type`：`text` 或 `image`。
- `content[].mimeType`：摄像头压缩图 MIME 类型，通常是 `image/jpeg`。
- `content[].data`：摄像头压缩图二进制数据。

不会发送当前任务、屏幕截图、app 名、窗口标题、浏览器 URL 或历史事件。

如果没有可用摄像头图片，流程不发起 LLM 请求，直接生成内部结果：

```json
{
  "presence": "unclear",
  "engagement": "unclear",
  "reason": "摄像头照片不可用，未运行用户状态判断。"
}
```

## 输出字段和格式

模型必须返回严格 JSON object：

```json
{
  "presence": "present",
  "engagement": "engaged",
  "reason": "用户在场并保持参与。"
}
```

字段约束：

- `presence`：必填 string，只能是 `present`、`away`、`resting`、`unclear`。
- `engagement`：必填 string，只能是 `engaged`、`disengaged`、`unclear`。
- `reason`：必填 string，简短中文原因。

## System Prompt 原文

```text
You are a focus analysis expert.
Judge only whether recent camera frames show the person physically present, away, resting, or unclear.
Do not use task details, screen content, app names, window titles, browser metadata, or recent focus history.
Do not infer task progress or task alignment.

Choose:
- present: the person is visible and appears available to continue.
- away: the person is absent from the camera frames.
- resting: the person is visible but appears to be taking an intentional pause.
- unclear: camera evidence is missing, unreadable, or ambiguous.

engagement:
- engaged: the person appears attentive or active.
- disengaged: the person appears inactive or not attending.
- unclear: engagement cannot be determined.

Output exactly one strict JSON object with keys: "presence", "engagement", "reason".
"presence" must be one of: present, away, resting, unclear.
"engagement" must be one of: engaged, disengaged, unclear.
Example output: {"presence":"present","engagement":"engaged","reason":"用户在场并保持参与。"}
Use concise Chinese for reason. Do not add Markdown or extra text.
```

## System Prompt 中文翻译

```text
你是专注分析专家。
只判断最近的摄像头画面是否显示用户本人在场、离开、休息或无法判断。
不要使用任务细节、屏幕内容、应用名称、窗口标题、浏览器元数据或最近专注历史。
不要推断任务进展或任务匹配情况。

可选值：
- present：用户可见，并且看起来可以继续。
- away：用户没有出现在摄像头画面中。
- resting：用户可见，但看起来是在有意短暂停顿。
- unclear：摄像头证据缺失、不可读或模糊。

engagement：
- engaged：用户看起来专注或活跃。
- disengaged：用户看起来不活跃或没有注意。
- unclear：无法判断参与状态。

只输出一个严格 JSON object，字段为 "presence"、"engagement"、"reason"。
"presence" 必须是 present、away、resting、unclear 之一。
"engagement" 必须是 engaged、disengaged、unclear 之一。
示例输出：{"presence":"present","engagement":"engaged","reason":"用户在场并保持参与。"}
reason 使用简洁中文。不要添加 Markdown 或任何额外文本。
```
