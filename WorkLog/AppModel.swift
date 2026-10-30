import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    var folderURL: URL?
    var library: LibraryIndex?
    var types: [WorkType] = []
    var mode: CalendarMode = .week
    var selectedDay: String
    /// Day clicked in the week or month grid. The color frame can stay after this is cleared.
    var pasteDay: String? = nil
    var selectedItemID: String?
    var editorKind: EditorKind {
        didSet { UserDefaults.standard.set(editorKind.rawValue, forKey: Keys.editor) }
    }
    var draft: ItemDraft?
    var activePicker: ActivePicker?
    var pickerMonth: String
    var expandedYears: Set<String>
    var alertTitle: String?
    var alertMessage: String?
    var confirmTitle: String?
    var confirmMessage: String?
    var confirmCancelTitle = "取消"
    var confirmAcceptTitle = "确定"
    var confirmAction: (() -> Void)?
    var pendingDeleteItemID: String?
    var showExport = false
    var showImport = false
    var statusMessage: String?

    private var store: LogStore?
    private var itemsByMonth: [String: [WorkItem]] = [:]
    private var unreadableMonths: Set<String> = []
    private var monthsOnDisk: [String] = []

    static let pasteboardType = NSPasteboard.PasteboardType("com.worklog.item")

    init() {
        let today = WorkCalendar.dayKey(Date())
        selectedDay = today
        pickerMonth = WorkCalendar.monthKey(fromDay: today)
        expandedYears = [String(today.prefix(4))]
        editorKind = EditorKind(rawValue: UserDefaults.standard.string(forKey: Keys.editor) ?? "") ?? .right
        if let path = UserDefaults.standard.string(forKey: Keys.folder) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("library.json").path) {
                try? openExisting(url)
            }
        }
    }

    var hasLibrary: Bool { store != nil && library != nil }
    var canPaste: Bool { hasLibrary && mode != .day && pasteDay != nil }
    var today: String { WorkCalendar.dayKey(Date()) }
    var draftIsDirty: Bool { draft?.isDirty == true }

    func items(on day: String) -> [WorkItem] {
        let month = WorkCalendar.monthKey(fromDay: day)
        ensureMonth(month)
        return (itemsByMonth[month] ?? [])
            .filter { $0.date == day }
            .sorted { $0.order < $1.order }
    }

    func item(id: String) -> WorkItem? {
        for items in itemsByMonth.values {
            if let item = items.first(where: { $0.id == id }) { return item }
        }
        return nil
    }

    var selectedItem: WorkItem? {
        guard let selectedItemID else { return nil }
        return item(id: selectedItemID)
    }

    func visibleMonths() -> [String] {
        guard let library else { return [] }
        return MonthTree.visibleMonths(
            startMonth: library.startMonth,
            todayMonth: WorkCalendar.monthKey(Date()),
            monthsWithItems: monthsOnDisk
        )
    }

    func years() -> [String] {
        Array(Set(visibleMonths().map { String($0.prefix(4)) })).sorted()
    }

    func months(in year: String) -> [String] {
        visibleMonths().filter { $0.hasPrefix(year) }
    }

    func createLibrary(at url: URL) {
        let libraryURL = url.appendingPathComponent("library.json")
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            try? openExisting(url)
            return
        }
        let store = LogStore(root: url)
        let start = WorkCalendar.monthKey(Date())
        let library = LibraryIndex(startMonth: start, openedMonths: [])
        do {
            try store.saveLibrary(library)
            try store.saveTypes([])
            adopt(store, library: library, types: [])
        } catch {
            present(error)
        }
    }

    func openExisting(_ url: URL) throws {
        let store = LogStore(root: url)
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("library.json").path) else {
            throw LogStoreError.notALibrary
        }
        let library = try store.loadLibrary()
        let types = try store.loadTypes()
        adopt(store, library: library, types: types)
    }

    func pickNewFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "新建"
        panel.message = "选择或新建一个文件夹，用来存放工作日志。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        createLibrary(at: url)
    }

    func reviewImport(at url: URL) -> (review: ImportReview?, message: String?) {
        guard hasLibrary else { return (nil, "先打开一个日志文件夹。") }
        if draftIsDirty {
            return (nil, "先保存或取消正在编辑的事项。")
        }
        let text: String
        do {
            text = try Self.readImportText(at: url)
        } catch {
            return (nil, "这个文件读不出来。")
        }
        let entries: [PlainLogImport.Entry]
        switch PlainLogImport.parse(text) {
        case .success(let parsed):
            entries = parsed
        case .failure(let error):
            return (nil, error.localizedDescription)
        }
        let plan = planImport(entries)
        if let problem = plan.problem {
            return (nil, problem)
        }
        guard plan.added.isEmpty == false else {
            return (nil, "这些事项已经有了，没有新的内容要追加。")
        }
        return (ImportReview(added: plan.added, skipped: plan.skipped), nil)
    }

    func commitImport(_ review: ImportReview, done: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "导入之后不能撤销，确定导入吗？"
        alert.informativeText = review.skipped == 0
            ? "将追加 \(review.added.count) 条事项。已经记下的内容不会改动。"
            : "将追加 \(review.added.count) 条事项。已经有的 \(review.skipped) 条会跳过，其余内容不会改动。"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in
                self?.applyImport(review.added)
                done()
            }
        }
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    func pickExistingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "打开"
        panel.message = "打开已有的工作日志文件夹。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try openExisting(url)
        } catch {
            present(error)
        }
    }

    func go(to day: String, keepPicker: Bool = false, forPaste: Bool = false, clearItem: Bool = false) {
        let apply = {
            self.selectedDay = day
            self.pickerMonth = WorkCalendar.monthKey(fromDay: day)
            self.ensureMonth(WorkCalendar.monthKey(fromDay: day))
            if !keepPicker { self.activePicker = nil }
            if clearItem || (self.editorKind == .dialog && self.draft == nil) {
                self.selectedItemID = nil
            }
            if forPaste {
                self.pasteDay = self.mode == .day ? nil : day
            } else if self.pasteDay != day {
                self.pasteDay = nil
            }
        }
        guard draftIsDirty else {
            apply()
            return
        }
        askDiscard(apply)
    }

    func showToday() {
        pasteDay = nil
        go(to: today)
    }

    func choosePasteDay(_ day: String) {
        guard mode != .day else { return }
        holdPasteSelection()
        go(to: day, forPaste: true)
    }

    func clearPasteDay() {
        guard pasteSelectionHeld == false else { return }
        pasteDay = nil
    }

    /// The day cell and the "click outside" layer can both see one click. Keep the selection for this turn.
    private var pasteSelectionHeld = false

    private func holdPasteSelection() {
        pasteSelectionHeld = true
        DispatchQueue.main.async { [weak self] in
            self?.pasteSelectionHeld = false
        }
    }

    private func flashStatus(_ text: String) {
        statusMessage = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if statusMessage == text { statusMessage = nil }
        }
    }

    func shift(_ direction: Int) {
        pasteDay = nil
        switch mode {
        case .day:
            if let day = WorkCalendar.shiftingDay(selectedDay, by: direction) { go(to: day) }
        case .week:
            if let day = WorkCalendar.shiftingDay(selectedDay, by: direction * 7) { go(to: day) }
        case .month:
            let month = WorkCalendar.monthKey(fromDay: selectedDay)
            guard let next = WorkCalendar.shiftingMonth(month, by: direction) else { return }
            let dayNumber = Int(selectedDay.suffix(2)) ?? 1
            go(to: WorkCalendar.dayClamped(in: next, day: dayNumber))
        }
    }

    func openMonth(_ month: String) {
        pasteDay = nil
        mode = .month
        let todayMonth = WorkCalendar.monthKey(Date())
        if month == todayMonth {
            go(to: today)
        } else {
            go(to: month + "-01")
        }
    }

    func openYear(_ year: String) {
        let listed = months(in: year)
        let todayMonth = WorkCalendar.monthKey(Date())
        guard let month = MonthTree.nearestMonth(in: listed, to: todayMonth) else { return }
        openMonth(month)
    }

    func openWeek(containing day: String) {
        pasteDay = nil
        mode = .week
        if let monday = WorkCalendar.startOfWeek(containing: day) {
            go(to: monday)
        }
    }

    func jumpToWeek(_ week: Int) {
        pasteDay = nil
        guard let year = WorkCalendar.isoWeekYear(of: selectedDay),
              let monday = WorkCalendar.mondayOfISOWeek(week, year: year) else { return }
        let offset = WorkCalendar.weekdayIndexMondayFirst(of: selectedDay) ?? 0
        let day = WorkCalendar.shiftingDay(monday, by: offset) ?? monday
        go(to: day, keepPicker: true)
    }

    func select(_ item: WorkItem) {
        if mode != .day { holdPasteSelection() }
        let apply = {
            self.selectedItemID = item.id
            self.selectedDay = item.date
            if self.mode != .day { self.pasteDay = item.date }
            self.revealMonth(WorkCalendar.monthKey(fromDay: item.date))
            if self.editorKind == .dialog {
                if self.draft?.purpose == .edit, self.draft?.itemID == item.id {
                    return
                }
                self.activePicker = nil
                self.draft = .editing(item)
            } else if self.draft?.purpose == .view {
                self.draft = nil
            }
        }
        if draftIsDirty, draft?.itemID != item.id {
            askDiscard(apply)
        } else if draft?.purpose == .add, draftIsDirty {
            askDiscard(apply)
        } else {
            apply()
        }
    }

    func beginAdd(on day: String) {
        if mode != .day { holdPasteSelection() }
        let apply = {
            self.selectedDay = day
            if self.mode != .day { self.pasteDay = day }
            self.activePicker = nil
            self.draft = .adding(on: day)
        }
        guard draftIsDirty else { apply(); return }
        askDiscard(apply)
    }

    func beginEdit(_ item: WorkItem) {
        selectedItemID = item.id
        selectedDay = item.date
        activePicker = nil
        draft = .editing(item)
    }

    func beginEditSelected() {
        guard let selectedItem else { return }
        beginEdit(selectedItem)
    }

    func openEditIfAllowed(_ item: WorkItem) {
        if draft?.purpose == .edit, draft?.itemID == item.id { return }
        beginEdit(item)
    }

    func updateDraft(_ body: (inout ItemDraft) -> Void) {
        guard var draft else { return }
        body(&draft)
        if draft.typeId != self.draft?.typeId {
            let children = types.first(where: { $0.id == draft.typeId })?.children ?? []
            if children.contains(where: { $0.id == draft.subTypeId }) == false {
                draft.subTypeId = ""
            }
        }
        self.draft = draft
    }

    func cancelDraft() {
        draft = nil
    }

    func saveDraft() {
        guard var draft else { return }
        let text = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            present(title: "描述不能为空", message: "写一下做了什么，再保存。")
            return
        }
        draft.description = text
        switch draft.purpose {
        case .add:
            add(draft)
        case .edit:
            update(draft)
        case .view:
            break
        }
    }

    func askDeleteSelected() {
        guard let id = selectedItemID ?? draft?.itemID else { return }
        pendingDeleteItemID = id
        let text = item(id: id)?.description ?? "这条事项"
        confirmCancelTitle = "取消"
        confirmAcceptTitle = "删除"
        confirmTitle = "删除这条事项？"
        confirmMessage = "「\(text)」会从这一天去掉。这个操作不能撤销。"
        confirmAction = { [weak self] in self?.deletePending() }
    }

    func copySelected() {
        guard let item = selectedItem else {
            flashStatus("先点中一条事项，再复制。")
            return
        }
        let payload = ClipboardPayload(
            description: item.description,
            note: item.note,
            typeId: item.typeId,
            subTypeId: item.subTypeId
        )
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(item.description, forType: .string)
        if let data = try? JSONEncoder().encode(payload) {
            board.setData(data, forType: Self.pasteboardType)
        }
    }

    func paste() {
        guard let day = pasteDay, mode != .day else {
            flashStatus(mode == .day ? "日视图里不能粘贴。" : "先点中某一天，再粘贴。")
            return
        }
        let board = NSPasteboard.general
        let payload: ClipboardPayload
        if let data = board.data(forType: Self.pasteboardType),
           let decoded = try? JSONDecoder().decode(ClipboardPayload.self, from: data) {
            payload = decoded
        } else if let text = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            payload = ClipboardPayload(description: text, note: "", typeId: "", subTypeId: "")
        } else {
            flashStatus("剪贴板上没有可粘贴的内容。")
            return
        }
        let draft = ItemDraft(
            purpose: .add,
            itemID: nil,
            date: day,
            description: payload.description,
            note: payload.note,
            typeId: payload.typeId,
            subTypeId: payload.subTypeId,
            original: ItemDraft.Snapshot(date: day, description: "", note: "", typeId: "", subTypeId: "")
        )
        add(draft)
    }

    private var itemDragMonitor: Any?
    private var itemDragToken = 0
    private var itemDragPreviewAt = Date.distantPast
    var draggingItemID: String?
    var itemDragPreview: ItemDragPreview?
    var itemHeights: [String: CGFloat] = [:]
    var dayGridColumns = 1

    func noteDayGridColumns(_ count: Int) {
        let next = max(count, 1)
        guard dayGridColumns != next else { return }
        dayGridColumns = next
    }

    /// Arrow keys. Returns true when the event should not reach a scroll view.
    func handleArrow(_ event: NSEvent) -> Bool {
        guard event.window?.identifier?.rawValue == "worklog.main" else { return false }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if activePicker != nil { return false }
        if let draft, draft.purpose != .view { return false }
        if event.window?.firstResponder is NSTextView { return false }
        let horizontal: Int
        let vertical: Int
        switch event.keyCode {
        case 123: horizontal = -1; vertical = 0
        case 124: horizontal = 1; vertical = 0
        case 125: horizontal = 0; vertical = 1
        case 126: horizontal = 0; vertical = -1
        default: return false
        }
        if mode == .day {
            moveDayGrid(horizontal: horizontal, vertical: vertical)
        } else if horizontal != 0 {
            moveSelectedDay(by: horizontal)
        } else {
            moveItems(by: vertical)
        }
        return true
    }

    func moveSelectedDay(by direction: Int) {
        guard let day = WorkCalendar.shiftingDay(selectedDay, by: direction) else { return }
        holdPasteSelection()
        go(to: day, forPaste: true, clearItem: true)
    }

    func moveItems(by delta: Int) {
        let list = items(on: selectedDay)
        let current = list.firstIndex { $0.id == selectedItemID }
        guard let index = ItemArrow.listIndex(current: current, count: list.count, delta: delta) else { return }
        focusItem(list[index])
    }

    func moveDayGrid(horizontal: Int, vertical: Int) {
        let list = items(on: selectedDay)
        let current = list.firstIndex { $0.id == selectedItemID }
        guard let index = ItemArrow.gridIndex(
            current: current,
            count: list.count,
            columns: dayGridColumns,
            horizontal: horizontal,
            vertical: vertical
        ) else { return }
        focusItem(list[index])
    }

    private func focusItem(_ item: WorkItem) {
        selectedItemID = item.id
        selectedDay = item.date
        if mode != .day { pasteDay = item.date }
    }

    func noteItemHeights(_ heights: [String: CGFloat]) {
        for (id, height) in heights {
            let rounded = (height * 2).rounded() / 2
            guard rounded > 1, itemHeights[id] != rounded else { continue }
            itemHeights[id] = rounded
        }
    }

    func armItemDrag(_ id: String) {
        itemDragToken += 1
        draggingItemID = id
        if let moving = item(id: id) {
            itemDragPreview = ItemDragPreview(itemID: id, day: moving.date, beforeID: id)
            itemDragPreviewAt = Date()
        } else {
            itemDragPreview = nil
        }
        guard itemDragMonitor == nil else { return }
        itemDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                let token = self.itemDragToken
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard self.itemDragToken == token else { return }
                self.clearItemDrag()
            }
            return event
        }
    }

    func previewItemDrop(id: String, day: String, beforeID: String?) {
        itemDragPreviewAt = Date()
        let next = ItemDragPreview(itemID: id, day: day, beforeID: beforeID)
        guard itemDragPreview != next else { return }
        itemDragPreview = next
    }

    /// Empty space in a column also accepts the drop. Ignore it briefly so the
    /// gap between two rows does not flash the placeholder to the end of the day.
    func previewItemAppend(id: String, day: String) {
        if let preview = itemDragPreview,
           preview.day == day,
           preview.beforeID != nil,
           Date().timeIntervalSince(itemDragPreviewAt) < 0.12 {
            return
        }
        previewItemDrop(id: id, day: day, beforeID: nil)
    }

    /// Dropping on the item being dragged means "leave it here". After removal,
    /// that is the following item, or the end of the day when it is already last.
    func landingBefore(id: String, day: String, beforeID: String?) -> String? {
        guard beforeID == id else { return beforeID }
        let dayItems = items(on: day)
        guard let index = dayItems.firstIndex(where: { $0.id == id }),
              dayItems.indices.contains(index + 1) else { return nil }
        return dayItems[index + 1].id
    }

    func clearItemDrag() {
        draggingItemID = nil
        itemDragPreview = nil
        if let itemDragMonitor {
            NSEvent.removeMonitor(itemDragMonitor)
            self.itemDragMonitor = nil
        }
    }

    func moveItem(id: String, to day: String, before beforeID: String?) {
        guard var moving = item(id: id) else { return }
        let fromMonth = WorkCalendar.monthKey(fromDay: moving.date)
        let toMonth = WorkCalendar.monthKey(fromDay: day)
        moving.date = day
        if fromMonth == toMonth {
            guard var items = itemsByMonth[fromMonth] else { return }
            items.removeAll { $0.id == id }
            items = Self.insert(moving, into: items, day: day, before: beforeID)
            itemsByMonth[fromMonth] = items
            do {
                try store?.saveMonth(fromMonth, items: items)
                refreshDiskMonths()
            } catch {
                present(error)
            }
        } else {
            guard unreadableMonths.contains(fromMonth) == false, unreadableMonths.contains(toMonth) == false else {
                present(title: "无法移动", message: "有一份月份文件读不出来，这次没有改动。")
                return
            }
            ensureMonth(toMonth)
            guard var destination = itemsByMonth[toMonth], var source = itemsByMonth[fromMonth] else { return }
            source.removeAll { $0.id == id }
            destination = Self.insert(moving, into: destination, day: day, before: beforeID)
            do {
                try store?.saveMonth(toMonth, items: destination)
                itemsByMonth[toMonth] = destination
                do {
                    try store?.saveMonth(fromMonth, items: source)
                    itemsByMonth[fromMonth] = source
                } catch {
                    present(LogStoreError.moveIncomplete)
                }
                refreshDiskMonths()
                revealMonth(toMonth)
            } catch {
                present(error)
            }
        }
        selectedItemID = id
        selectedDay = day
    }

    func addType(parentID: String?, name: String = "未命名", allowEmpty: Bool = false) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard allowEmpty, parentID != nil else { return "名称不能为空。" }
        }
        if let parentID {
            guard let index = types.firstIndex(where: { $0.id == parentID }) else { return nil }
            if trimmed.isEmpty == false, types[index].children.contains(where: { $0.name == trimmed }) {
                return "同一个一级类型下面不能有重名的二级类型。"
            }
            let order = (types[index].children.map(\.order).max() ?? -1) + 1
            types[index].children.append(SubType(id: Self.newID("s"), name: trimmed, order: order))
        } else {
            if types.contains(where: { $0.name == trimmed }) {
                return "一级类型不能重名。"
            }
            let order = (types.map(\.order).max() ?? -1) + 1
            types.append(WorkType(id: Self.newID("t"), name: trimmed, order: order, children: []))
        }
        persistTypes()
        return nil
    }

    func renameType(id: String, parentID: String?, name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "名称不能为空。" }
        if let parentID {
            guard let parentIndex = types.firstIndex(where: { $0.id == parentID }),
                  let childIndex = types[parentIndex].children.firstIndex(where: { $0.id == id }) else { return nil }
            let duplicate = types[parentIndex].children.contains { $0.id != id && $0.name == trimmed }
            guard !duplicate else { return "同一个一级类型下面不能有重名的二级类型。" }
            types[parentIndex].children[childIndex].name = trimmed
        } else {
            guard let index = types.firstIndex(where: { $0.id == id }) else { return nil }
            let duplicate = types.contains { $0.id != id && $0.name == trimmed }
            guard !duplicate else { return "一级类型不能重名。" }
            types[index].name = trimmed
        }
        persistTypes()
        return nil
    }

    func moveType(id: String, parentID: String?, direction: Int) {
        if let parentID, let parentIndex = types.firstIndex(where: { $0.id == parentID }) {
            types[parentIndex].children = Self.move(types[parentIndex].children, id: id, direction: direction)
        } else {
            types = Self.move(types, id: id, direction: direction)
        }
        persistTypes()
    }

    func moveType(id: String, parentID: String?, to index: Int) {
        if let parentID {
            guard let parentIndex = types.firstIndex(where: { $0.id == parentID }) else { return }
            let updated = Self.relocate(types[parentIndex].children, id: id, to: index)
            guard updated != types[parentIndex].children else { return }
            types[parentIndex].children = updated
        } else {
            let updated = Self.relocate(types, id: id, to: index)
            guard updated != types else { return }
            types = updated
        }
        persistTypes()
    }

    func discardUnnamedChild(id: String, parentID: String) {
        guard let parent = types.first(where: { $0.id == parentID }),
              let child = parent.children.first(where: { $0.id == id }),
              child.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        removeType(id: id, parentID: parentID)
    }

    func deleteType(id: String, parentID: String?) {
        let count = store?.usageCount(typeID: parentID ?? id, subTypeID: parentID == nil ? nil : id) ?? 0
        let name: String
        if let parentID, let parent = types.first(where: { $0.id == parentID }), let child = parent.children.first(where: { $0.id == id }) {
            name = child.name.isEmpty ? "未填写的二级类型" : child.name
        } else {
            name = types.first(where: { $0.id == id })?.name ?? "这个类型"
        }
        let alert = NSAlert()
        alert.messageText = "删除「\(name)」？"
        alert.informativeText = count == 0
            ? "没有事项正在使用它。"
            : "有 \(count) 条事项正在使用它。删掉之后，那些事项不再显示这个类型，描述和备注还在。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in
                self?.removeType(id: id, parentID: parentID)
            }
        }
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    func exportMarkdown(scope: ExportScope) -> String? {
        guard let store else { return nil }
        var collected: [WorkItem] = []
        for month in scope.months {
            if let cached = itemsByMonth[month], unreadableMonths.contains(month) == false {
                collected.append(contentsOf: cached)
            } else if let loaded = try? store.loadMonth(month) {
                collected.append(contentsOf: loaded)
            }
        }
        return MarkdownExport.document(scope: scope, items: collected, types: types)
    }

    func saveExport(_ text: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "工作日志.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            present(title: "无法保存", message: error.localizedDescription)
        }
    }

    func copyExport(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = "已复制"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if statusMessage == "已复制" { statusMessage = nil }
        }
    }

    func loadMonths(for days: [String]) {
        for day in days {
            ensureMonth(WorkCalendar.monthKey(fromDay: day))
        }
    }

    struct ImportReview {
        var added: [PlainLogImport.Entry]
        var skipped: Int
    }

    private struct ImportPlan {
        var added: [PlainLogImport.Entry]
        var skipped: Int
        var problem: String?
    }

    private func planImport(_ entries: [PlainLogImport.Entry]) -> ImportPlan {
        var existing: [PlainLogImport.Entry] = []
        let months = Set(entries.map { WorkCalendar.monthKey(fromDay: $0.date) })
        for month in months {
            ensureMonth(month)
            if unreadableMonths.contains(month) {
                return ImportPlan(added: [], skipped: 0, problem: "有一份月份文件读不出来，没有导入。")
            }
            for item in itemsByMonth[month] ?? [] {
                existing.append(PlainLogImport.Entry(date: item.date, description: item.description))
            }
        }
        let filtered = PlainLogImport.skippingExisting(entries, existing: existing)
        return ImportPlan(added: filtered.added, skipped: filtered.skipped, problem: nil)
    }

    private func applyImport(_ entries: [PlainLogImport.Entry]) {
        var grouped: [String: [PlainLogImport.Entry]] = [:]
        for entry in entries {
            grouped[WorkCalendar.monthKey(fromDay: entry.date), default: []].append(entry)
        }
        var first: WorkItem?
        var written = 0
        for month in grouped.keys.sorted() {
            ensureMonth(month)
            guard unreadableMonths.contains(month) == false, var items = itemsByMonth[month] else {
                present(title: "无法导入", message: "有一份月份文件读不出来，已经写入的部分还在。")
                return
            }
            let kept = items
            for entry in grouped[month] ?? [] {
                let description = entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if items.contains(where: { $0.date == entry.date && $0.description.trimmingCharacters(in: .whitespacesAndNewlines) == description }) {
                    continue
                }
                let order = (items.filter { $0.date == entry.date }.map(\.order).max() ?? -1) + 1
                let item = WorkItem(
                    id: Self.newID("i"),
                    date: entry.date,
                    description: description,
                    note: "",
                    typeId: "",
                    subTypeId: "",
                    order: order
                )
                items.append(item)
                written += 1
                if first == nil, entry.date == entries[0].date, entry.description == entries[0].description {
                    first = item
                }
            }
            guard items.count > kept.count else { continue }
            let keptIDs = Set(kept.map(\.id))
            guard kept.allSatisfy({ old in items.contains(old) }),
                  keptIDs.isSubset(of: Set(items.map(\.id))) else {
                present(title: "无法导入", message: "为了保住已经记下的事项，这次没有写入。")
                return
            }
            do {
                try store?.saveMonth(month, items: items)
                itemsByMonth[month] = items
                refreshDiskMonths()
                revealMonth(month)
            } catch {
                present(error)
                return
            }
        }
        if let first {
            selectedItemID = first.id
            selectedDay = first.date
            pickerMonth = WorkCalendar.monthKey(fromDay: first.date)
            if draftIsDirty == false { draft = nil }
            activePicker = nil
        }
        statusMessage = "导入了 \(written) 条"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if statusMessage == "导入了 \(written) 条" { statusMessage = nil }
        }
    }

    private static func readImportText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8) { return text }
        let encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let text = String(data: data, encoding: encoding) { return text }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    private func add(_ draft: ItemDraft) {
        let month = WorkCalendar.monthKey(fromDay: draft.date)
        ensureMonth(month)
        guard unreadableMonths.contains(month) == false, var items = itemsByMonth[month] else {
            present(title: "无法添加", message: "这个月的文件读不出来，没有写入。")
            return
        }
        let order = (items.filter { $0.date == draft.date }.map(\.order).max() ?? -1) + 1
        let item = WorkItem(
            id: Self.newID("i"),
            date: draft.date,
            description: draft.description,
            note: draft.note,
            typeId: draft.typeId,
            subTypeId: draft.subTypeId,
            order: order
        )
        items.append(item)
        itemsByMonth[month] = items
        do {
            try store?.saveMonth(month, items: items)
            refreshDiskMonths()
            revealMonth(month)
            finishSave(item, openView: false)
        } catch {
            present(error)
        }
    }

    private func update(_ draft: ItemDraft) {
        guard let id = draft.itemID, var existing = item(id: id) else { return }
        let fromMonth = WorkCalendar.monthKey(fromDay: existing.date)
        let toMonth = WorkCalendar.monthKey(fromDay: draft.date)
        existing.description = draft.description
        existing.note = draft.note
        existing.typeId = draft.typeId
        existing.subTypeId = draft.subTypeId
        existing.date = draft.date
        if fromMonth == toMonth {
            guard var items = itemsByMonth[fromMonth] else { return }
            let sameDay = items.contains { $0.id == id && $0.date == draft.date }
            if sameDay {
                if let index = items.firstIndex(where: { $0.id == id }) {
                    items[index] = existing
                }
            } else {
                items.removeAll { $0.id == id }
                existing.order = (items.filter { $0.date == draft.date }.map(\.order).max() ?? -1) + 1
                items.append(existing)
            }
            itemsByMonth[fromMonth] = items
            do {
                try store?.saveMonth(fromMonth, items: items)
                finishSave(existing, openView: false)
            } catch {
                present(error)
            }
        } else {
            ensureMonth(toMonth)
            guard unreadableMonths.contains(toMonth) == false,
                  var destination = itemsByMonth[toMonth],
                  var source = itemsByMonth[fromMonth] else {
                present(title: "无法保存", message: "目标月份的文件读不出来，没有改动原来的记录。")
                return
            }
            source.removeAll { $0.id == id }
            existing.order = (destination.filter { $0.date == draft.date }.map(\.order).max() ?? -1) + 1
            destination.append(existing)
            do {
                try store?.saveMonth(toMonth, items: destination)
                itemsByMonth[toMonth] = destination
                do {
                    try store?.saveMonth(fromMonth, items: source)
                    itemsByMonth[fromMonth] = source
                } catch {
                    present(LogStoreError.moveIncomplete)
                }
                refreshDiskMonths()
                revealMonth(toMonth)
                finishSave(existing, openView: false)
            } catch {
                present(error)
            }
        }
    }

    private func finishSave(_ item: WorkItem, openView: Bool) {
        selectedItemID = item.id
        selectedDay = item.date
        draft = openView ? .viewing(item) : nil
    }

    private func deletePending() {
        guard let id = pendingDeleteItemID, let existing = item(id: id) else { return }
        let month = WorkCalendar.monthKey(fromDay: existing.date)
        guard var items = itemsByMonth[month] else { return }
        items.removeAll { $0.id == id }
        items = Self.renumber(items)
        itemsByMonth[month] = items
        do {
            try store?.saveMonth(month, items: items)
            refreshDiskMonths()
            if selectedItemID == id { selectedItemID = nil }
            if draft?.itemID == id { draft = nil }
        } catch {
            present(error)
        }
        pendingDeleteItemID = nil
    }

    private func removeType(id: String, parentID: String?) {
        if let parentID, let index = types.firstIndex(where: { $0.id == parentID }) {
            types[index].children.removeAll { $0.id == id }
        } else {
            types.removeAll { $0.id == id }
        }
        persistTypes()
    }

    private func persistTypes() {
        normalizeTypeOrder()
        do {
            try store?.saveTypes(types)
        } catch {
            present(error)
        }
    }

    private func normalizeTypeOrder() {
        types = types.sorted { $0.order < $1.order }
        for index in types.indices {
            types[index].order = index
            types[index].children = types[index].children.sorted { $0.order < $1.order }
            for child in types[index].children.indices {
                types[index].children[child].order = child
            }
        }
    }

    private func adopt(_ store: LogStore, library: LibraryIndex, types: [WorkType]) {
        self.store = store
        self.library = library
        self.types = types.sorted { $0.order < $1.order }
        itemsByMonth = [:]
        unreadableMonths = []
        folderURL = store.root
        UserDefaults.standard.set(store.root.path, forKey: Keys.folder)
        refreshDiskMonths()
        let today = WorkCalendar.dayKey(Date())
        selectedDay = today
        pickerMonth = WorkCalendar.monthKey(fromDay: today)
        expandedYears = [String(today.prefix(4))]
        mode = .week
        selectedItemID = nil
        draft = nil
        ensureMonth(WorkCalendar.monthKey(fromDay: today))
    }

    private func ensureMonth(_ month: String) {
        guard store != nil, itemsByMonth[month] == nil, unreadableMonths.contains(month) == false else { return }
        do {
            itemsByMonth[month] = try store?.loadMonth(month) ?? []
        } catch {
            unreadableMonths.insert(month)
            present(error)
        }
    }

    private func revealMonth(_ month: String) {
        expandedYears.insert(String(month.prefix(4)))
    }

    private func refreshDiskMonths() {
        monthsOnDisk = store?.monthsOnDisk() ?? []
    }

    private func askDiscard(_ action: @escaping () -> Void) {
        confirmCancelTitle = "继续编辑"
        confirmAcceptTitle = "放弃"
        confirmTitle = "放弃这次编辑？"
        confirmMessage = "描述、备注和类型还没保存。"
        confirmAction = { [weak self] in
            self?.draft = nil
            action()
        }
    }

    private func present(_ error: Error) {
        present(title: "没有完成", message: error.localizedDescription)
    }

    private func present(title: String, message: String) {
        alertTitle = title
        alertMessage = message
    }

    private static func insert(_ item: WorkItem, into items: [WorkItem], day: String, before beforeID: String?) -> [WorkItem] {
        var dayItems = items.filter { $0.date == day }.sorted { $0.order < $1.order }
        let others = items.filter { $0.date != day }
        if let beforeID, let index = dayItems.firstIndex(where: { $0.id == beforeID }) {
            dayItems.insert(item, at: index)
        } else {
            dayItems.append(item)
        }
        for index in dayItems.indices {
            dayItems[index].order = index
        }
        return others + dayItems
    }

    private static func renumber(_ items: [WorkItem]) -> [WorkItem] {
        let days = Set(items.map(\.date))
        var result: [WorkItem] = []
        for day in days.sorted() {
            var dayItems = items.filter { $0.date == day }.sorted { $0.order < $1.order }
            for index in dayItems.indices { dayItems[index].order = index }
            result.append(contentsOf: dayItems)
        }
        return result
    }

    private static func relocate<T: OrderWritable>(_ values: [T], id: T.ID, to index: Int) -> [T] {
        var copy = values.sorted { $0.order < $1.order }
        guard let from = copy.firstIndex(where: { $0.id == id }) else { return values }
        let target = min(max(index, 0), copy.count - 1)
        guard target != from else { return values }
        let item = copy.remove(at: from)
        copy.insert(item, at: target)
        for position in copy.indices { copy[position].order = position }
        return copy
    }

    private static func move<T: Identifiable>(_ values: [T], id: T.ID, direction: Int) -> [T] where T: OrderWritable {
        var copy = values.sorted { $0.order < $1.order }
        guard let index = copy.firstIndex(where: { $0.id == id }) else { return values }
        let target = index + direction
        guard copy.indices.contains(target) else { return values }
        copy.swapAt(index, target)
        for position in copy.indices { copy[position].order = position }
        return copy
    }

    private static func newID(_ prefix: String) -> String {
        prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
    }

    private enum Keys {
        static let folder = "worklog.folderPath"
        static let editor = "worklog.editorKind"
    }
}

private protocol OrderWritable: Identifiable {
    var order: Int { get set }
}

extension WorkType: OrderWritable {}
extension SubType: OrderWritable {}

@MainActor
final class AppRuntime: NSObject, NSApplicationDelegate {
    static let shared = AppRuntime()
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        MenuSlimmer.shared.install()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                self?.model?.handleArrow(event) ?? false
            }
            return handled ? nil : event
        }
    }

    func applicationWillUpdate(_ notification: Notification) {
        MenuSlimmer.shared.install()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.draftIsDirty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "还有没保存的编辑"
        alert.informativeText = "描述、备注和类型还没保存。关闭窗口会丢掉这次编辑。"
        alert.addButton(withTitle: "继续编辑")
        alert.addButton(withTitle: "仍然关闭")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
