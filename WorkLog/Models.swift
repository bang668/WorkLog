import Foundation

struct WorkItem: Codable, Identifiable, Equatable {
    var id: String
    var date: String
    var description: String
    var note: String
    var typeId: String
    var subTypeId: String
    var order: Int
}

struct SubType: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var order: Int
}

struct WorkType: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var order: Int
    var children: [SubType]
}

struct LibraryIndex: Codable, Equatable {
    var startMonth: String
    var openedMonths: [String]
}

struct MonthFile: Codable, Equatable {
    var items: [WorkItem]
}

struct ClipboardPayload: Codable, Equatable {
    var description: String
    var note: String
    var typeId: String
    var subTypeId: String
}

enum CalendarMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        }
    }
}

enum EditorKind: String, CaseIterable, Identifiable {
    case right
    case bottom
    case dialog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .right: "右侧"
        case .bottom: "下方"
        case .dialog: "弹窗"
        }
    }

    var caption: String {
        switch self {
        case .right: "日历在左，查看在右"
        case .bottom: "日历在上，查看在下"
        case .dialog: "点开后用半抽屉编辑"
        }
    }
}

struct ItemDragPreview: Equatable {
    var itemID: String
    var day: String
    var beforeID: String?
}

enum ActivePicker: Equatable {
    case week
    case month
    case day
}

enum DraftPurpose: Equatable {
    case add
    case edit
    case view
}

struct ItemDraft: Equatable {
    var purpose: DraftPurpose
    var itemID: String?
    var date: String
    var description: String
    var note: String
    var typeId: String
    var subTypeId: String
    var original: Snapshot

    struct Snapshot: Equatable {
        var date: String
        var description: String
        var note: String
        var typeId: String
        var subTypeId: String
    }

    var isDirty: Bool {
        guard purpose != .view else { return false }
        return date != original.date
            || description != original.description
            || note != original.note
            || typeId != original.typeId
            || subTypeId != original.subTypeId
    }

    static func adding(on date: String) -> ItemDraft {
        ItemDraft(
            purpose: .add,
            itemID: nil,
            date: date,
            description: "",
            note: "",
            typeId: "",
            subTypeId: "",
            original: Snapshot(date: date, description: "", note: "", typeId: "", subTypeId: "")
        )
    }

    static func editing(_ item: WorkItem) -> ItemDraft {
        let snapshot = Snapshot(
            date: item.date,
            description: item.description,
            note: item.note,
            typeId: item.typeId,
            subTypeId: item.subTypeId
        )
        return ItemDraft(
            purpose: .edit,
            itemID: item.id,
            date: item.date,
            description: item.description,
            note: item.note,
            typeId: item.typeId,
            subTypeId: item.subTypeId,
            original: snapshot
        )
    }

    static func viewing(_ item: WorkItem) -> ItemDraft {
        ItemDraft(
            purpose: .view,
            itemID: item.id,
            date: item.date,
            description: item.description,
            note: item.note,
            typeId: item.typeId,
            subTypeId: item.subTypeId,
            original: Snapshot(
                date: item.date,
                description: item.description,
                note: item.note,
                typeId: item.typeId,
                subTypeId: item.subTypeId
            )
        )
    }
}

enum TypeNames {
    static func parentName(typeID: String, types: [WorkType]) -> String {
        guard !typeID.isEmpty, let type = types.first(where: { $0.id == typeID }) else { return "" }
        return type.name
    }

    static func childName(typeID: String, subTypeID: String, types: [WorkType]) -> String {
        guard !typeID.isEmpty, !subTypeID.isEmpty,
              let type = types.first(where: { $0.id == typeID }),
              let child = type.children.first(where: { $0.id == subTypeID }) else { return "" }
        return child.name
    }

    static func exportLabel(item: WorkItem, types: [WorkType]) -> String {
        let parent = parentName(typeID: item.typeId, types: types)
        guard !parent.isEmpty else { return "" }
        let child = childName(typeID: item.typeId, subTypeID: item.subTypeId, types: types)
        return child.isEmpty ? parent : "\(parent) / \(child)"
    }
}
