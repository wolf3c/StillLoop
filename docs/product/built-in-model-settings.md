# 自有模型设置文档

## 功能目标

自有模型是 StillLoop 的默认模型路径。它让普通用户无需配置外部服务，即可在本机完成专注状态评估。

当前自有模型由两部分组成：

- GGUF 模型文件。
- 内部可切换的本地 runtime；当前默认使用打包在应用内的 llama.cpp runtime，MLX 仅作为内部本机实验后端保留。

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

自有模型 runtime 支持内部三套后端：`llama.cpp`、`mlx`、`rapid-mlx`。这个切换不暴露给用户设置；用户可见模型来源仍然只有自带模型、手动模型和基础规则。

当前默认后端是打包在应用内的 llama.cpp runtime。切换后端用于本机开发比对时可通过 `STILLLOOP_BUNDLED_RUNTIME` 环境变量指定，不改动用户设置页。可取值：

- `llamaCpp`（默认）
- `mlx`（走 `mlx_vlm.server`）
- `rapidMlx`（走 `rapid-mlx serve`）

当环境变量未设置或取值非法时回退到默认 `llamaCpp`。

`llama.cpp` 后端使用应用内打包的 `stillloop-llama-server`。开发和 App Store 包会把 runtime 复制到 app bundle 的 `Contents/Helpers/stillloop-llama-server`。

`llama.cpp` 后端使用 Unix domain socket，不依赖 TCP localhost server。因此 Mac App Store 构建不需要 `com.apple.security.network.server` entitlement。MLX/rapid-mlx 路径属于开发测评路径，不作为 App Store 打包路径；`.build/mlx-runtime` 也不会被复制进正式包。

## MLX 与 Rapid-MLX 开发测评后端

MLX 后端使用本机 `mlx_vlm.server` 风格的 OpenAI-compatible 服务，模型为 `mlx-community/Qwen3.5-0.8B-4bit`。该路径只用于本机实测，不把 Python、MLX 或 `mlx-vlm` 依赖打进 App Store 包。

MLX 本机实测 runtime 默认开启 in-memory APC（Automatic Prefix Caching），用于观察固定 prompt 前缀在真实 focus session 中的 prefill 收益。该开关是内部代码常量，不暴露给用户设置；默认不配置 `APC_DISK_PATH`，因此不会启用 APC disk cache 或写入 prompt/KV 缓存文件。

Rapid-MLX 后端优先复用本机已下载的 MLX Hugging Face snapshot（若存在），避免重复下载：

`rapid-mlx serve <模型路径或模型ID> --mllm --host 127.0.0.1 --port <ephemeral> --max-tokens 900`

默认行为：

- 若本机存在 HF 缓存目录 `~/.cache/huggingface/hub/models--mlx-community--Qwen3.5-0.8B-4bit` 且 `refs/main` 指向可用 snapshot，会优先用该 snapshot 路径启动（`models--mlx-community--Qwen3.5-0.8B-4bit/snapshots/<hash>`），避免重复下载。
- 如果 HF 缓存不存在，再尝试用内置 GGUF 路径 `~/Library/Application Support/StillLoop/Models/Qwen3.5VL-0.8B-ImageExplainer-GGUF/Qwen3.5-0.8B-Base.Q4_K_M.gguf`。
- 如果两个本地源都不可用，回退到 `mlx-community/Qwen3.5-0.8B-4bit` 远程模型ID。
- 可通过 `STILLLOOP_RAPID_MLX_MODEL` 强制覆盖为自定义模型路径/ID（例如本地路径）。

本机 MLX / Rapid-MLX 实测前建议先跑一次：

```sh
scripts/setup-mlx-runtime.sh
```

该脚本会创建 `.build/mlx-runtime`，并在其中安装 `mlx-vlm`；若需要可再加 `STILLLOOP_INSTALL_RAPID_MLX=1` 安装 `rapid-mlx`。`scripts/run-app.sh` 在 `STILLLOOP_BUNDLED_RUNTIME=rapidMlx` 时会自动确保 `rapid-mlx` 已安装；当检测到 `.build/mlx-runtime/bin/python3` 时也会把该 venv 的 `bin` 放到转发给 app 的 `PATH` 最前面，因此 runtime 启动命令优先使用项目本地依赖，而不是系统 Python。

启动方式示例：

```sh
STILLLOOP_BUNDLED_RUNTIME=mlx STILLLOOP_SKIP_MODEL_DOWNLOAD=1 scripts/run-app.sh
STILLLOOP_BUNDLED_RUNTIME=rapidMlx STILLLOOP_SKIP_MODEL_DOWNLOAD=1 scripts/run-app.sh
```

MLX 或 Rapid-MLX 启动、readiness、图片能力探测失败时，应用会停止该进程并自动回退到 llama.cpp 后端。诊断日志会记录实际使用的 `bundledRuntimeKind`，如果发生自动回退也会记录 `fallbackRuntimeKind`；MLX 路径还会记录 `mlxAPCEnabled`，避免把 llama.cpp 回退结果误判为 MLX 实测结果。

llama.cpp 主要启动参数：

- 模型文件：主 GGUF。
- 视觉投影文件：mmproj。
- context size：16384，总 context 由 llama-server 分配给 parallel slots。
- parallel slots：4，用于给不同 prompt family 保留独立 cache slot；App 层 LLM 调用仍由全局 gate 保持 1 并发。
- GPU layers：99。
- logical batch size：2048。
- physical microbatch size：2048。
- flash attention：不显式设置 `--flash-attn`，使用 llama.cpp 默认策略。
- KV cache：`q4_1`。
- memory lock：启用 `--mlock`，请求系统尽量让模型和 runtime 相关内存常驻，减少内存压缩或换页造成的推理长尾延迟；代价是常驻内存压力更高，低内存环境下可能影响系统余量。
- prompt cache：默认启用。

内置模型请求使用 Qwen 官方推荐的非思考 VL 采样参数：`temperature=0.7`、`top_p=0.8`、`top_k=20`、`min_p=0.0`、`presence_penalty=1.5`、`repeat_penalty=1.0`。其中 `repeat_penalty` 是 llama.cpp 对 Qwen 推荐 `repetition_penalty` 的对应请求字段。

当前配置是多 slot prompt cache 实验配置，每个 slot 约 4096 context。内置 llama.cpp 请求会显式绑定 slot：presence=0、alignment=1、progress=2、target judgment 和 session review comment 共用 auxiliary=3，并在请求体发送 `id_slot` 与 `cache_prompt=true`。诊断日志会输出 `*LLMSlotID`，并继续用 `*CacheN`、`*CachedTokens`、`*PromptMS`、`*DurationMS` 判断真实收益。代价是 KV/context 常驻内存压力高于单槽配置；如果 `--cache-reuse 512` 或 `2048 / 2048` 使 cache 掉回 0，或内存/长尾明显恶化，需要回退到上一版不显式设置 batch / microbatch 且 `--cache-reuse 64` 的配置。

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
