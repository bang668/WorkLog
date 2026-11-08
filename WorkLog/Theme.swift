import SwiftUI

private struct WorkNightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var workNight: Bool {
        get { self[WorkNightKey.self] }
        set { self[WorkNightKey.self] = newValue }
    }
}

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

enum WorkTint {
    static let date = Color(red: 0.78, green: 0.45, blue: 0.16)
    static let dateNight = Color(red: 0.96, green: 0.72, blue: 0.42)
    static let note = Color(red: 0.45, green: 0.38, blue: 0.62)
    static let noteNight = Color(red: 0.78, green: 0.72, blue: 0.94)
    static let type = Color(red: 0.12, green: 0.48, blue: 0.42)
    static let typeNight = Color(red: 0.48, green: 0.82, blue: 0.74)

    static func date(_ night: Bool) -> Color { night ? dateNight : date }
    static func note(_ night: Bool) -> Color { night ? noteNight : note }
    static func type(_ night: Bool) -> Color { night ? typeNight : type }
}

/// One stable color per level-1 type. Light uses a pale fill and dark text;
/// night uses a deep fill and a light text of the same hue.
struct TypeTone {
    var mark: Color
    var fill: Color
    var text: Color

    static func tone(typeID: String, night: Bool) -> TypeTone? {
        guard typeID.isEmpty == false else { return nil }
        let hues: [(Color, Color, Color, Color, Color, Color)] = [
            (Color(red: 0.12, green: 0.48, blue: 0.42), Color(red: 0.86, green: 0.94, blue: 0.91), Color(red: 0.08, green: 0.36, blue: 0.32),
             Color(red: 0.48, green: 0.84, blue: 0.76), Color(red: 0.12, green: 0.28, blue: 0.26), Color(red: 0.74, green: 0.93, blue: 0.87)),
            (Color(red: 0.76, green: 0.42, blue: 0.14), Color(red: 0.98, green: 0.92, blue: 0.84), Color(red: 0.55, green: 0.28, blue: 0.06),
             Color(red: 0.96, green: 0.70, blue: 0.40), Color(red: 0.32, green: 0.20, blue: 0.10), Color(red: 0.98, green: 0.84, blue: 0.66)),
            (Color(red: 0.46, green: 0.32, blue: 0.66), Color(red: 0.93, green: 0.90, blue: 0.97), Color(red: 0.34, green: 0.20, blue: 0.52),
             Color(red: 0.78, green: 0.66, blue: 0.96), Color(red: 0.24, green: 0.16, blue: 0.32), Color(red: 0.88, green: 0.80, blue: 0.98)),
            (Color(red: 0.72, green: 0.26, blue: 0.32), Color(red: 0.98, green: 0.90, blue: 0.90), Color(red: 0.54, green: 0.14, blue: 0.20),
             Color(red: 0.96, green: 0.58, blue: 0.62), Color(red: 0.32, green: 0.14, blue: 0.16), Color(red: 0.98, green: 0.78, blue: 0.80)),
            (Color(red: 0.24, green: 0.48, blue: 0.20), Color(red: 0.90, green: 0.95, blue: 0.86), Color(red: 0.14, green: 0.36, blue: 0.12),
             Color(red: 0.62, green: 0.86, blue: 0.50), Color(red: 0.16, green: 0.26, blue: 0.12), Color(red: 0.82, green: 0.94, blue: 0.72)),
            (Color(red: 0.26, green: 0.34, blue: 0.70), Color(red: 0.90, green: 0.92, blue: 0.98), Color(red: 0.16, green: 0.22, blue: 0.52),
             Color(red: 0.66, green: 0.74, blue: 0.98), Color(red: 0.14, green: 0.16, blue: 0.32), Color(red: 0.82, green: 0.86, blue: 0.98))
        ]
        var hash = 0
        for byte in typeID.utf8 {
            hash = (hash &* 33 &+ Int(byte)) % 10007
        }
        let hue = hues[hash % hues.count]
        if night {
            return TypeTone(mark: hue.3, fill: hue.4, text: hue.5)
        }
        return TypeTone(mark: hue.0, fill: hue.1, text: hue.2)
    }
}

