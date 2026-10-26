import Foundation

enum LogStoreError: LocalizedError {
    case notALibrary
    case unreadable(String)
    case saveFailed(String)
    case moveIncomplete

    var errorDescription: String? {
        switch self {
        case .notALibrary:
            return "这个文件夹里没有工作日志。"
        case .unreadable(let name):
            return "无法读取 \(name)。已有内容没有被覆盖。"
        case .saveFailed(let name):
            return "无法保存 \(name)。"
        case .moveIncomplete:
            return "事项已经写到新的日期，但从原来的那天移除时失败，原记录仍在。"
        }
    }
}

struct LogStore {
    let root: URL

    private var libraryURL: URL { root.appendingPathComponent("library.json") }
    private var typesURL: URL { root.appendingPathComponent("types.json") }

    func loadLibrary() throws -> LibraryIndex {
        try decode(LibraryIndex.self, from: libraryURL, name: "library.json")
    }

    func saveLibrary(_ library: LibraryIndex) throws {
        try write(library, to: libraryURL, name: "library.json")
    }

    func loadTypes() throws -> [WorkType] {
        if !FileManager.default.fileExists(atPath: typesURL.path) {
            return []
        }
        return try decode([WorkType].self, from: typesURL, name: "types.json")
    }

    func saveTypes(_ types: [WorkType]) throws {
        try write(types, to: typesURL, name: "types.json")
    }

    func loadMonth(_ month: String) throws -> [WorkItem] {
        let url = monthURL(month)
        if !FileManager.default.fileExists(atPath: url.path) {
            return []
        }
        return try decode(MonthFile.self, from: url, name: "\(month).json").items
    }

    func saveMonth(_ month: String, items: [WorkItem]) throws {
        let url = monthURL(month)
        if items.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    throw LogStoreError.saveFailed("\(month).json")
                }
            }
            return
        }
        try write(MonthFile(items: items), to: url, name: "\(month).json")
    }

    func monthsOnDisk() -> [String] {
        let fileManager = FileManager.default
        guard let years = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var months: [String] = []
        for yearURL in years {
            let year = yearURL.lastPathComponent
            guard year.count == 4, Int(year) != nil else { continue }
            guard let files = try? fileManager.contentsOfDirectory(at: yearURL, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "json" {
                let month = file.deletingPathExtension().lastPathComponent
                guard month.count == 2, Int(month) != nil else { continue }
                months.append("\(year)-\(month)")
            }
        }
        return months.sorted()
    }

    func usageCount(typeID: String, subTypeID: String?) -> Int {
        monthsOnDisk().reduce(0) { total, month in
            let items = (try? loadMonth(month)) ?? []
            return total + items.filter { item in
                if let subTypeID {
                    return item.typeId == typeID && item.subTypeId == subTypeID
                }
                return item.typeId == typeID
            }.count
        }
    }

    private func monthURL(_ month: String) -> URL {
        let parts = month.split(separator: "-")
        let year = parts.count == 2 ? String(parts[0]) : "0000"
        let mon = parts.count == 2 ? String(parts[1]) : "00"
        return root.appendingPathComponent(year).appendingPathComponent("\(mon).json")
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL, name: String) throws -> T {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LogStoreError.unreadable(name)
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL, name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw LogStoreError.saveFailed(name)
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".tmp")
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            throw LogStoreError.saveFailed(name)
        }
    }
}
