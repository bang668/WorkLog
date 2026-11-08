import SwiftUI

struct SideInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("事项")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if model.selectedItem != nil {
                    tools
                }
            }
            if let item = model.selectedItem {
                dateField(item.date)
                TypeResultTags(names: [
                    TypeNames.parentName(typeID: item.typeId, types: model.types),
                    TypeNames.childName(typeID: item.typeId, subTypeID: item.subTypeId, types: model.types)
                ], typeID: item.typeId)
                field("描述", item.description, symbol: "text.alignleft", tint: WorkTint.type)
                field("备注", item.note, emptyMark: true, symbol: "note.text", tint: WorkTint.note)
                Spacer()
            } else {
                Spacer()
                empty
                Spacer()
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(WorkColor.card)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { model.clearPasteDay() })
    }

    private var tools: some View {
        HStack(spacing: 10) {
            Button("编辑") { model.beginEditSelected() }
                .buttonStyle(.plain)
                .foregroundStyle(WorkColor.blue)
            Button { model.askDeleteSelected() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(WorkColor.secondary)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            WorkMark(symbol: "square.text.square", tint: WorkTint.date, size: 20)
            Text("单击一条事项，在这里查看。")
                .font(.system(size: 13))
                .foregroundStyle(WorkColor.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func dateField(_ day: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            WorkCaption(title: "日期", symbol: "calendar", tint: WorkTint.date)
            Text("\(WorkCalendar.chineseYearMonthDay(day)) \(WorkCalendar.weekdayName(of: day))")
                .font(.system(size: 14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ title: String, _ value: String, emptyMark: Bool = false, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            WorkCaption(title: title, symbol: symbol, tint: tint)
            if emptyMark, value.isEmpty {
                EmptyMark()
            } else {
                Text(value).font(.system(size: 14))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BottomInspector: View {
    @Environment(AppModel.self) private var model

    /// Date label, date, weekday, and one row of type tags, plus the card padding.
    private static let cardMinHeight: CGFloat = 110
    /// Fixed description column in the bottom item view.
    private static let descriptionWidth: CGFloat = 270

    var body: some View {
        Group {
            if let item = model.selectedItem {
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 4) {
                        WorkCaption(title: "日期", symbol: "calendar", tint: WorkTint.date)
                        Text(WorkCalendar.chineseYearMonthDay(item.date)).font(.system(size: 14))
                        Text(WorkCalendar.weekdayName(of: item.date)).font(.system(size: 14))
                        TypeResultTags(names: [
                            TypeNames.parentName(typeID: item.typeId, types: model.types),
                            TypeNames.childName(typeID: item.typeId, subTypeID: item.subTypeId, types: model.types)
                        ], typeID: item.typeId)
                        .frame(minHeight: 22, alignment: .leading)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 170, alignment: .leading)
                    block("描述", symbol: "text.alignleft", tint: WorkTint.type, flexible: false) {
                        FixedDescription(text: item.description, width: Self.descriptionWidth)
                    }
                    block("备注", symbol: "note.text", tint: WorkTint.note) {
                        if item.note.isEmpty {
                            EmptyMark().frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(item.note)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        Button("编辑") { model.beginEditSelected() }
                            .buttonStyle(.plain)
                            .foregroundStyle(WorkColor.blue)
                        Button { model.askDeleteSelected() } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                            .foregroundStyle(WorkColor.secondary)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: Self.cardMinHeight, alignment: .topLeading)
                .background(WorkColor.card, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                VStack(spacing: 8) {
                    WorkMark(symbol: "square.text.square", tint: WorkTint.date, size: 20)
                    Text("单击一条事项，在这里查看。")
                        .font(.system(size: 13))
                        .foregroundStyle(WorkColor.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: Self.cardMinHeight)
                .background(WorkColor.card, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { model.clearPasteDay() })
    }

    private func block(_ title: String, symbol: String, tint: Color, flexible: Bool = true, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WorkCaption(title: title, symbol: symbol, tint: tint)
            content()
                .font(.system(size: 14))
        }
        .frame(maxWidth: flexible ? .infinity : nil, alignment: .leading)
        .fixedSize(horizontal: flexible == false, vertical: false)
    }

}

/// Description stays one width. Extra lines wrap, and a long body scrolls inside the column.
private struct FixedDescription: View {
    let text: String
    var width: CGFloat
    /// About four lines, then the column scrolls instead of growing the bar.
    private let maxHeight: CGFloat = 88
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let limit = contentHeight > maxHeight ? maxHeight : nil
        Group {
            if contentHeight > maxHeight {
                ScrollView { wrapping }
                    .scrollIndicators(.visible)
            } else {
                wrapping
            }
        }
        .frame(width: width, height: limit, alignment: .topLeading)
        .background { measure }
        .onPreferenceChange(DescriptionHeightKey.self) { contentHeight = $0 }
    }

    private var wrapping: some View {
        Text(text)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var measure: some View {
        Text(text)
            .font(.system(size: 14))
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: DescriptionHeightKey.self, value: geo.size.height)
                }
            }
    }
}

private struct DescriptionHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TypeResultTags: View {
    let names: [String]
    var typeID: String = ""
    /// Week rows are narrow, so the tags are smaller and wrap onto the next line.
    var compact = false
    @Environment(\.workNight) private var night

    var body: some View {
        let shown = names.filter { $0.isEmpty == false }
        let tone = TypeTone.tone(typeID: typeID, night: night)
        if shown.isEmpty == false {
            let row = ForEach(Array(shown.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(tone?.text ?? (night ? Color(white: 0.78) : WorkColor.secondary))
                    .lineLimit(1)
                    .padding(.horizontal, compact ? 6 : 8)
                    .frame(height: compact ? 18 : 22)
                    .background(tone?.fill ?? (night ? Color(white: 0.22) : Color.white), in: Capsule())
                    .overlay(Capsule().stroke(tone?.mark.opacity(0.35) ?? (night ? Color.white.opacity(0.16) : Color(red: 0.867, green: 0.839, blue: 0.796))))
            }
            if compact {
                WrappingTagRow(spacing: 4, lineSpacing: 4) { row }
            } else {
                HStack(spacing: 6) { row }
            }
        }
    }
}

/// Lays tags on one line, then continues on the next when the column is too narrow.
private struct WrappingTagRow: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .greatestFiniteMagnitude
        let rows = lines(limit: limit, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(limit: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in line.items {
                item.view.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Placed {
        var view: LayoutSubview
        var size: CGSize
    }

    private struct Line {
        var items: [Placed]
        var width: CGFloat
        var height: CGFloat
    }

    private func lines(limit: CGFloat, subviews: Subviews) -> [Line] {
        var rows: [Line] = []
        var current: [Placed] = []
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        func push() {
            guard current.isEmpty == false else { return }
            let width = x > 0 ? x - spacing : 0
            rows.append(Line(items: current, width: width, height: rowHeight))
            current = []
            x = 0
            rowHeight = 0
        }
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let fitted = CGSize(width: min(ideal.width, limit), height: ideal.height)
            if current.isEmpty == false, x + fitted.width > limit {
                push()
            }
            current.append(Placed(view: view, size: fitted))
            rowHeight = max(rowHeight, fitted.height)
            x += fitted.width + spacing
        }
        push()
        return rows
    }
}

struct EmptyMark: View {
    var body: some View {
        Capsule()
            .fill(WorkColor.tertiary)
            .frame(width: 10, height: 1.5)
            .frame(height: 18, alignment: .center)
    }
}
