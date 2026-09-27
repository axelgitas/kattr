// swift-tools-version: 6.0
import PackageDescription
import Foundation

let sdkVersion: String = {
    if let env = ProcessInfo.processInfo.environment["SDK_VERSION"], !env.isEmpty {
        return env
    }
    let defaultSDK = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/SDKSettings.json"
    if let data = try? Data(contentsOf: URL(fileURLWithPath: defaultSDK)),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let ver = json["Version"] as? String {
        return ver
    }
    return "27.0"
}()

let package = Package(
    name: "Kattr",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kattr",
            path: "Sources/Search",
            // Same reasoning as the canvas app next door: the whole interface is
            // main-thread by nature, and Swift 6's strict isolation buys nothing
            // here but ceremony.
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-platform_version",
                    "-Xlinker", "macos",
                    "-Xlinker", "14.0",
                    "-Xlinker", sdkVersion
                ])
            ]
        )
    ]
)
