import SwiftUI

struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind = 1
    @State private var start = ""
    @State private var end = ""
    @State private var startMonth = ""
    @State private var endMonth = ""
    @State private var pickingStart = false
    @State private var pickingEnd = false
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var monthNumber = Calendar.current.component(.month, from: Date())
    @State private var quarter = 4
    @State private var copyInstead = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("导出 Markdown")
                .font(.system(size: 18, weight: .semibold))
            Text("默认导出当前正在看的这个月。没有事项的日期不会写进去。")
                .font(.system(size: 13))
                .foregroundStyle(WorkColor.secondary)
            WorkSegmented(titles: ["自定义", "按月", "按季度"], selection: $kind)
            if kind == 0 {
                HStack(spacing: 8) {
                    dateField("开始", day: $start, month: $startMonth, open: $pickingStart, closeOther: { pickingEnd = false })
                    dateField("结束", day: $end, month: $endMonth, open: $pickingEnd, closeOther: { pickingStart = false })
                }
            } else if kind == 1 {
                HStack(spacing: 8) {
                    WorkField(title: "年") { yearMenu }
                    WorkField(title: "月") { monthMenu }
                }
            } else {
                HStack(spacing: 8) {
                    WorkField(title: "年") { yearMenu }
                    WorkField(title: "季度") {
                        Picker("季度", selection: $quarter) {
                            Text("第 1 季度").tag(1)
                            Text("第 2 季度").tag(2)
                            Text("第 3 季度").tag(3)
                            Text("第 4 季度").tag(4)
                        }
                        .labelsHidden()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                destination(false, "保存为 Markdown 文件")
                destination(true, "复制到剪贴板")
            }
            .font(.system(size: 13))
            ScrollView {
                Text(preview)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(red: 0.227, green: 0.227, blue: 0.235))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 220)
            .background(Color(red: 0.965, green: 0.957, blue: 0.937), in: RoundedRectangle(cornerRadius: 8))
            if let message {
                Text(message).font(.system(size: 13)).foregroundStyle(WorkColor.secondary)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(WorkButtonStyle())
                Button(copyInstead ? "复制" : "导出") { perform() }
                    .buttonStyle(WorkButtonStyle(prominent: true))
            }
        }
        .padding(18)
        .frame(width: 520)
        .background(WorkColor.card)
        .onAppear { applyViewedRange() }
    }

    private var exportYears: [Int] {
        let listed = model.years().compactMap(Int.init).sorted()
        return listed.isEmpty ? [year] : listed
    }

    private var resolvedYear: Int {
        exportYears.contains(year) ? year : (exportYears.last ?? year)
    }

    private var yearSelection: Binding<Int> {
        Binding(get: { resolvedYear }, set: { year = $0 })
    }

    private func applyViewedRange() {
        let key = WorkCalendar.monthKey(fromDay: model.selectedDay)
        let viewedYear = Int(key.prefix(4)) ?? year
        if exportYears.contains(viewedYear) {
            year = viewedYear
        } else if let latest = exportYears.last {
            year = latest
        }
        monthNumber = Int(key.suffix(2)) ?? monthNumber
        start = key + "-01"
        end = model.selectedDay
        startMonth = key
        endMonth = WorkCalendar.monthKey(fromDay: end)
        quarter = (monthNumber - 1) / 3 + 1
    }

    private func dateField(
        _ title: String,
        day: Binding<String>,
        month: Binding<String>,
        open: Binding<Bool>,
        closeOther: @escaping () -> Void
    ) -> some View {
        WorkField(title: title) {
            Button {
                closeOther()
                month.wrappedValue = WorkCalendar.monthKey(fromDay: day.wrappedValue)
                open.wrappedValue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(day.wrappedValue.isEmpty ? "选择日期" : day.wrappedValue)
                        .foregroundStyle(day.wrappedValue.isEmpty ? WorkColor.tertiary : WorkColor.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(WorkColor.secondary)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(open.wrappedValue ? WorkColor.blue.opacity(0.45) : Color(red: 0.867, green: 0.839, blue: 0.796))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: open, arrowEdge: .bottom) {
                DayPicker(month: month, selectedDay: day.wrappedValue) { picked in
                    day.wrappedValue = picked
                    open.wrappedValue = false
                }
            }
        }
    }

    private var yearMenu: some View {
        Picker("年", selection: yearSelection) {
            ForEach(exportYears, id: \.self) { value in
                Text(String(value)).tag(value)
            }
        }
        .labelsHidden()
    }

    private var monthMenu: some View {
        Picker("月", selection: $monthNumber) {
            ForEach(1...12, id: \.self) { value in
                Text(String(format: "%02d月", value)).tag(value)
            }
        }
        .labelsHidden()
    }

    private func destination(_ copy: Bool, _ title: String) -> some View {
        Button {
            copyInstead = copy
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copyInstead == copy ? "circle.inset.filled" : "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(copyInstead == copy ? WorkColor.blue : WorkColor.tertiary)
                Text(title)
                    .foregroundStyle(WorkColor.ink)
            }
        }
        .buttonStyle(.plain)
    }

    private var preview: String {
        guard let scope = currentScope(), let text = model.exportMarkdown(scope: scope) else {
            return "这段时间没有记录。"
        }
        return text
    }

    private func perform() {
        guard let scope = currentScope() else {
            message = "请选择开始和结束日期。"
            return
        }
        guard let text = model.exportMarkdown(scope: scope) else {
            message = "这段时间没有记录。"
            return
        }
        if copyInstead {
            model.copyExport(text)
        } else {
            model.saveExport(text)
        }
        dismiss()
    }

    private func currentScope() -> ExportScope? {
        switch kind {
        case 0:
            guard validDay(start), validDay(end) else { return nil }
            return .custom(start: start, end: end)
        case 1:
            let key = String(format: "%04d-%02d", resolvedYear, monthNumber)
            return .month(key)
        default:
            return .quarter(year: resolvedYear, quarter: quarter)
        }
    }

    private func validDay(_ value: String) -> Bool {
        WorkCalendar.date(fromDay: value) != nil && value.count == 10
    }
}
