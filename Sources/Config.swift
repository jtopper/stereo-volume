import Foundation

struct Config: Codable {
    var audioDeviceName: String = ""
    var castDeviceName: String  = ""

    // Preserve the snake_case JSON keys from the Go version so existing
    // config files continue to work after the rewrite.
    enum CodingKeys: String, CodingKey {
        case audioDeviceName = "audio_device_name"
        case castDeviceName  = "cast_device_name"
    }

    static var filePath: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("stereo-vol/config.json")
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: filePath),
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return Config() }
        return config
    }

    func save() throws {
        let dir = Config.filePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir,
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try encoder.encode(self).write(to: Config.filePath, options: .atomic)
    }
}
