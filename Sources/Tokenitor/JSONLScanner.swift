import Foundation

/// 流式 JSONL 读取：分块读文件、按换行切分逐行回调，**不把整个文件载入内存**。
/// Claude Code / Codex 的活跃会话文件可以长到上百 MB，整读字符串是此前的主要内存峰值来源。
enum JSONLScanner {

    /// 逐行回调（行内容为去掉换行符的字符串）。回调里把 stop 置 true 可提前终止。
    static func forEachLine(of url: URL, chunkSize: Int = 1 << 20,
                            _ body: (String, _ stop: inout Bool) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        var buffer = Data()
        var stop = false
        while !stop, let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)
            var start = buffer.startIndex
            while !stop, let nl = buffer[start...].firstIndex(of: 0x0A) {
                if nl > start {
                    body(String(decoding: buffer[start..<nl], as: UTF8.self), &stop)
                }
                start = buffer.index(after: nl)
            }
            if stop { return }
            buffer = Data(buffer[start...])   // 留下未完整的尾行，重置索引空间
        }
        if !stop, !buffer.isEmpty {
            body(String(decoding: buffer, as: UTF8.self), &stop)
        }
    }
}
