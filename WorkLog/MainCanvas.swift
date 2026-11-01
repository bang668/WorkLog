import SwiftUI

private struct ChipFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct MainCanvas: View {
    @Environment(AppModel.self) private var model
    @AppStorage("worklog.sidebarCollapsed") private var sidebarCollapsed = false
    @State private var chipFrame: CGRect = .zero
    @State private var titleHovering = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Group {
                if model.editorKind == .bottom {
                    VStack(spacing: 0) {
                        calendar.frame(maxHeight: .infinity)
                        BottomInspector()
                    }
                } else {
                    HStack(spacing: 0) {
                        calendar
                        if model.editorKind == .right {
                            Divider()
                            SideInspector()
                                .frame(width: 268)
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: "canvas")
        .background(WorkColor.paper)
        .onPreferenceChange(ChipFrameKey.self) { chipFrame = $0 }
        .overlay { pickerOverlay }
        .onAppear { model.loadMonths(for: visibleDays) }
        .onChange(of: model.selectedDay) { _, _ in model.loadMonths(for: visibleDays) }
        .onChange(of: model.mode) { _, mode in
            if mode == .day { model.clearPasteDay() }
            if mode == .day || mode == .week {
                model.expandedYears.insert(String(model.selectedDay.prefix(4)))
            }
            model.loadMonths(for: visibleDays)
        }
    }

    private var calendar: some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.clearPasteDay() }
            board
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            DrawerOverlay()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var board: some View {
        switch model.mode {
        case .day:
            DayBoard()
        case .week:
            WeekBoard()
        case .month:
            MonthBoard()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { sidebarCollapsed.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WorkColor.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.001))
                    .contentShape(Rectangle())
            }
            .buttonStyle(SegmentHitStyle())
            .accessibilityLabel(sidebarCollapsed ? "显示侧栏" : "收起侧栏")
            WorkSegmented(titles: CalendarMode.allCases.map(\.title), selection: modeIndex)
            chevron("chevron.left") { model.shift(-1) }
            Button { togglePicker() } label: {
                Text(chipTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Color.black.opacity(titleHovering ? 0.1 : 0.05),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { titleHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: titleHovering)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: ChipFrameKey.self, value: geo.frame(in: .named("canvas")))
                }
            }
            chevron("chevron.right") { model.shift(1) }
            if let caption = titleCaption {
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(WorkColor.secondary)
            }
            Spacer()
            if let status = model.statusMessage {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(WorkColor.secondary)
            }
            Button("今天") { model.showToday() }
                .buttonStyle(WorkButtonStyle())
        }
        .padding(.leading, sidebarCollapsed ? 72 : 14)
        .padding(.trailing, 14)
        .frame(height: 52)
        .background(WorkColor.card.opacity(0.92))
        .simultaneousGesture(TapGesture().onEnded { model.clearPasteDay() })
        .overlay(alignment: .bottom) { Rectangle().fill(WorkColor.line).frame(height: 1) }
    }

    private func chevron(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WorkColor.secondary)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.001))
                .contentShape(Rectangle())
        }
        .buttonStyle(SegmentHitStyle())
    }

    @ViewBuilder
    private var pickerOverlay: some View {
        if model.activePicker != nil, chipFrame != .zero {
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .onTapGesture {
                        model.clearPasteDay()
                        model.activePicker = nil
                    }
                picker
                    .fixedSize(horizontal: true, vertical: true)
                    .offset(x: chipFrame.minX, y: chipFrame.maxY + 8)
            }
        }
    }

    @ViewBuilder
    private var picker: some View {
        switch model.activePicker {
        case .week:
            WeekPicker()
        case .month:
            MonthPicker()
        case .day:
            DayPicker(month: pickerMonthBinding, selectedDay: model.selectedDay) { day in
                model.clearPasteDay()
                model.go(to: day, keepPicker: true)
            }
        case nil:
            EmptyView()
        }
    }

    private var chipTitle: String {
        switch model.mode {
        case .day:
            WorkCalendar.chineseYearMonthDay(model.selectedDay)
        case .week:
            "第 \(WorkCalendar.isoWeek(of: model.selectedDay) ?? 0) 周"
        case .month:
            WorkCalendar.chineseYearMonth(WorkCalendar.monthKey(fromDay: model.selectedDay))
        }
    }

    private var titleCaption: String? {
        switch model.mode {
        case .day:
            let week = WorkCalendar.isoWeek(of: model.selectedDay) ?? 0
            let todayMark = model.selectedDay == model.today ? " · 今天" : ""
            return "\(WorkCalendar.weekdayName(of: model.selectedDay)) · 第 \(week) 周\(todayMark)"
        case .week:
            return weekRange
        case .month:
            return nil
        }
    }

    private var weekRange: String {
        WorkCalendar.weekRangeLabel(days: WorkCalendar.weekDays(containing: model.selectedDay))
    }

    private var visibleDays: [String] {
        switch model.mode {
        case .day:
            return [model.selectedDay]
        case .week:
            return WorkCalendar.weekDays(containing: model.selectedDay)
        case .month:
            return WorkCalendar.weeks(inMonth: WorkCalendar.monthKey(fromDay: model.selectedDay)).flatMap { $0 }
        }
    }

    private var modeIndex: Binding<Int> {
        Binding(
            get: { CalendarMode.allCases.firstIndex(of: model.mode) ?? 0 },
            set: { index in
                model.mode = CalendarMode.allCases[index]
                model.activePicker = nil
            }
        )
    }

    private var pickerMonthBinding: Binding<String> {
        Binding(get: { model.pickerMonth }, set: { model.pickerMonth = $0 })
    }

    private func togglePicker() {
        let next: ActivePicker = switch model.mode {
        case .day: .day
        case .week: .week
        case .month: .month
        }
        if model.activePicker == next {
            model.activePicker = nil
        } else {
            model.pickerMonth = WorkCalendar.monthKey(fromDay: model.selectedDay)
            model.activePicker = next
        }
    }
}

