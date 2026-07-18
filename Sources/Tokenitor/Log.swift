import Foundation

/// 启动诊断日志：同时写到 stderr（前台运行可见）和 ~/.tokenitor/launch.log。
/// launch.log 有大小上限，超过即只保留最近的一段，避免无限增长。
/// 文件写入收敛到串行队列：log() 会被主线程与各网络回调线程并发调用，
/// 直接写文件会交错损坏、且把 I/O 压在调用线程上。
private let logMaxBytes = 256 * 1024   // 上限 256KB，超过保留最近一半
private let logQueue = DispatchQueue(label: "tokenitor.log", qos: .utility)

func log(_ msg: String) {
    let line = "[Tokenitor] \(msg)\n"
    FileHandle.standardError.write(Data(line.utf8))
    let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)"
    logQueue.async { appendToLogFile(stamped) }
}

private func appendToLogFile(_ stamped: String) {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dir = home.appendingPathComponent(".tokenitor", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("launch.log")

    // 轮转：超过上限时，只留最近 logMaxBytes/2 的尾部（保留近期事件）。
    if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
       size > logMaxBytes, let data = try? Data(contentsOf: url) {
        try? data.suffix(logMaxBytes / 2).write(to: url)
    }

    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(Data(stamped.utf8)); try? h.close()
    } else {
        try? stamped.data(using: .utf8)?.write(to: url)
    }
}

/// 当前进程真实内存足迹（phys_footprint，与活动监视器「内存」列同口径），MB。
func memFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return 0 }
    return Double(info.phys_footprint) / 1_048_576
}
