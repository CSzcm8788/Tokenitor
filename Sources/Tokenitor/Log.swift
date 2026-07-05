import Foundation

/// 启动诊断日志：同时写到 stderr（前台运行可见）和 ~/.tokenitor/launch.log。
/// launch.log 有大小上限，超过即只保留最近的一段，避免无限增长。
private let logMaxBytes = 256 * 1024   // 上限 256KB，超过保留最近一半

func log(_ msg: String) {
    let line = "[Tokenitor] \(msg)\n"
    FileHandle.standardError.write(Data(line.utf8))
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dir = home.appendingPathComponent(".tokenitor", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("launch.log")

    // 轮转：超过上限时，只留最近 logMaxBytes/2 的尾部（保留近期事件）。
    if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
       size > logMaxBytes, let data = try? Data(contentsOf: url) {
        try? data.suffix(logMaxBytes / 2).write(to: url)
    }

    let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(Data(stamped.utf8)); try? h.close()
    } else {
        try? stamped.data(using: .utf8)?.write(to: url)
    }
}
