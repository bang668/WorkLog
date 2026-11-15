import Foundation

enum WorkStamp {
    static func isoNow(_ date: Date = Date()) -> String {
        formatter.string(from: date)
    }

    static func clock(_ date: Date = Date()) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = TimeZone(secondsFromGMT: 0)
        clock.dateFormat = "HHmmss"
        return clock.string(from: date)
    }

    static func isCanonical(_ value: String) -> Bool {
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

enum Inbox {
    struct Payload: Codable {
        var date: String
        var generatedAt: String?
        var materialTs: String?
        var ops: [Op]
    }

    struct Op: Codable {
        var op: String
        var id: String?
        var description: String?
        var note: String?
        var typeId: String?
        var subTypeId: String?
        var source: String?
        var materialTs: String?
    }

    struct Problem: Error, Equatable {
        var message: String
    }

    static func fileDay(_ url: URL) -> String {
        url.deletingPathExtension().deletingPathExtension().lastPathComponent
    }

    static func apply(ops: [Op], date: String, to items: [WorkItem], makeID: () -> String) throws -> [WorkItem] {
        var items = items
        for op in ops {
            switch op.op {
            case "new":
                guard op.id == nil else { throw Problem(message: "新增事项不能自带 id。") }
                let description = op.description ?? ""
                guard description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    throw Problem(message: "新增事项没有描述。")
                }
                let order = (items.filter { $0.date == date }.map(\.order).max() ?? -1) + 1
                items.append(WorkItem(
                    id: makeID(),
                    date: date,
                    description: description,
                    note: op.note ?? "",
                    typeId: op.typeId ?? "",
                    subTypeId: op.subTypeId ?? "",
                    order: order,
                    source: op.source,
                    materialTs: op.materialTs
                ))
            case "update":
                guard let id = op.id, id.isEmpty == false else {
                    throw Problem(message: "更新缺少 id。")
                }
                guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
                guard let incoming = op.materialTs, WorkStamp.isCanonical(incoming) else { continue }
                if let current = items[index].materialTs, WorkStamp.isCanonical(current), current >= incoming {
                    continue
                }
                if let description = op.description { items[index].description = description }
                if let note = op.note { items[index].note = note }
                if let typeId = op.typeId { items[index].typeId = typeId }
                if let subTypeId = op.subTypeId { items[index].subTypeId = subTypeId }
                if let source = op.source { items[index].source = source }
                items[index].materialTs = incoming
            case "delete":
                guard let id = op.id, id.isEmpty == false else {
                    throw Problem(message: "删除缺少 id。")
                }
                guard let target = items.first(where: { $0.id == id }), target.source != nil else {
                    return items
                }
                items.removeAll { $0.id == id }
            default:
                continue
            }
        }
        return items
    }
}
