# 开源许可与模型信息文档

## 功能目标

“开源许可与模型信息”页面向用户披露 StillLoop 分发的内置模型、GGUF 来源和本地运行时许可，并提醒用户手动模型服务不由 StillLoop 分发。

该页面服务三类需求：

- 用户了解本机模型来源。
- App Store 审核了解模型和 runtime 分发边界。
- 开发迭代时保持许可证信息可维护。

## 页面入口

设置页中点击“开源许可与模型信息”进入。页面标题为“设置 / 开源许可与模型信息”。

## 内置模型信息

页面展示：

- 基础模型：`Qwen/Qwen3.5-0.8B`。
- 许可证：Apache License 2.0。
- Qwen 官方许可证链接。
- GGUF 来源：Hugging Face / `twinblade02/Qwen3.5VL-0.8B-ImageExplainer-GGUF`。
- 模型文件列表。
- 本地保存位置。

必需模型文件：

- `Qwen3.5-0.8B-Base.Q4_K_M.gguf`
- `Qwen3.5-0.8B-Base.BF16-mmproj.gguf`

页面说明该 GGUF 仓库作为转换来源；仓库未提供单独 LICENSE 文件，因此同时标注底层 Qwen 官方 Apache 2.0 许可与转换来源。

## 本地运行时信息

页面展示：

- 运行时：llama.cpp / ggml-org b9060 macOS arm64 runtime。
- 许可证：MIT License。
- 版权：Copyright (c) 2023-2026 The ggml authors。
- 许可文件：`LICENSE.llama.cpp`。

完整 MIT 许可文本保留在应用资源 `LICENSE.llama.cpp`。

## 手动模型服务说明

页面说明：

“用户手动配置的本地或在线模型服务不由 StillLoop 分发；请自行确认对应模型、服务和 API 的许可证与使用条款。”

该说明用于区分：

- StillLoop 随应用分发的自带模型与 runtime。
- 用户自行配置的 LM Studio、本机 llama.cpp、OpenAI-compatible 服务或在线 API。

## 维护规则

当以下内容变化时，必须更新本页和对应文档：

- 内置模型仓库。
- 模型文件名。
- 模型许可证。
- llama.cpp runtime 版本或许可证。
- 本地保存路径。
- 是否分发新的第三方依赖。

## 非目标

- 不在此页展示完整第三方依赖清单，除非产品实际新增用户可见的第三方分发责任。
- 不在此页处理用户手动模型的许可证审核。
- 不在此页展示 API Key、服务 URL 或用户配置。

## 验收标准

- 用户能看到模型、runtime 和手动服务三类信息。
- 内置模型许可证和 runtime 许可证明确。
- 页面能从设置页进入，并可返回设置页。
- 许可证文案不暗示 StillLoop 拥有或重新授权用户手动配置的模型。
