import Foundation
import StillLoopCore

struct OpenSourceModelDisclosure: Equatable {
    var baseModelID: String
    var baseModelLicenseName: String
    var baseModelLicenseURL: URL
    var ggufRepositoryID: String
    var modelFilenames: [String]
    var localModelPathDescription: String
    var ggufLicenseNoteKey: String
    var runtimeName: String
    var runtimeLicenseName: String
    var runtimeCopyright: String
    var runtimeLicenseResourceName: String
    var manualModelServiceNoteKey: String

    var ggufLicenseNote: String {
        L10n.text(ggufLicenseNoteKey)
    }

    var manualModelServiceNote: String {
        L10n.text(manualModelServiceNoteKey)
    }

    static let builtIn = OpenSourceModelDisclosure(
        baseModelID: "Qwen/Qwen3.5-0.8B",
        baseModelLicenseName: "Apache License 2.0",
        baseModelLicenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3.5-0.8B/blob/main/LICENSE")!,
        ggufRepositoryID: ModelDownloadSpec.builtIn.repoID,
        modelFilenames: ModelDownloadSpec.builtIn.requiredFilenames,
        localModelPathDescription: "Application Support/StillLoop/Models/\(ModelDownloadSpec.builtIn.localSubdirectory)",
        ggufLicenseNoteKey: "openSource.ggufLicenseNote",
        runtimeName: "llama.cpp / ggml-org b9060 macOS arm64 runtime",
        runtimeLicenseName: "MIT License",
        runtimeCopyright: "Copyright (c) 2023-2026 The ggml authors",
        runtimeLicenseResourceName: "LICENSE.llama.cpp",
        manualModelServiceNoteKey: "openSource.manualModelServiceNote"
    )
}
