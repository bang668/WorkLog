import SwiftUI

enum WorkColor {
    static let paper = Color(red: 0.953, green: 0.945, blue: 0.925)
    static let chip = Color(red: 0.981, green: 0.971, blue: 0.954)
    static let card = Color(red: 1, green: 0.988, blue: 0.973)
    static let sidebar = Color(red: 0.910, green: 0.902, blue: 0.882)
    static let line = Color(red: 0.890, green: 0.875, blue: 0.839)
    static let ink = Color(red: 0.114, green: 0.114, blue: 0.122)
    static let secondary = Color(red: 0.431, green: 0.431, blue: 0.451)
    static let tertiary = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let blue = Color(red: 0, green: 0.478, blue: 1)
    static let blueSoft = Color(red: 0.910, green: 0.949, blue: 1)
    static let outside = Color(red: 0.969, green: 0.965, blue: 0.949)
}

struct WorkButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: prominent ? .semibold : .regular))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(prominent ? WorkColor.blue : Color.white, in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(prominent ? Color.white : WorkColor.ink)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(prominent ? Color.clear : WorkColor.line))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct WorkSegmented: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Button {
                    selection = index
                } label: {
                    Text(title)
                        .font(.system(size: 13, weight: selection == index ? .semibold : .regular))
                        .foregroundStyle(selection == index ? WorkColor.ink : WorkColor.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .frame(minWidth: 40, minHeight: 22)
                        .background {
                            if selection == index {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                            }
                        }
                        .background(Color.white.opacity(0.001))
                        .contentShape(Rectangle())
                }
                .buttonStyle(SegmentHitStyle())
            }
        }
        .padding(2)
        .background(Color(red: 0.902, green: 0.890, blue: 0.863), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SegmentHitStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
    }
}

struct FillHitButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

struct WorkMenuCard<Content: View>: View {
    var width: CGFloat? = nil
    var padding: CGFloat = 4
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(WorkColor.line))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

struct WorkMenuRows<Content: View>: View {
    var maxHeight: CGFloat
    var scrollToID: AnyHashable? = nil
    @ViewBuilder var content: Content

    var body: some View {
        MenuFit(maxHeight: maxHeight, scrollToID: scrollToID) {
            VStack(alignment: .leading, spacing: 2) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct MenuFit<Content: View>: View {
    var maxHeight: CGFloat
    var scrollToID: AnyHashable?
    @ViewBuilder var content: Content

    var body: some View {
        MenuFitLayout(maxHeight: maxHeight) {
            content
            ScrollViewReader { proxy in
                ScrollView {
                    content
                }
                .scrollBounceBehavior(.basedOnSize)
                .contentMargins(0, for: .scrollContent)
                .onAppear {
                    guard let scrollToID else { return }
                    proxy.scrollTo(scrollToID, anchor: .center)
                }
            }
        }
    }
}

private struct MenuFitLayout: Layout {
    var maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews[0].sizeThatFits(.unspecified).width
        let ideal = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: min(ideal.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideal = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
        if ideal <= maxHeight + 0.5 {
            subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: ideal))
            subviews[1].place(at: bounds.origin, anchor: .topLeading, proposal: .zero)
        } else {
            subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .zero)
            subviews[1].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}

struct WorkMenuRow: View {
    let title: String
    var selected = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(WorkColor.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(FillHitButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var fill: Color {
        if selected { return WorkColor.blueSoft }
        if hovering { return Color.black.opacity(0.05) }
        return Color.clear
    }
}

struct WorkField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(WorkColor.secondary)
            content
        }
    }
}
