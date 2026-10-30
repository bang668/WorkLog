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
                ])
                field("描述", item.description)
                field("备注", item.note, emptyMark: true)
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
        Text("单击一条事项，在这里查看。")
            .font(.system(size: 13))
            .foregroundStyle(WorkColor.secondary)
            .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func dateField(_ day: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("日期").font(.system(size: 12)).foregroundStyle(WorkColor.secondary)
            Text("\(WorkCalendar.chineseYearMonthDay(day)) \(WorkCalendar.weekdayName(of: day))")
                .font(.system(size: 14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ title: String, _ value: String, emptyMark: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12)).foregroundStyle(WorkColor.secondary)
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
                        Text("日期").font(.system(size: 12)).foregroundStyle(WorkColor.secondary)
                        Text(WorkCalendar.chineseYearMonthDay(item.date)).font(.system(size: 14))
                        Text(WorkCalendar.weekdayName(of: item.date)).font(.system(size: 14))
                        TypeResultTags(names: [
                            TypeNames.parentName(typeID: item.typeId, types: model.types),
                            TypeNames.childName(typeID: item.typeId, subTypeID: item.subTypeId, types: model.types)
                        ])
                        .frame(minHeight: 22, alignment: .leading)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 170, alignment: .leading)
                    block("描述", flexible: false) {
                        FixedDescription(text: item.description, width: Self.descriptionWidth)
                    }
                    block("备注") {
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
                Text("单击一条事项，在这里查看。")
                    .font(.system(size: 13))
                    .foregroundStyle(WorkColor.secondary)
                    .multilineTextAlignment(.center)
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

    private func block(_ title: String, flexible: Bool = true, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(WorkColor.secondary)
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

    var body: some View {
        let shown = names.filter { $0.isEmpty == false }
        if shown.isEmpty == false {
            HStack(spacing: 6) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundStyle(WorkColor.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().stroke(Color(red: 0.867, green: 0.839, blue: 0.796)))
                }
            }
        }
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
