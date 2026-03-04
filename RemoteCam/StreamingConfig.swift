import Foundation

struct StreamingConfig: Codable {
    /// Average bitrate in bits per second (e.g., 2_000_000 for 2 Mbps)
    let bitrate: Int
    /// Frames between keyframes (e.g., 30 = 1 keyframe/sec at 30fps)
    let maxKeyFrameInterval: Int
    /// Target frames per second
    let fps: Int
    /// Encode width in pixels
    let width: Int
    /// Encode height in pixels
    let height: Int

    static let `default` = StreamingConfig(
        bitrate: 2_000_000,
        maxKeyFrameInterval: 30,
        fps: 30,
        width: 1280,
        height: 720
    )

    static func load() -> StreamingConfig {
        guard let url = Bundle.main.url(forResource: "streaming_config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(StreamingConfig.self, from: data) else {
            return .default
        }
        return config
    }
}
