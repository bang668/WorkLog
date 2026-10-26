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
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    block("描述") {
                        Text(item.description).frame(maxWidth: 480, alignment: .leading)
                    }
                    block("备注") {
                        if item.note.isEmpty {
                            EmptyMark()
                        } else {
                            Text(item.note).frame(maxWidth: 240, alignment: .leading)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        Button("编辑") { model.beginEditSelected() }
                            .buttonStyle(.plain)
                            .foregroundStyle(WorkColor.blue)
                        Button { model.askDeleteSelected() } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                            .foregroundStyle(WorkColor.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WorkColor.card, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                Text("单击一条事项，在这里查看。")
                    .font(.system(size: 13))
                    .foregroundStyle(WorkColor.secondary)
                    .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(WorkColor.card, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func block(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(WorkColor.secondary)
            content()
                .font(.system(size: 14))
        }
        .fixedSize(horizontal: true, vertical: false)
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
