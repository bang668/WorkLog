import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                WorkMark(symbol: "calendar", tint: WorkTint.date, size: 10)
                Text("年 / 月")
                    .font(.system(size: 11))
                    .foregroundStyle(WorkColor.tertiary)
            }
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
        .simultaneousGesture(TapGesture().onEnded { model.clearPasteDay() })
    }

    private func yearBlock(_ year: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarHitRow {
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
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SegmentHitStyle())
                    .accessibilityLabel(model.expandedYears.contains(year) ? "收起\(year)" : "展开\(year)")
                    Button {
                        model.expandedYears.insert(year)
                        model.openYear(year)
                    } label: {
                        HStack(spacing: 6) {
                            WorkMark(symbol: "calendar", tint: WorkTint.date, size: 11)
                            Text(year)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WorkColor.ink)
                        }
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(FillHitButtonStyle())
                }
            }
            if model.expandedYears.contains(year) {
                ForEach(model.months(in: year), id: \.self) { month in
                    let selected = WorkCalendar.monthKey(fromDay: model.selectedDay) == month
                    Button {
                        model.openMonth(month)
                    } label: {
                        SidebarHitRow(selected: selected) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(selected ? WorkTint.date : WorkTint.date.opacity(0.4))
                                    .frame(width: 7, height: 7)
                                Text(monthTitle(month))
                                    .font(.system(size: 13))
                                    .foregroundStyle(WorkColor.ink)
                            }
                            .padding(.leading, 28)
                            .padding(.trailing, 8)
                        }
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

/// Hover wash for a year or month row. The selected month keeps its warm fill.
private struct SidebarHitRow<Content: View>: View {
    var selected = false
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 6))
            .background(RowHoverTracker(hovering: $hovering))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var fill: Color {
        if selected {
            return hovering
                ? Color(red: 0.99, green: 0.90, blue: 0.78)
                : Color(red: 1, green: 0.95, blue: 0.88)
        }
        return hovering ? Color(red: 0.965, green: 0.953, blue: 0.930) : Color.clear
    }
}

/// Geometry tracking, so a year row still lights up when the pointer is over its buttons.
private struct RowHoverTracker: NSViewRepresentable {
    @Binding var hovering: Bool

    func makeNSView(context: Context) -> RowHoverView {
        let view = RowHoverView()
        view.onHover = { hovering = $0 }
        return view
    }

    func updateNSView(_ nsView: RowHoverView, context: Context) {
        nsView.onHover = { hovering = $0 }
    }
}

private final class RowHoverView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }

    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
