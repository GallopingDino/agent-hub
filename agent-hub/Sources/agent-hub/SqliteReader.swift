import Foundation
import SQLite3

// Queries that only read; each row holds a column's text, blob or nil.
enum SqliteReader {
    enum Value {
        case text(String)
        case blob(Data)
        case null

        var text: String? {
            if case let .text(value) = self { return value }
            return nil
        }

        var blob: Data? {
            if case let .blob(value) = self { return value }
            return nil
        }
    }

    enum Access {
        // For a database another process keeps locked, at the price of missing its unsaved changes.
        case immutable
        // For a private copy: replaying a write-ahead log needs write access even to read.
        case privateCopy
    }

    static func query(_ path: String, _ sql: String, access: Access) -> [[Value]] {
        let url = URL(fileURLWithPath: path).absoluteString
        let (uri, flags) = access == .immutable ? (url + "?immutable=1", SQLITE_OPEN_READONLY) : (url, SQLITE_OPEN_READWRITE)
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(uri, &database, flags | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return [] }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }

        var rows: [[Value]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { readColumn(statement, $0) })
        }
        return rows
    }

    private static func readColumn(_ statement: OpaquePointer?, _ index: Int32) -> Value {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_TEXT:
            return sqlite3_column_text(statement, index).map { .text(String(cString: $0)) } ?? .null
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            return sqlite3_column_blob(statement, index).map { .blob(Data(bytes: $0, count: count)) } ?? .null
        default:
            return .null
        }
    }
}
