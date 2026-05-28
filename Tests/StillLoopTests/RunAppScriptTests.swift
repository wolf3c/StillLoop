import Foundation
import XCTest

final class RunAppScriptTests: XCTestCase {
    func testRunAppForcesSkippingModelDownloadForDevelopmentLaunches() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("\nexport STILLLOOP_SKIP_MODEL_DOWNLOAD=1\n"))
    }

    func testRunAppLaunchesTheAppBundleInsteadOfRawExecutable() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("/usr/bin/open \"${OPEN_ARGS[@]}\""))
        XCTAssertTrue(script.contains("-W\n  \"$APP_DIR\""))
        XCTAssertFalse(script.contains("\n\"$MACOS_DIR/StillLoop\"\n"))
    }

    func testRunAppSignsBundleWithStableDevelopmentIdentifier() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("BUNDLE_IDENTIFIER=\"local.StillLoop.dev\""))
        XCTAssertTrue(script.contains("CODESIGN_IDENTITY=\"${STILLLOOP_CODESIGN_IDENTITY:--}\""))
        XCTAssertTrue(script.contains("DESIGNATED_REQUIREMENT=\"=designated => identifier \\\"$BUNDLE_IDENTIFIER\\\"\""))
        XCTAssertTrue(script.contains("<string>$BUNDLE_IDENTIFIER</string>"))
        XCTAssertTrue(script.contains("CODESIGN_ARGS=(--force --sign \"$CODESIGN_IDENTITY\" --identifier \"$BUNDLE_IDENTIFIER\")"))
        XCTAssertTrue(script.contains("if [[ \"$RUN_APP_STORE_SANDBOX\" != \"1\" ]]; then"))
        XCTAssertTrue(script.contains("CODESIGN_ARGS+=(--deep)"))
        XCTAssertTrue(script.contains("if [[ \"$CODESIGN_IDENTITY\" == \"-\" ]]; then"))
        XCTAssertTrue(script.contains("CODESIGN_ARGS+=(--requirements \"$DESIGNATED_REQUIREMENT\")"))
        XCTAssertTrue(script.contains("/usr/bin/codesign \"${CODESIGN_ARGS[@]}\" \"$APP_DIR\""))
    }

    func testRunAppEmbedsAndSignsBundledLlamaServerHelper() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("HELPERS_DIR=\"$CONTENTS_DIR/Helpers\""))
        XCTAssertTrue(script.contains("RUNTIME_SOURCE_DIR=\"$ROOT_DIR/Sources/StillLoop/Resources/Runtime\""))
        XCTAssertTrue(script.contains("RUNTIME_SOURCE=\"$ROOT_DIR/Sources/StillLoop/Resources/Runtime/llama-server\""))
        XCTAssertTrue(script.contains("HELPER_EXECUTABLE_NAME=\"stillloop-llama-server\""))
        XCTAssertTrue(script.contains("cp \"$RUNTIME_SOURCE\" \"$HELPERS_DIR/$HELPER_EXECUTABLE_NAME\""))
        XCTAssertTrue(script.contains("cp -R \"$RUNTIME_SOURCE_DIR\"/lib*.dylib \"$HELPERS_DIR\"/"))
        XCTAssertTrue(script.contains("find \"$HELPERS_DIR\" -type f \\( -name \"$HELPER_EXECUTABLE_NAME\" -o -name \"lib*.dylib\" \\) -exec chmod 755 {} \\;"))
        XCTAssertTrue(script.contains("find \"$HELPERS_DIR\" -type f \\( -name \"$HELPER_EXECUTABLE_NAME\" -o -name \"lib*.dylib\" \\) -exec /usr/bin/codesign --force --sign \"$CODESIGN_IDENTITY\" {} \\;"))
    }

    func testRunAppCanUseSandboxEntitlementsWithoutChangingDevelopmentIdentity() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("RUN_APP_STORE_SANDBOX=\"${STILLLOOP_RUN_APP_STORE_SANDBOX:-0}\""))
        XCTAssertTrue(script.contains("ENTITLEMENTS_FILE=\"$ROOT_DIR/.build/StillLoop-run.generated.entitlements\""))
        XCTAssertTrue(script.contains("HELPER_ENTITLEMENTS_FILE=\"$ROOT_DIR/.build/StillLoop-run-helper.generated.entitlements\""))
        XCTAssertTrue(script.contains("BUNDLE_IDENTIFIER=\"local.StillLoop.dev\""))
        XCTAssertTrue(script.contains("<string>StillLoop Dev</string>"))
        XCTAssertTrue(script.contains("<key>com.apple.security.app-sandbox</key>"))
        XCTAssertTrue(script.contains("<key>com.apple.security.device.camera</key>"))
        XCTAssertTrue(script.contains("<key>com.apple.security.network.client</key>"))
        XCTAssertTrue(script.contains("<key>com.apple.security.automation.apple-events</key>"))
        XCTAssertTrue(script.contains("<key>com.apple.security.inherit</key>"))
        XCTAssertTrue(script.contains("CODESIGN_ARGS+=(--entitlements \"$ENTITLEMENTS_FILE\")"))
        XCTAssertTrue(script.contains("/usr/bin/codesign --force --sign \"$CODESIGN_IDENTITY\" --entitlements \"$HELPER_ENTITLEMENTS_FILE\" {} \\;"))
        XCTAssertFalse(script.contains("<key>com.apple.security.network.server</key>"))
    }

    func testRunAppUsesDistinctDevelopmentDisplayName() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("<key>CFBundleDisplayName</key>"))
        XCTAssertTrue(script.contains("<string>StillLoop Dev</string>"))
        XCTAssertTrue(script.contains("<key>CFBundleName</key>"))
        XCTAssertTrue(script.contains("<string>StillLoop Dev</string>"))
    }

    func testRunAppDeclaresAppleEventsUsageForBrowserMetadata() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("<key>NSAppleEventsUsageDescription</key>"))
        XCTAssertTrue(script.contains("StillLoop reads the active browser tab title and URL as local focus context when available."))
    }

    func testRunAppForwardsLocalModelEnvironmentIntoLaunchServices() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("--env \"STILLLOOP_SKIP_MODEL_DOWNLOAD=$STILLLOOP_SKIP_MODEL_DOWNLOAD\""))
        XCTAssertTrue(script.contains("--env \"STILLLOOP_USE_LOCAL_LLM=$STILLLOOP_USE_LOCAL_LLM\""))
        XCTAssertTrue(script.contains("--env \"STILLLOOP_LLM_BASE_URL=$STILLLOOP_LLM_BASE_URL\""))
        XCTAssertTrue(script.contains("--env \"STILLLOOP_LLM_MODEL=$STILLLOOP_LLM_MODEL\""))
        XCTAssertTrue(script.contains("--env \"STILLLOOP_RUN_PROMPT_CACHE_PROBE=$STILLLOOP_RUN_PROMPT_CACHE_PROBE\""))
        XCTAssertTrue(script.contains("--env \"STILLLOOP_DISABLE_PROMPT_CACHE=$STILLLOOP_DISABLE_PROMPT_CACHE\""))
        XCTAssertTrue(script.contains("--env \"STILLLOOP_BUNDLED_RUNTIME=$STILLLOOP_BUNDLED_RUNTIME\""))
    }

    func testRunAppForwardsPathForLocalMLXRuntimeDependencies() throws {
        let script = try String(contentsOfFile: "scripts/run-app.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("MLX_RUNTIME_DIR=\"$ROOT_DIR/.build/mlx-runtime\""))
        XCTAssertTrue(script.contains("if [[ -x \"$MLX_RUNTIME_DIR/bin/python3\" ]]; then"))
        XCTAssertTrue(script.contains("export PATH=\"$MLX_RUNTIME_DIR/bin:$PATH\""))
        XCTAssertTrue(script.contains("--env \"PATH=$PATH\""))
    }

    func testSetupMLXRuntimeInstallsProjectLocalMLXVLMEnvironment() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: "scripts/setup-mlx-runtime.sh"))

        let script = try String(contentsOfFile: "scripts/setup-mlx-runtime.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("RUNTIME_DIR=\"$ROOT_DIR/.build/mlx-runtime\""))
        XCTAssertTrue(script.contains("python3 -m venv \"$RUNTIME_DIR\""))
        XCTAssertTrue(script.contains("\"$RUNTIME_DIR/bin/python3\" -m pip install --upgrade pip"))
        XCTAssertTrue(script.contains("\"$RUNTIME_DIR/bin/python3\" -m pip install --upgrade mlx-vlm"))
        XCTAssertTrue(script.contains("STILLLOOP_INSTALL_RAPID_MLX"))
        XCTAssertTrue(script.contains("pip install --upgrade rapid-mlx"))
        XCTAssertTrue(script.contains("\"$RUNTIME_DIR/bin/python3\" -c \"import mlx_vlm\""))
    }

    func testAppStoreEntitlementsUseMinimumRequiredSandboxCapabilities() throws {
        let entitlements = try String(contentsOfFile: "Config/StillLoop-AppStore.entitlements", encoding: .utf8)

        XCTAssertTrue(entitlements.contains("<key>com.apple.security.app-sandbox</key>"))
        XCTAssertTrue(entitlements.contains("<key>com.apple.security.device.camera</key>"))
        XCTAssertTrue(entitlements.contains("<key>com.apple.security.network.client</key>"))
        XCTAssertFalse(entitlements.contains("<key>com.apple.security.network.server</key>"))
        XCTAssertTrue(entitlements.contains("<key>com.apple.security.automation.apple-events</key>"))
    }

    func testAppStorePackageScriptUsesRegisteredAppStoreBundleDefaults() throws {
        let script = try String(contentsOfFile: "scripts/build-app-store-package.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("BUNDLE_IDENTIFIER=\"${STILLLOOP_BUNDLE_IDENTIFIER:-com.super-tree.stillloop}\""))
        XCTAssertTrue(script.contains("MARKETING_VERSION=\"${STILLLOOP_MARKETING_VERSION:-1.0}\""))
        XCTAssertTrue(script.contains("<string>$BUNDLE_IDENTIFIER</string>"))
    }

    func testAppStorePackageScriptRequiresDistributionSigningIdentities() throws {
        let script = try String(contentsOfFile: "scripts/build-app-store-package.sh", encoding: .utf8)

        XCTAssertTrue(script.contains(": \"${STILLLOOP_APP_SIGN_IDENTITY:?Set STILLLOOP_APP_SIGN_IDENTITY"))
        XCTAssertTrue(script.contains(": \"${STILLLOOP_INSTALLER_SIGN_IDENTITY:?Set STILLLOOP_INSTALLER_SIGN_IDENTITY"))
        XCTAssertTrue(script.contains("STATIC_ENTITLEMENTS_FILE=\"$ROOT_DIR/Config/StillLoop-AppStore.entitlements\""))
        XCTAssertTrue(script.contains("ENTITLEMENTS_FILE=\"$OUTPUT_DIR/StillLoop-AppStore.generated.entitlements\""))
        XCTAssertTrue(script.contains("HELPER_ENTITLEMENTS_FILE=\"$OUTPUT_DIR/StillLoop-Helper.generated.entitlements\""))
        XCTAssertTrue(script.contains("/usr/bin/codesign --force --options runtime --sign \"$STILLLOOP_APP_SIGN_IDENTITY\" --entitlements \"$ENTITLEMENTS_FILE\" \"$APP_DIR\""))
        XCTAssertFalse(script.contains("/usr/bin/codesign --force --deep --options runtime --sign \"$STILLLOOP_APP_SIGN_IDENTITY\" --entitlements \"$ENTITLEMENTS_FILE\" \"$APP_DIR\""))
        XCTAssertTrue(script.contains("/usr/bin/codesign --verify --strict --deep --verbose=2 \"$APP_DIR\""))
        XCTAssertTrue(script.contains("/usr/bin/productbuild --sign \"$STILLLOOP_INSTALLER_SIGN_IDENTITY\" --component \"$APP_DIR\" /Applications \"$PKG_PATH\""))
    }

    func testAppStorePackageScriptEmbedsProvisioningProfileBeforeSigning() throws {
        let script = try String(contentsOfFile: "scripts/build-app-store-package.sh", encoding: .utf8)

        XCTAssertTrue(script.contains(": \"${STILLLOOP_PROVISIONING_PROFILE:?Set STILLLOOP_PROVISIONING_PROFILE"))
        XCTAssertTrue(script.contains("cp \"$STILLLOOP_PROVISIONING_PROFILE\" \"$CONTENTS_DIR/embedded.provisionprofile\""))
        XCTAssertTrue(script.range(of: "cp \"$STILLLOOP_PROVISIONING_PROFILE\" \"$CONTENTS_DIR/embedded.provisionprofile\"")!.lowerBound < script.range(of: "/usr/bin/codesign --force --options runtime --sign \"$STILLLOOP_APP_SIGN_IDENTITY\" --entitlements \"$ENTITLEMENTS_FILE\" \"$APP_DIR\"")!.lowerBound)
    }

    func testAppStorePackageScriptSignsApplicationIdentifierEntitlement() throws {
        let script = try String(contentsOfFile: "scripts/build-app-store-package.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("TEAM_IDENTIFIER=\"${STILLLOOP_TEAM_IDENTIFIER:-FUNQ8PQ8CX}\""))
        XCTAssertTrue(script.contains("<key>com.apple.application-identifier</key>"))
        XCTAssertTrue(script.contains("<string>$TEAM_IDENTIFIER.$BUNDLE_IDENTIFIER</string>"))
        XCTAssertTrue(script.contains("<key>com.apple.developer.team-identifier</key>"))
        XCTAssertTrue(script.contains("<string>$TEAM_IDENTIFIER</string>"))
    }

    func testAppStorePackageScriptClearsExtendedAttributesBeforeSigning() throws {
        let script = try String(contentsOfFile: "scripts/build-app-store-package.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("/usr/bin/xattr -cr \"$APP_DIR\""))
        XCTAssertTrue(script.range(of: "/usr/bin/xattr -cr \"$APP_DIR\"")!.lowerBound < script.range(of: "/usr/bin/codesign --force --options runtime --sign \"$STILLLOOP_APP_SIGN_IDENTITY\" --entitlements \"$ENTITLEMENTS_FILE\" \"$APP_DIR\"")!.lowerBound)
    }

    func testAppStorePackageScriptEmbedsAndSignsBundledLlamaServerHelper() throws {
        let script = try String(contentsOfFile: "scripts/build-app-store-package.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("HELPERS_DIR=\"$CONTENTS_DIR/Helpers\""))
        XCTAssertTrue(script.contains("RUNTIME_SOURCE_DIR=\"$ROOT_DIR/Sources/StillLoop/Resources/Runtime\""))
        XCTAssertTrue(script.contains("RUNTIME_SOURCE=\"$ROOT_DIR/Sources/StillLoop/Resources/Runtime/llama-server\""))
        XCTAssertTrue(script.contains("HELPER_EXECUTABLE_NAME=\"stillloop-llama-server\""))
        XCTAssertTrue(script.contains("cp \"$RUNTIME_SOURCE\" \"$HELPERS_DIR/$HELPER_EXECUTABLE_NAME\""))
        XCTAssertTrue(script.contains("cp -R \"$RUNTIME_SOURCE_DIR\"/lib*.dylib \"$HELPERS_DIR\"/"))
        XCTAssertTrue(script.contains("find \"$HELPERS_DIR\" -type f \\( -name \"$HELPER_EXECUTABLE_NAME\" -o -name \"lib*.dylib\" \\) -exec chmod 755 {} \\;"))
        XCTAssertTrue(script.contains("find \"$HELPERS_DIR\" -type f \\( -name \"$HELPER_EXECUTABLE_NAME\" -o -name \"lib*.dylib\" \\) -exec /usr/bin/codesign --force --options runtime --sign \"$STILLLOOP_APP_SIGN_IDENTITY\" --entitlements \"$HELPER_ENTITLEMENTS_FILE\" {} \\;"))
        XCTAssertTrue(script.contains("<key>com.apple.security.inherit</key>"))
        XCTAssertFalse(script.contains("<key>com.apple.security.network.server</key>"))
    }
}
