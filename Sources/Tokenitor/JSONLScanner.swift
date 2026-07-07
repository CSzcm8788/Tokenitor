import Foundation

/// 流式 JSONL 读取：分块（默认 1MB）读文件、按 `\n` 切出**完整行**逐条回调，
/// 返回消费到的新字节偏移——jsonl 只追加不改写，调用方保存 offset 即可做**增量解析**
///（TokenAggregator 每 10 分钟的 tick 从"重读 48h 全量"降为"只读新增"）。
///
/// 两个刻意的行为约定：
///  · 末尾未以换行结束的半行**不消费**（offset 停在它之前），待文件长大后下轮再读——
///    既保证增量偏移正确，也避免解析写到一半的 JSON；
///  · 只在 `\n` 字节处切割：0x0A 不会出现在多字节 UTF-8 序列中间，按块解码始终安全。
enum JSONLScanner {

    /// 从 `offset` 起扫描到文件末尾，每个完整行回调一次；返回新偏移（最后一个完整行之后）。
    /// 文件打不开时原样返回 offset；文件比 offset 短（被截断/轮转）时返回文件长度，
    /// 调用方据此重置自己的累计状态。
    @discardableResult
    static func scan(url: URL, from offset: UInt64 = 0, chunkSize: Int = 1 << 20,
                     line handle: (Substring) -> Void) -> UInt64 {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? fh.close() }
        let end = (try? fh.seekToEnd()) ?? 0
        guard offset < end else { return min(offset, end) }
        try? fh.seek(toOffset: offset)

        var consumed = offset
        var pending = Data()   // 跨块残留的不完整行
        while let chunk = try? fh.read(upToCount: chunkSize), !chunk.isEmpty {
            autoreleasepool {   // 每块一个池：本块的解码/切行/回调里的解析临时对象及时归还
                pending.append(chunk)
                guard let lastNL = pending.lastIndex(of: 0x0A) else { return }
                let completeLen = lastNL - pending.startIndex + 1
                let text = String(decoding: pending.prefix(completeLen), as: UTF8.self)
                consumed += UInt64(completeLen)
                pending.removeFirst(completeLen)
                for l in text.split(separator: "\n", omittingEmptySubsequences: true) {
                    handle(l)
                }
            }
        }
        return consumed
    }
}
