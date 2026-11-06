import Foundation

enum TranscriptUtils {
    private static let tailWindows = [512 * 1024, 4 * 1024 * 1024]

    // Reads only the end of the transcript, widening the window once if the last message is not there.
    static func findLastMessage(in transcript: URL, extractText: (Substring) -> String?) -> AgentLastMessage? {
        for window in tailWindows {
            guard let tail = readTail(of: transcript, byteCount: window) else { return nil }
            for line in tail.text.split(separator: "\n").reversed() {
                if let text = extractText(line), text.isEmpty == false {
                    return AgentLastMessage(text: text)
                }
            }
            if tail.isWholeFile {
                return nil
            }
        }
        return nil
    }

    private static func readTail(of file: URL, byteCount: Int) -> (text: String, isWholeFile: Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(byteCount) ? size - UInt64(byteCount) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        return (String(decoding: data, as: UTF8.self), offset == 0)
    }
}
