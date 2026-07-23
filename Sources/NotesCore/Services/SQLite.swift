import CSQLite
import Foundation

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct NotesDatabaseError: LocalizedError {
    public let operation: String
    public let message: String

    public var errorDescription: String? {
        "\(operation): \(message)"
    }
}

final class SQLiteConnection {
    private(set) var handle: OpaquePointer?

    init(url: URL, readOnly: Bool = false) throws {
        var database: OpaquePointer?
        let flags = (readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE)) | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &database, flags, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
            if let database {
                sqlite3_close(database)
            }
            throw NotesDatabaseError(operation: "Open database", message: message)
        }

        handle = database
        if !readOnly {
            try execute("PRAGMA foreign_keys = ON;")
            try execute("PRAGMA journal_mode = WAL;")
        }
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    var changes: Int32 {
        sqlite3_changes(handle)
    }

    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(errorPointer)
            throw NotesDatabaseError(operation: "Execute SQL", message: message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw NotesDatabaseError(operation: "Prepare SQL", message: errorMessage)
        }
        return SQLiteStatement(statement: statement, connection: self)
    }

    func transaction<T>(_ work: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let result = try work()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    fileprivate var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
    }
}

final class SQLiteStatement {
    private var statement: OpaquePointer?
    private unowned let connection: SQLiteConnection

    init(statement: OpaquePointer, connection: SQLiteConnection) {
        self.statement = statement
        self.connection = connection
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ value: String, at index: Int32) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw bindingError()
        }
    }

    func bind(_ value: String?, at index: Int32) throws {
        guard let value else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else { throw bindingError() }
            return
        }
        try bind(value, at: index)
    }

    func bind(_ value: Int64, at index: Int32) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
            throw bindingError()
        }
    }

    func bind(_ value: Bool, at index: Int32) throws {
        guard sqlite3_bind_int(statement, index, value ? 1 : 0) == SQLITE_OK else {
            throw bindingError()
        }
    }

    @discardableResult
    func step() throws -> Bool {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw NotesDatabaseError(operation: "Run SQL", message: connection.errorMessage)
        }
    }

    func string(at index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    func optionalString(at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return string(at: index)
    }

    func int64(at index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    func bool(at index: Int32) -> Bool {
        sqlite3_column_int(statement, index) != 0
    }

    func double(at index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    private func bindingError() -> NotesDatabaseError {
        NotesDatabaseError(operation: "Bind SQL value", message: connection.errorMessage)
    }
}
