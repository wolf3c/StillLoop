# 自有模型设置文档

## 功能目标

自有模型是 StillLoop 的默认模型路径。它让普通用户无需配置外部服务，即可在本机完成专注状态评估。

当前自有模型由两部分组成：

- GGUF 模型文件。
- 打包在应用内的 llama.cpp runtime。

## 页面入口

用户可从以下位置进入模型准备页：

- 首次设置流程。
- 顶部“缺少模型设置”或“模型下载中”入口。
- 设置页中的“模型设置”。
- 手动模型不可用或自带模型运行失败后的引导。

## 默认选择

模型准备页默认选择“应用自带模型”。说明文案：

“StillLoop 默认使用应用自带模型评估专注状态。你也可以手动连接本地或线上 OpenAI-compatible HTTP 模型服务。”

该默认选择不能被误认为“基础规则”。自带模型、手动模型和基础规则是三个不同层次：

- 自带模型：默认 LLM 路径。
- 手动模型：用户配置的 HTTP/online LLM 路径。
- 基础规则：模型不可用或用户跳过下载时的 fallback。

## 模型文件

内置模型下载来源：

`twinblade02/Qwen3.5VL-0.8B-ImageExplainer-GGUF`

必需文件：

- `Qwen3.5-0.8B-Base.Q4_K_M.gguf`
- `Qwen3.5-0.8B-Base.BF16-mmproj.gguf`

保存位置：

`~/Library/Application Support/StillLoop/Models/Qwen3.5VL-0.8B-ImageExplainer-GGUF/`

总下载大小约 737 MB。

## 下载状态

模型准备页和任务输入页会展示下载状态：

- 未检查：尚未确认本地模型文件。
- 尚未下载：可开始下载或继续使用其他路径。
- 正在下载：展示当前文件和进度。
- 下载已暂停：可继续下载或取消。
- 下载失败：提示检查网络可访问 Hugging Face 后重试。
- 已准备好：模型文件已在本机。
- 已跳过下载：开发运行中通过 `STILLLOOP_SKIP_MODEL_DOWNLOAD=1` 跳过。

下载支持暂停、取消、继续和重试。未完成的临时文件会被清理。

## runtime 启动

自有模型 runtime 使用应用内打包的 `stillloop-llama-server`。开发和 App Store 包会把 runtime 复制到 app bundle 的 `Contents/Helpers/stillloop-llama-server`。

运行时使用 Unix domain socket，不依赖 TCP localhost server。因此 Mac App Store 构建不需要 `com.apple.security.network.server` entitlement。

主要启动参数：

- 模型文件：主 GGUF。
- 视觉投影文件：mmproj。
- context size：12288。
- parallel slots：3。
- GPU layers：99。
- KV cache：`q4_1`。
- prompt cache：默认启用。

## 主页预热

当用户进入任务输入主页、选择自带模型、模型文件已下载且当前空闲时，应用会后台预热自带模型。预热成功后状态显示“自带模型：已预热”。

预热包括：

- 启动 runtime。
- 建立三个 LLM engine：用户在场、任务匹配、任务进展。
- 预热 prompt cache。
- 可选运行 prompt cache probe 并记录诊断指标。

## 开始任务时的检查

如果选择自带模型但文件未下载，点击开始专注会弹出下载提示。用户可以：

- 开始下载。
- 暂不下载并使用基础规则开始。

如果模型文件存在，首次评估前会确认 runtime 可用。

## 失败与 fallback

自带模型可能失败的情况：

- 缺少 `stillloop-llama-server`。
- 缺少主模型文件。
- 缺少视觉投影文件。
- runtime 启动失败。
- 图片输入不可用。
- readiness 探测失败。
- 推理超时、连接失败、HTTP 异常、空响应或 JSON 解析失败。

失败后产品行为：

- 状态文案显示具体失败类型。
- 当前评估回退到基础规则。
- 记录 `model_issue_detected`。
- 必要时路由回模型设置页。

## 产品风险

- 首次下载体积较大，用户可能放弃。
- 自带模型质量和延迟直接影响提醒准确度。
- 图片输入不可用时，专注判断会明显降级。
- runtime 生命周期必须避免重复 helper 进程。

## 验收标准

- 默认路径是应用自带模型。
- 未下载时用户能清楚看到下载状态和替代路径。
- 已下载时进入主页会后台预热。
- 自带模型失败时不会阻塞专注流程，必须可回退基础规则。
- 设置页和隐私区能反映当前自带模型状态。
