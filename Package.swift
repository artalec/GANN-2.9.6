// swift-tools-version: 6.0
// Xcode 16 (Swift 6.0). Языковой режим остаётся Swift 5, чтобы перевод не
// превратился в переписывание всего кода под строгий параллелизм.

import PackageDescription

let package = Package(
    name: "GANNPlayer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GANNPlayer", targets: ["GANNPlayer"])
    ],
    targets: [
        .executableTarget(
            name: "GANNPlayer",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        // Тесты для чистых функций: PlaylistOrdering, SelectionManager, Track.clampedTrim.
        // Зависимость тестовой цели от executableTarget поддерживается SwiftPM
        // (testability включается автоматически), отдельная библиотечная
        // цель не нужна.
        .testTarget(
            name: "GANNPlayerTests",
            dependencies: ["GANNPlayer"],
            path: "Tests/GANNPlayerTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