private struct WeekPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = WorkCalendar.isoWeek(of: model.selectedDay) ?? 1
        WorkMenuCard(width: 228) {
            WorkMenuRows(maxHeight: 320, scrollToID: current) {
                ForEach(weeks, id: \.self) { week in
                    weekRow(week, current: current)
                }
            }
        }
    }

    private func weekRow(_ week: Int, current: Int) -> some View {
        let monday = WorkCalendar.mondayOfISOWeek(week, year: year) ?? model.selectedDay
        let days = WorkCalendar.weekDays(containing: monday)
        return WorkMenuRow(
            title: "第\(week)周　\(WorkCalendar.chineseMonthDay(days.first ?? monday)) – \(WorkCalendar.chineseMonthDay(days.last ?? monday))",
            selected: week == current
        ) {
            model.jumpToWeek(week)
        }
        .id(week)
    }

    private var year: Int { WorkCalendar.isoWeekYear(of: model.selectedDay) ?? 2026 }
    private var weeks: [Int] {
        (1...53).filter { week in
            guard let monday = WorkCalendar.mondayOfISOWeek(week, year: year),
                  WorkCalendar.isoWeekYear(of: monday) == year,
                  WorkCalendar.isoWeek(of: monday) == week else { return false }
            return true
        }
    }
}

private struct MonthPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let months = model.visibleMonths()
        let current = WorkCalendar.monthKey(fromDay: model.selectedDay)
        WorkMenuCard(width: 124) {
            WorkMenuRows(maxHeight: 320) {
                ForEach(months, id: \.self) { month in
                    WorkMenuRow(title: WorkCalendar.chineseYearMonth(month), selected: month == current) {
                        model.openMonth(month)
                        model.activePicker = .month
                    }
                }
            }
        }
    }
}

struct DayPicker: View {
    @Binding var month: String
    var selectedDay: String
    var onSelect: (String) -> Void
    @Environment(\.workNight) private var night

    var body: some View {
        WorkMenuCard(width: 292, padding: 8) {
            dayBody
        }
    }

    private var dayBody: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                MenuChevron(name: "chevron.left") { shiftMonth(-1) }
                Spacer(minLength: 0)
                Text(WorkCalendar.chineseYearMonth(month))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(night ? Color.white : WorkColor.ink)
                Spacer(minLength: 0)
                MenuChevron(name: "chevron.right") { shiftMonth(1) }
            }
            let weeks = WorkCalendar.weeks(inMonth: month)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(WorkCalendar.weekdaySymbols, id: \.self) { symbol in
                    Text(String(symbol.suffix(1)))
                        .font(.system(size: 11))
                        .foregroundStyle(night ? Color(white: 0.55) : WorkColor.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(weeks.flatMap { $0 }, id: \.self) { day in
                    DayMenuCell(day: day, month: month, selected: day == selectedDay) {
                        onSelect(day)
                    }
                }
            }
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = WorkCalendar.shiftingMonth(month, by: delta) {
            month = next
        }
    }
}

private struct MenuChevron: View {
    let name: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.workNight) private var night

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? (night ? Color.white : WorkColor.ink) : (night ? Color(white: 0.62) : WorkColor.secondary))
                .frame(width: 28, height: 28)
                .background(hovering ? (night ? Color.white.opacity(0.08) : Color.black.opacity(0.05)) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct DayMenuCell: View {
    let day: String
    let month: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.workNight) private var night

    var body: some View {
        let inside = WorkCalendar.monthKey(fromDay: day) == month
        Button(action: action) {
            Text(String(format: "%02d", Int(day.suffix(2)) ?? 0))
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(fill, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? Color.white : (inside ? (night ? Color.white : WorkColor.ink) : (night ? Color(white: 0.45) : WorkColor.secondary)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var fill: Color {
        if selected { return WorkColor.blue }
        if hovering { return night ? Color.white.opacity(0.08) : Color.black.opacity(0.05) }
        return Color.clear
    }
}

