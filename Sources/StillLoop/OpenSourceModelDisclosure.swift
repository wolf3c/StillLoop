import Foundation
import StillLoopCore

struct OpenSourceModelDisclosure: Equatable {
    var baseModelID: String
    var baseModelLicenseName: String
    var baseModelLicenseURL: URL
    var ggufRepositoryID: String
    var modelFilenames: [String]
    var localModelPathDescription: String
    var ggufLicenseNote: String
    var runtimeName: String
    var runtimeLicenseName: String
    var runtimeCopyright: String
    var runtimeLicenseResourceName: String
    var manualModelServiceNote: String

    static let builtIn = OpenSourceModelDisclosure(
        baseModelID: "Qwen/Qwen3.5-0.8B",
        baseModelLicenseName: "Apache License 2.0",
        baseModelLicenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3.5-0.8B/blob/main/LICENSE")!,
        ggufRepositoryID: ModelDownloadSpec.builtIn.repoID,
        modelFilenames: ModelDownloadSpec.builtIn.requiredFilenames,
        localModelPathDescription: "Application Support/StillLoop/Models/\(ModelDownloadSpec.builtIn.localSubdirectory)",
        ggufLicenseNote: "该 GGUF 仓库作为转换来源；仓库未提供单独 LICENSE 文件，因此页面同时标注底层 Qwen 官方 Apache 2.0 许可与转换来源。",
        runtimeName: "llama.cpp / ggml-org b9060 macOS arm64 runtime",
        runtimeLicenseName: "MIT License",
        runtimeCopyright: "Copyright (c) 2023-2026 The ggml authors",
        runtimeLicenseResourceName: "LICENSE.llama.cpp",
        manualModelServiceNote: "用户手动配置的本地或在线模型服务不由 StillLoop 分发；请自行确认对应模型、服务和 API 的许可证与使用条款。"
    )
}
