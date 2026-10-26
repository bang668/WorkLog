import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("年 / 月")
                .font(.system(size: 11))
                .foregroundStyle(WorkColor.tertiary)
                .padding(.horizontal, 16)
                .padding(.top, 52)
                .padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.years(), id: \.self) { year in
                        yearBlock(year)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(WorkColor.sidebar)
    }

    private func yearBlock(_ year: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Button {
                    if model.expandedYears.contains(year) {
                        model.expandedYears.remove(year)
                    } else {
                        model.expandedYears.insert(year)
                    }
                } label: {
                    Image(systemName: model.expandedYears.contains(year) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WorkColor.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.001))
                        .contentShape(Rectangle())
                }
                .buttonStyle(SegmentHitStyle())
                .accessibilityLabel(model.expandedYears.contains(year) ? "收起\(year)" : "展开\(year)")
                Button {
                    model.expandedYears.insert(year)
                    model.openYear(year)
                } label: {
                    Text(year)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WorkColor.ink)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .background(Color.white.opacity(0.001))
                        .contentShape(Rectangle())
                }
                .buttonStyle(FillHitButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.expandedYears.contains(year) {
                ForEach(model.months(in: year), id: \.self) { month in
                    Button {
                        model.openMonth(month)
                    } label: {
                        Text(monthTitle(month))
                            .font(.system(size: 13))
                            .foregroundStyle(WorkColor.ink)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                            .padding(.leading, 28)
                            .padding(.trailing, 8)
                            .background(
                                WorkCalendar.monthKey(fromDay: model.selectedDay) == month && model.mode == .month
                                    ? Color.white
                                    : Color.white.opacity(0.001),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FillHitButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func monthTitle(_ month: String) -> String {
        let value = Int(month.suffix(2)) ?? 0
        return String(format: "%02d月", value)
    }
}
