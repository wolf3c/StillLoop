# StillLoop 产品文档目录

本目录记录 StillLoop 当前产品形态。文档以现有 macOS App 代码为准，用于后续优化迭代、评审、测试和 App Store 提交流程。

## 核心文档

- [总产品文档](./product-overview.md)
- [主页与任务专注流程](./home-and-focus-flow.md)
- [新用户首次打开首页](./first-run-home.md)
- [权限获取引导](./permissions.md)
- [自有模型设置](./built-in-model-settings.md)
- [HTTP local 模型设置](./local-http-model.md)
- [设置页面其他功能](./settings-other-features.md)
- [开源许可与模型信息](./open-source-disclosure.md)

## LLM 流程文档

- [LLM 总评估编排](./llm/focus-evaluation-orchestration.md)
- [用户在场状态评估](./llm/user-presence-evaluation.md)
- [屏幕任务匹配评估](./llm/task-alignment-evaluation.md)
- [任务进展评估](./llm/task-progress-evaluation.md)
- [任务相关目标判断](./llm/task-relevant-target-evaluation.md)
- [复盘评语生成](./llm/session-review-comment-generation.md)

## 当前产品定位

StillLoop 是一款本地优先的 macOS 专注辅助应用。用户输入当前任务后，应用读取本机上下文，在本机模型或用户手动配置的 OpenAI-compatible 模型中判断当前活动是否支持任务，并在跑偏、停滞、离开或休息等状态下给出轻提醒。

产品边界：

- 不做云端 AI 调用作为默认路径。
- 不做团队监控、员工管理或统计面板。
- 不阻断网站或应用。
- 不保存截图、摄像头原图或照片。
- 只在用户开始专注任务后采集必要上下文。
- 结束后给出本机复盘摘要，帮助用户理解本次专注过程。
