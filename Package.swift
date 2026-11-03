// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "GetTheCamera",
	platforms: [.macOS(.v14)],
	products: [
		.executable(name: "GetTheCamera", targets: ["GetTheCamera"]),
		.executable(name: "GetTheCameraInstaller", targets: ["GetTheCameraInstaller"]),
	],
	dependencies: [
		.package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack", exact: "3.8.5"),
	],
	targets: [
		.target(
			name: "GetTheCameraObjCSupport",
			path: "Sources/GetTheCameraObjCSupport"
		),
		.executableTarget(
			name: "GetTheCameraInstaller",
			path: "Sources/GetTheCameraInstaller"
		),
		.executableTarget(
			name: "GetTheCamera",
			dependencies: [
				.product(name: "CocoaLumberjackSwift", package: "CocoaLumberjack"),
				"GetTheCameraObjCSupport",
			],
			path: "Sources/GetTheCamera",
			linkerSettings: [
				.linkedLibrary("sqlite3"),
				.unsafeFlags([
					"-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
					"-Xlinker", "-rpath", "-Xlinker", "@executable_path",
				]),
			]
		),
		.testTarget(
			name: "GetTheCameraTests",
			dependencies: ["GetTheCamera"],
			path: "Tests/GetTheCameraTests",
			linkerSettings: [
				.unsafeFlags([
					"-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../..",
				]),
			]
		),
	]
)
