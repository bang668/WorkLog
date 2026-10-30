import AppKit
import SwiftUI

struct DayBoard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DayColumn(day: model.selectedDay, kind: .day)
            .background(WorkColor.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WorkColor.line))
            .padding(.top, 4)
    }
}

struct WeekBoard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let days = WorkCalendar.weekDays(containing: model.selectedDay)
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                let slim = ColumnLayout.weekIsSlim(index: index, itemCount: model.items(on: day).count)
                DayColumn(day: day, kind: .week)
                    .frame(width: slim ? 40 : nil)
                    .frame(maxWidth: slim ? 40 : .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 4)
    }
}

struct MonthBoard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let month = WorkCalendar.monthKey(fromDay: model.selectedDay)
        let weeks = WorkCalendar.weeks(inMonth: month)
        let slim = ColumnLayout.monthSlimColumns(weeks: weeks, viewMonth: month) { model.items(on: $0).count }
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                Color.clear.frame(width: Self.weekColumn, height: 16)
                HStack(spacing: 6) {
                    ForEach(Array(WorkCalendar.weekdaySymbols.enumerated()), id: \.offset) { index, name in
                        Text(name)
                            .font(.system(size: 11))
                            .foregroundStyle(WorkColor.tertiary)
                            .lineLimit(1)
                            .frame(width: columnWidth(index: index, slim: slim), height: 16, alignment: .leading)
                            .frame(maxWidth: isSlim(index: index, slim: slim) ? columnWidth(index: index, slim: slim) : .infinity, alignment: .leading)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .onTapGesture { model.clearPasteDay() }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(alignment: .center, spacing: 3) {
                    Button {
                        if let first = week.first { model.openWeek(containing: first) }
                    } label: {
                        VStack(spacing: 1) {
                            Text("第")
                            Text("\(WorkCalendar.isoWeek(of: week[0]) ?? 0)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(WorkColor.ink)
                            Text("周")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(WorkColor.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .frame(width: Self.weekColumn)
                    .frame(maxHeight: .infinity)
                    HStack(alignment: .center, spacing: 6) {
                        ForEach(Array(week.enumerated()), id: \.element) { index, day in
                            MonthCell(day: day, viewMonth: month, slim: isSlim(index: index, slim: slim))
                                .frame(width: isSlim(index: index, slim: slim) ? Self.slimColumn : nil)
                                .frame(maxWidth: isSlim(index: index, slim: slim) ? Self.slimColumn : .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private func isSlim(index: Int, slim: (saturday: Bool, sunday: Bool)) -> Bool {
        (index == 5 && slim.saturday) || (index == 6 && slim.sunday)
    }

    private func columnWidth(index: Int, slim: (saturday: Bool, sunday: Bool)) -> CGFloat? {
        isSlim(index: index, slim: slim) ? Self.slimColumn : nil
    }

    /// Empty weekend columns match the UI draft: 44pt, date stays on one line.
    private static let slimColumn: CGFloat = 44
    /// Week label column. Narrower than the draft's 32pt so the number sits closer to the days.
    private static let weekColumn: CGFloat = 24
}

private enum ColumnKind {
    case day
    case week
}

private enum DayFrame {
    /// Color frame left on the current day after the paste selection is cleared.
    static let parked = Color(red: 0.47, green: 0.69, blue: 1)
}

private struct DayColumn: View {
    @Environment(AppModel.self) private var model
    let day: String
    let kind: ColumnKind
    @State private var hovering = false

    var body: some View {
        let selected = day == model.selectedDay
        let armed = selected && model.pasteDay == day
        let frame: Color = {
            guard kind == .week else { return .clear }
            if selected == false { return WorkColor.line }
            return armed ? WorkColor.blue : DayFrame.parked
        }()
        VStack(alignment: .leading, spacing: 0) {
            if kind == .week {
                weekHead
                    .padding(.horizontal, slim ? 2 : 8)
                    .padding(.top, 8)
            }
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        if kind == .day {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: DayDragLayout.gridSpacing)], spacing: DayDragLayout.gridSpacing) {
                                ForEach(boardSlots(on: day, model: model)) { slot in
                                    switch slot {
                                    case .item(let item):
                                        DayGridCard(item: item)
                                            .id(item.id)
                                    case .gap:
                                        ItemDropGap(height: DayGridCard.height, radius: 12)
                                            .itemDrop(day: day, beforeID: model.itemDragPreview?.beforeID, model: model)
                                    }
                                }
                                DayAddButton(day: day)
                            }
                            .animation(.easeOut(duration: 0.16), value: model.itemDragPreview)
                            .padding(16)
                            .frame(width: geo.size.width, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(boardSlots(on: day, model: model)) { slot in
                                    switch slot {
                                    case .item(let item):
                                        EntryRow(item: item, kind: kind)
                                            .id(item.id)
                                    case .gap:
                                        ItemDropGap(height: draggedRowHeight(model: model, fallback: 32), radius: 7)
                                            .itemDrop(day: day, beforeID: model.itemDragPreview?.beforeID, model: model)
                                    }
                                }
                                plus
                            }
                            .animation(.easeOut(duration: 0.16), value: model.itemDragPreview)
                            .padding(6)
                            .frame(width: geo.size.width, alignment: .leading)
                        }
                    }
                    .onAppear {
                        guard kind == .day else { return }
                        model.noteDayGridColumns(ItemArrow.columns(fitting: geo.size.width))
                    }
                    .onChange(of: geo.size.width) { _, width in
                        guard kind == .day else { return }
                        model.noteDayGridColumns(ItemArrow.columns(fitting: width))
                    }
                    .onChange(of: model.selectedItemID) { _, id in
                        guard day == model.selectedDay, let id else { return }
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WorkColor.card, in: RoundedRectangle(cornerRadius: kind == .day ? 0 : 10))
        .overlay(
            RoundedRectangle(cornerRadius: kind == .day ? 0 : 10)
                .stroke(frame, lineWidth: selected && kind == .week ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .simultaneousGesture(TapGesture().onEnded {
            if kind == .week {
                model.choosePasteDay(day)
            } else {
                model.clearPasteDay()
            }
        })
        .onDrop(of: [.plainText], delegate: ItemDropDelegate(day: day, target: .column, model: model))
        .onPreferenceChange(ItemHeightKey.self) { model.noteItemHeights($0) }
    }

    private var slim: Bool {
        kind == .week && (WorkCalendar.weekdayIndexMondayFirst(of: day) ?? 0) >= 5 && model.items(on: day).isEmpty
    }

    private var weekHead: some View {
        let today = day == model.today
        return VStack(alignment: .leading, spacing: 2) {
            Button { model.choosePasteDay(day) } label: {
                Text(WorkCalendar.weekdayName(of: day))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, slim ? 3 : 8)
                    .padding(.vertical, 2)
                    .background(today ? WorkColor.blue : Color.clear, in: Capsule())
                    .foregroundStyle(today ? Color.white : WorkColor.ink)
            }
            .buttonStyle(.plain)
            Text(WorkCalendar.monthDayHyphen(day))
                .font(.system(size: 11))
                .foregroundStyle(WorkColor.secondary)
                .padding(.leading, slim ? 2 : 8)
        }
    }

    private var plus: some View {
        Group {
            if kind == .day {
                DayAddButton(day: day)
            } else {
                Button {
                    model.beginAdd(on: day)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(hovering ? WorkColor.ink : Color.clear)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background(hovering ? WorkColor.paper : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .itemDrop(day: day, beforeID: nil, model: model)
                .accessibilityLabel("添加事项")
            }
        }
    }
}

private struct DayAddButton: View {
    @Environment(AppModel.self) private var model
    let day: String
    @State private var hovering = false

    var body: some View {
        Button {
            model.beginAdd(on: day)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(hovering ? WorkColor.ink : WorkColor.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: DayGridCard.height)
                .background(hovering ? WorkColor.paper : WorkColor.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(hovering ? Self.chipHoverStroke : WorkColor.line)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(SegmentHitStyle())
        .onHover { hovering = $0 }
        .itemDrop(day: day, beforeID: nil, model: model)
        .accessibilityLabel("添加事项")
    }

    fileprivate static let chipHoverStroke = Color(red: 0.78, green: 0.75, blue: 0.70)
}

private struct DayGridCard: View {
    @Environment(AppModel.self) private var model
    let item: WorkItem
    @State private var hovering = false

    static let height: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.description)
                .font(.system(size: 15))
                .foregroundStyle(WorkColor.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.note.isEmpty == false {
                Text(item.note)
                    .font(.system(size: 13))
                    .foregroundStyle(WorkColor.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            typeLine
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .topLeading)
        .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .itemActions(select: { model.select(item) }, doubleClick: { model.openEditIfAllowed(item) })
        .onDrag {
            model.armItemDrag(item.id)
            return NSItemProvider(object: item.id as NSString)
        }
        .itemDrop(day: item.date, beforeID: item.id, model: model)
    }

    private var typeLine: some View {
        let parent = TypeNames.parentName(typeID: item.typeId, types: model.types)
        let child = TypeNames.childName(typeID: item.typeId, subTypeID: item.subTypeId, types: model.types)
        return Group {
            if parent.isEmpty && child.isEmpty {
                EmptyMark()
            } else {
                Text(child.isEmpty ? parent : "\(parent) / \(child)")
                    .font(.system(size: 12))
                    .foregroundStyle(WorkColor.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fill: Color {
        if model.selectedItemID == item.id { return WorkColor.blueSoft }
        if hovering { return WorkColor.card }
        return Self.rest
    }

    private var stroke: Color {
        if model.selectedItemID == item.id { return WorkColor.blue.opacity(0.45) }
        if hovering { return DayAddButton.chipHoverStroke }
        return WorkColor.line
    }

    private static let rest = Color(red: 0.994, green: 0.988, blue: 0.978)
}

private struct EntryRow: View {
    @Environment(AppModel.self) private var model
    let item: WorkItem
    let kind: ColumnKind
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.description)
                .font(.system(size: kind == .day ? 14 : 12, weight: .regular))
                .foregroundStyle(WorkColor.ink)
                .lineLimit(kind == .week ? 2 : nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if kind == .day, item.note.isEmpty == false {
                Text(item.note)
                    .font(.system(size: 13))
                    .foregroundStyle(WorkColor.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(kind == .day ? 10 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: rowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: rowRadius, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: rowRadius, style: .continuous))
        .onHover { hovering = $0 }
        .itemActions(select: { model.select(item) }, doubleClick: { model.openEditIfAllowed(item) })
        .onDrag {
            model.armItemDrag(item.id)
            return NSItemProvider(object: item.id as NSString)
        }
        .itemDrop(day: item.date, beforeID: item.id, model: model)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ItemHeightKey.self, value: [item.id: proxy.size.height])
            }
            .allowsHitTesting(false)
        }
    }

    private var rowRadius: CGFloat { kind == .day ? 10 : 7 }

    private var fill: Color {
        if model.selectedItemID == item.id { return WorkColor.blueSoft }
        if hovering { return WorkColor.paper }
        return WorkColor.chip
    }

    private var stroke: Color {
        if model.selectedItemID == item.id { return WorkColor.blue.opacity(0.45) }
        if hovering { return DayAddButton.chipHoverStroke }
        return WorkColor.line
    }
}

private struct MonthEntry: View {
    @Environment(AppModel.self) private var model
    let item: WorkItem
    @State private var hovering = false

    var body: some View {
        Text(item.description)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .onHover { hovering = $0 }
            .itemActions(select: { model.select(item) }, doubleClick: { model.openEditIfAllowed(item) })
            .onDrag {
                model.armItemDrag(item.id)
                return NSItemProvider(object: item.id as NSString)
            }
            .itemDrop(day: item.date, beforeID: item.id, model: model)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ItemHeightKey.self, value: [item.id: proxy.size.height])
                }
                .allowsHitTesting(false)
            }
    }

    private var fill: Color {
        if model.selectedItemID == item.id { return WorkColor.blueSoft }
        if hovering { return WorkColor.paper }
        return WorkColor.chip
    }

    private var stroke: Color {
        if model.selectedItemID == item.id { return WorkColor.blue.opacity(0.45) }
        if hovering { return DayAddButton.chipHoverStroke }
        return WorkColor.line
    }
}

private struct MonthCell: View {
    @Environment(AppModel.self) private var model
    let day: String
    let viewMonth: String
    var slim = false
    @State private var hovering = false

    var body: some View {
        let outside = WorkCalendar.monthKey(fromDay: day) != viewMonth
        let selected = day == model.selectedDay
        let armed = selected && model.pasteDay == day
        let today = day == model.today
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(WorkCalendar.monthDayHyphen(day))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(slim ? 0.85 : 1)
                    .padding(.horizontal, today ? (slim ? 3 : 5) : 0)
                    .padding(.vertical, today ? 1 : 0)
                    .background(today ? WorkColor.blue : Color.clear, in: Capsule())
                    .foregroundStyle(today ? Color.white : (outside ? WorkColor.secondary : WorkColor.ink))
                    .padding(.top, slim ? 3 : 4)
                    .padding(.leading, slim ? 2 : 4)
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(boardSlots(on: day, model: model)) { slot in
                                    switch slot {
                                    case .item(let item):
                                        MonthEntry(item: item)
                                            .id(item.id)
                                    case .gap:
                                        ItemDropGap(height: draggedRowHeight(model: model, fallback: 22), radius: 4)
                                            .itemDrop(day: day, beforeID: model.itemDragPreview?.beforeID, model: model)
                                    }
                                }
                            }
                            .animation(.easeOut(duration: 0.16), value: model.itemDragPreview)
                            .padding(.horizontal, 2)
                            .frame(width: geo.size.width, alignment: .leading)
                        }
                        .onChange(of: model.selectedItemID) { _, id in
                            guard day == model.selectedDay, let id else { return }
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Button {
                model.beginAdd(on: day)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(hovering ? WorkColor.ink : Color.clear)
                    .frame(width: 16, height: 16)
                    .background(hovering ? WorkColor.card : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .padding(3)
            .accessibilityLabel("添加事项")
        }
        .background(dayFill(outside: outside), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if hovering {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.02))
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? (armed ? WorkColor.blue : DayFrame.parked) : (hovering ? Color(red: 0.84, green: 0.82, blue: 0.78) : WorkColor.line), lineWidth: selected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .simultaneousGesture(TapGesture().onEnded { model.choosePasteDay(day) })
        .onDrop(of: [.plainText], delegate: ItemDropDelegate(day: day, target: .column, model: model))
        .onPreferenceChange(ItemHeightKey.self) { model.noteItemHeights($0) }
    }

    private func dayFill(outside: Bool) -> Color {
        if hovering {
            return outside ? Color(red: 0.955, green: 0.948, blue: 0.928) : Color(red: 0.986, green: 0.975, blue: 0.959)
        }
        return outside ? WorkColor.outside : WorkColor.card
    }
}

private enum BoardSlot: Identifiable {
    case item(WorkItem)
    case gap

    var id: String {
        switch self {
        case .item(let item): item.id
        case .gap: "drop-gap"
        }
    }
}

struct DayCardSlot: Equatable {
    var id: String
    var frame: CGRect
}

enum ItemArrow {
    /// Adaptive grid column count for the day view. Width includes the grid's outer padding.
    static func columns(fitting width: CGFloat, minimum: CGFloat = 260, spacing: CGFloat = 12, padding: CGFloat = 32) -> Int {
        let inner = max(0, width - padding)
        guard inner > 0 else { return 1 }
        return max(1, Int((inner + spacing) / (minimum + spacing)))
    }

    static func listIndex(current: Int?, count: Int, delta: Int) -> Int? {
        guard count > 0, delta != 0 else { return nil }
        guard let current, current >= 0, current < count else {
            return delta < 0 ? count - 1 : 0
        }
        let next = current + delta
        guard next >= 0, next < count else { return current }
        return next
    }

    static func gridIndex(current: Int?, count: Int, columns: Int, horizontal: Int, vertical: Int) -> Int? {
        guard count > 0 else { return nil }
        let columns = max(columns, 1)
        guard let current, current >= 0, current < count else {
            if horizontal < 0 || vertical < 0 { return count - 1 }
            return 0
        }
        let row = current / columns
        let col = current % columns
        let rowCount = (count + columns - 1) / columns
        if horizontal != 0 {
            var newRow = row
            var newCol = col + horizontal
            if newCol < 0 {
                guard row > 0 else { return current }
                newRow = row - 1
                let rowLength = min(columns, count - newRow * columns)
                newCol = rowLength - 1
            } else {
                let rowLength = min(columns, count - row * columns)
                if newCol >= rowLength {
                    guard row + 1 < rowCount else { return current }
                    newRow = row + 1
                    newCol = 0
                }
            }
            return newRow * columns + newCol
        }
        if vertical != 0 {
            let newRow = row + vertical
            guard newRow >= 0, newRow < rowCount else { return current }
            let rowLength = min(columns, count - newRow * columns)
            let newCol = min(col, rowLength - 1)
            return newRow * columns + newCol
        }
        return current
    }
}

enum DayDragLayout {
    /// Pointer travel, from where the drag started, before the day-view placeholder moves to the next card.
    static let moveDistance: CGFloat = 48
    static let gridSpacing: CGFloat = 12

    static func ordered(_ frames: [String: CGRect]) -> [DayCardSlot] {
        rows(frames.map { DayCardSlot(id: $0.key, frame: $0.value) }).flatMap { $0 }
    }

    static func steps(_ delta: CGFloat, pitch: CGFloat, trigger: CGFloat = moveDistance) -> Int {
        guard pitch > 1 else { return 0 }
        let distance = abs(delta)
        guard distance >= trigger else { return 0 }
        let sign = delta >= 0 ? 1 : -1
        return sign * (1 + Int(floor((distance - trigger) / pitch)))
    }

    /// Nil means the pointer has moved past the last card, so the item lands at the end of the day.
    static func landingID(pointer: CGPoint, origin: CGPoint, slots: [DayCardSlot], draggingID: String, trigger: CGFloat = moveDistance) -> String? {
        let grouped = rows(slots)
        guard let place = index(of: draggingID, in: grouped) else { return draggingID }
        let columnPitch = pitch(across: grouped) ?? (slots.first { $0.id == draggingID }?.frame.width ?? 260) + gridSpacing
        let linePitch = pitch(down: grouped) ?? (slots.first { $0.id == draggingID }?.frame.height ?? 168) + gridSpacing
        let targetRow = place.row + steps(pointer.y - origin.y, pitch: linePitch, trigger: trigger)
        let targetCol = place.column + steps(pointer.x - origin.x, pitch: columnPitch, trigger: trigger)
        if targetRow >= grouped.count { return nil }
        let row = max(0, targetRow)
        let line = grouped[row]
        if targetCol >= line.count {
            return row == grouped.count - 1 ? nil : line[line.count - 1].id
        }
        return line[max(0, targetCol)].id
    }

    private static func rows(_ slots: [DayCardSlot]) -> [[DayCardSlot]] {
        let byY = slots.sorted { $0.frame.minY < $1.frame.minY }
        let tolerance = max(20, (byY.first?.frame.height ?? 168) * 0.45)
        var grouped: [[DayCardSlot]] = []
        for slot in byY {
            if let sample = grouped.last?.first, abs(slot.frame.minY - sample.frame.minY) <= tolerance {
                grouped[grouped.count - 1].append(slot)
            } else {
                grouped.append([slot])
            }
        }
        return grouped.map { $0.sorted { $0.frame.minX < $1.frame.minX } }
    }

    private static func index(of id: String, in grouped: [[DayCardSlot]]) -> (row: Int, column: Int)? {
        for (row, line) in grouped.enumerated() {
            if let column = line.firstIndex(where: { $0.id == id }) {
                return (row, column)
            }
        }
        return nil
    }

    private static func pitch(across grouped: [[DayCardSlot]]) -> CGFloat? {
        var gaps: [CGFloat] = []
        for line in grouped {
            let sorted = line.sorted { $0.frame.midX < $1.frame.midX }
            for index in 1..<sorted.count {
                gaps.append(sorted[index].frame.midX - sorted[index - 1].frame.midX)
            }
        }
        let usable = gaps.filter { $0 > 1 }
        guard usable.isEmpty == false else { return nil }
        return usable.reduce(0, +) / CGFloat(usable.count)
    }

    private static func pitch(down grouped: [[DayCardSlot]]) -> CGFloat? {
        let tops = grouped.compactMap { $0.first?.frame.minY }
        guard tops.count >= 2 else { return nil }
        var gaps: [CGFloat] = []
        for index in 1..<tops.count {
            gaps.append(tops[index] - tops[index - 1])
        }
        let usable = gaps.filter { $0 > 1 }
        guard usable.isEmpty == false else { return nil }
        return usable.reduce(0, +) / CGFloat(usable.count)
    }
}

enum ItemDragSlots {
    /// The dragged item leaves the list. The gap is the only stand-in, at the landing slot.
    static func ids(itemIDs: [String], draggingID: String?, preview: ItemDragPreview?, day: String) -> [String] {
        let visible = itemIDs.filter { $0 != draggingID }
        guard let preview, preview.day == day else { return visible }
        var slots = visible
        let gapIndex: Int
        if let beforeID = preview.beforeID {
            if let index = visible.firstIndex(of: beforeID) {
                gapIndex = index
            } else if let draggingID, beforeID == draggingID, let original = itemIDs.firstIndex(of: draggingID) {
                gapIndex = min(original, slots.count)
            } else {
                gapIndex = slots.count
            }
        } else {
            gapIndex = slots.count
        }
        slots.insert("gap", at: gapIndex)
        return slots
    }
}

@MainActor
private func boardSlots(on day: String, model: AppModel) -> [BoardSlot] {
    let items = model.items(on: day)
    let ids = ItemDragSlots.ids(
        itemIDs: items.map(\.id),
        draggingID: model.draggingItemID,
        preview: model.itemDragPreview,
        day: day
    )
    return ids.compactMap { id in
        if id == "gap" { return .gap }
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        return .item(item)
    }
}

private struct ItemDropGap: View {
    var height: CGFloat
    var radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(WorkColor.blueSoft.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(WorkColor.blue.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

private struct ItemDropDelegate: DropDelegate {
    enum Target {
        /// Insert before this item. Nil appends to the day.
        case before(String?)
        /// The day column or month cell. Keeps a row target that was just chosen.
        case column
    }

    let day: String
    let target: Target
    let model: AppModel

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        claim()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        claim()
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let day = day
        let target = target
        let preview = model.itemDragPreview
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String else { return }
            let beforeID: String?
            switch target {
            case .before(let before):
                beforeID = before
            case .column:
                beforeID = preview?.day == day ? preview?.beforeID : nil
            }
            Task { @MainActor in
                model.moveItem(id: id, to: day, before: model.landingBefore(id: id, day: day, beforeID: beforeID))
                model.clearItemDrag()
            }
        }
        return true
    }

    private func claim() {
        guard let id = model.draggingItemID else { return }
        switch target {
        case .before(let beforeID):
            model.previewItemDrop(id: id, day: day, beforeID: beforeID)
        case .column:
            model.previewItemAppend(id: id, day: day)
        }
    }
}

private struct ItemHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

@MainActor
private func draggedRowHeight(model: AppModel, fallback: CGFloat) -> CGFloat {
    guard let id = model.draggingItemID, let height = model.itemHeights[id], height > 1 else { return fallback }
    return height
}

private extension View {
    func itemDrop(day: String, beforeID: String?, model: AppModel) -> some View {
        onDrop(of: [.plainText], delegate: ItemDropDelegate(day: day, target: .before(beforeID), model: model))
    }

    /// Single click selects immediately. A paired single-tap gesture waits out the
    /// system double-click interval, which is what made the detail pane feel late.
    func itemActions(select: @escaping () -> Void, doubleClick: @escaping () -> Void) -> some View {
        self
            .onTapGesture(count: 2, perform: doubleClick)
            .simultaneousGesture(TapGesture().onEnded(select))
    }
}