struct WorkMark: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 11

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size + 3, height: size + 3)
    }
}

struct WorkCaption: View {
    var title: String
    var symbol: String
    var tint: Color
    var size: CGFloat = 12
    var prominent = false
    @Environment(\.workNight) private var night

    var body: some View {
        HStack(spacing: 4) {
            WorkMark(symbol: symbol, tint: tint, size: max(9, size - 1))
            Text(title)
                .font(.system(size: size, weight: prominent ? .semibold : .regular))
                .foregroundStyle(prominent ? WorkColor.ink : (night ? Color(white: 0.62) : WorkColor.secondary))
        }
    }
}

struct WorkButtonStyle: ButtonStyle {
    var prominent = false
    var focused = false

    func makeBody(configuration: Configuration) -> some View {
        WorkButtonBody(configuration: configuration, prominent: prominent, focused: focused)
    }
}

private struct WorkButtonBody: View {
    let configuration: ButtonStyleConfiguration
    var prominent: Bool
    var focused: Bool
    @Environment(\.workNight) private var night

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: prominent ? .semibold : .regular))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(fill, in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(prominent || night ? Color.white : WorkColor.ink)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(prominent ? Color.clear : (night ? Color.white.opacity(0.16) : WorkColor.line)))
            .shadow(color: focused ? (prominent ? Color(red: 0, green: 0.25, blue: 0.65).opacity(0.45) : Color.black.opacity(0.16)) : .clear, radius: focused ? 4 : 0)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }

    private var fill: Color {
        if prominent && focused { return Color(red: 0, green: 0.28, blue: 0.68) }
        if prominent { return WorkColor.blue }
        if focused { return night ? Color(white: 0.36) : Color(red: 0.90, green: 0.875, blue: 0.84) }
        return night ? Color(white: 0.28) : Color.white
    }
}

struct WorkSegmented: View {
    let titles: [String]
    var symbols: [String] = []
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Button {
                    selection = index
                } label: {
                    HStack(spacing: 4) {
                        if symbols.indices.contains(index) {
                            Image(systemName: symbols[index])
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selection == index ? WorkColor.blue : WorkColor.secondary)
                        }
                        Text(title)
                            .font(.system(size: 13, weight: selection == index ? .semibold : .regular))
                            .foregroundStyle(selection == index ? WorkColor.ink : WorkColor.secondary)
                    }
                        .padding(.horizontal, 10)
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
    var shadowed = true
    @ViewBuilder var content: Content

    @Environment(\.workNight) private var night

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width)
            .background(night ? Color(white: 0.12) : Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(night ? Color.white.opacity(0.14) : WorkColor.line))
            .shadow(color: shadowed ? Color.black.opacity(0.12) : .clear, radius: shadowed ? 12 : 0, y: shadowed ? 6 : 0)
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
                .onChange(of: scrollToID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id, anchor: .center)
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
    @Environment(\.workNight) private var night

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(night && selected == false ? Color.white : WorkColor.ink)
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
        if hovering { return night ? Color.white.opacity(0.08) : Color.black.opacity(0.05) }
        return Color.clear
    }
}

struct WorkField<Content: View>: View {
    var title: String
    var symbol: String? = nil
    var tint: Color? = nil
    var hint: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.workNight) private var night

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let symbol {
                    WorkMark(symbol: symbol, tint: tint ?? (night ? Color(white: 0.62) : WorkColor.secondary), size: 10)
                }
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(night ? Color(white: 0.62) : WorkColor.secondary)
                if let hint, hint.isEmpty == false {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(night ? Color(red: 1, green: 0.45, blue: 0.42) : Color(red: 0.84, green: 0.16, blue: 0.14))
                        .padding(.leading, 2)
                }
            }
            content
        }
    }
}
