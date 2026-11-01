import AppKit
import SwiftUI

private struct PopupKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private enum FieldMetrics {
    static let fontSize: CGFloat = 13
    static let inset: CGFloat = 8
    static var font: NSFont { .systemFont(ofSize: fontSize) }
    static var placeholderColor: NSColor { NSColor(srgbRed: 0.557, green: 0.557, blue: 0.576, alpha: 1) }
}

private struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focused: Bool
    var onEdit: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.fittingSize.width, height: proposal.height ?? 88)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteTextView.make(frame: NSRect(x: 0, y: 0, width: 300, height: 88))
        textView.placeholder = placeholder
        textView.string = text
        textView.delegate = context.coordinator
        let scroll = NoteScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.focusRingType = .none
        scroll.documentView = textView
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return scroll
    }

    @Environment(\.workNight) private var night

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NoteTextView else { return }
        textView.placeholder = placeholder
        textView.usesLightText = night
        context.coordinator.applyFocus(textView, wants: focused)
        guard textView.hasMarkedText() == false, textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        private var focusRetry = 0

        init(_ parent: NoteEditor) { self.parent = parent }

        func applyFocus(_ textView: NSTextView, wants: Bool) {
            if wants == false {
                focusRetry = 0
                if textView.window?.firstResponder === textView {
                    textView.window?.makeFirstResponder(textView.window?.contentView)
                }
                return
            }
            guard textView.window?.firstResponder !== textView else { return }
            guard let window = textView.window else {
                guard focusRetry < 4 else { return }
                focusRetry += 1
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView, self.parent.focused else { return }
                    self.applyFocus(textView, wants: true)
                }
                return
            }
            focusRetry = 0
            window.makeFirstResponder(textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onEdit()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if textView.hasMarkedText() { return }
            if textView.string != parent.text { parent.text = textView.string }
        }
    }
}

private final class NoteScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let textView = documentView as? NoteTextView else { return }
        let visible = contentSize
        let width = max(visible.width, 1)
        let height = max(textView.frame.height, visible.height)
        textView.minSize = NSSize(width: 0, height: visible.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        guard abs(textView.frame.width - width) > 0.5 || textView.frame.height + 0.5 < height else { return }
        textView.setFrameSize(NSSize(width: width, height: height))
    }
}

private final class NoteTextView: NSTextView {
    var placeholder = ""
    var usesLightText = false {
        didSet { guard usesLightText != oldValue else { return }; lockMetrics(); needsDisplay = true }
    }

    static func make(frame: NSRect) -> NoteTextView {
        let container = NSTextContainer(size: NSSize(width: max(frame.width, 1), height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(manager)
        return NoteTextView(frame: frame, textContainer: container)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        isRichText = false
        importsGraphics = false
        isEditable = true
        isSelectable = true
        allowsUndo = true
        drawsBackground = false
        focusRingType = .none
        usesFontPanel = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        lockMetrics()
    }

    required init?(coder: NSCoder) { nil }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        lockMetrics()
        return accepted
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, placeholder.isEmpty == false else { return }
        let font = self.font ?? FieldMetrics.font
        let inset = textContainerInset
        let padding = textContainer?.lineFragmentPadding ?? 0
        let rect = NSRect(
            x: inset.width + padding,
            y: inset.height,
            width: max(0, bounds.width - inset.width * 2 - padding),
            height: ceil(font.boundingRectForFont.height)
        )
        placeholder.draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: usesLightText ? NSColor(white: 0.55, alpha: 1) : FieldMetrics.placeholderColor
        ])
    }

    private func lockMetrics() {
        let font = FieldMetrics.font
        let inset = NSSize(width: FieldMetrics.inset, height: FieldMetrics.inset)
        let color: NSColor = usesLightText ? .white : .textColor
        if self.font?.pointSize != FieldMetrics.fontSize { self.font = font }
        if textColor != color { textColor = color }
        if insertionPointColor != color { insertionPointColor = color }
        if (typingAttributes[.font] as? NSFont)?.pointSize != FieldMetrics.fontSize || (typingAttributes[.foregroundColor] as? NSColor) != color {
            typingAttributes[.font] = font
            typingAttributes[.foregroundColor] = color
        }
        if textContainerInset != inset { textContainerInset = inset }
        if textContainer?.lineFragmentPadding != 0 { textContainer?.lineFragmentPadding = 0 }
    }
}

private struct ClearMark: View {
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.workNight) private var night

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(night ? Color(white: 0.7) : WorkColor.secondary)
                .frame(width: 16, height: 16)
                .background {
                    Circle().fill((night ? Color.white : Color.black).opacity(hovering ? 0.12 : 0))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("清空")
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct TypeChip: View {
    let title: String
    let selected: Bool
    var emphasized = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.workNight) private var night

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(selected ? WorkColor.ink : (night ? Color(white: 0.78) : WorkColor.secondary))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(fill, in: Capsule())
                .overlay(Capsule().stroke(selected ? WorkColor.blue : line))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var fill: Color {
        if selected && emphasized { return Color(red: 0.75, green: 0.86, blue: 1) }
        if selected { return WorkColor.blueSoft }
        if hovering { return night ? Color.white.opacity(0.08) : Color.black.opacity(0.04) }
        return night ? Color(white: 0.28) : Color.white
    }

    private var line: Color {
        if night { return hovering ? Color.white.opacity(0.28) : Color.white.opacity(0.16) }
        return hovering ? Color(red: 0.78, green: 0.75, blue: 0.70) : Color(red: 0.867, green: 0.839, blue: 0.796)
    }
}

struct ChipWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

private struct TypeMenu: View {
    let menuID: String
    let names: [(String, String)]
    @Binding var selection: String
    var enabled: Bool
    var isOpen: Bool
    var setOpen: (Bool) -> Void
    @State private var hovering = false

    private var chosen: String? {
        guard selection.isEmpty == false else { return nil }
        return names.first(where: { $0.0 == selection })?.1
    }

    var body: some View {
        field
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: PopupKey.self, value: [menuID: geo.frame(in: .named("drawerForm"))])
                }
            }
    }

    private var field: some View {
        HStack(spacing: 2) {
            Text(chosen ?? "未选择")
                .foregroundStyle(chosen == nil || enabled == false ? WorkColor.tertiary : WorkColor.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
            if enabled && selection.isEmpty == false {
                Button {
                    selection = ""
                    setOpen(false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WorkColor.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空")
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(enabled ? WorkColor.secondary : WorkColor.tertiary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
        }
        .font(.system(size: 13))
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .background(fieldFill, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(fieldStroke))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var fieldFill: Color {
        if enabled == false { return Color(red: 0.965, green: 0.957, blue: 0.937) }
        if hovering { return Color.black.opacity(0.04) }
        return Color.white
    }

    private var fieldStroke: Color {
        if isOpen { return WorkColor.blue.opacity(0.45) }
        if hovering { return Color(red: 0.78, green: 0.75, blue: 0.70) }
        return Color(red: 0.867, green: 0.839, blue: 0.796)
    }

    private func toggle() {
        if enabled { setOpen(isOpen == false) }
    }
}

private enum FormField: Hashable {
    case description, level1, level2, note, reset, cancel, submit
}

/// Tab order for the add/edit form. The system key loop also includes the date
/// button and the action buttons, so those keys are handled here instead.
private struct FormKeyCatcher: NSViewRepresentable {
    var isForm: Bool
    var field: FormField
    var level1IDs: [String]
    var level2IDs: [String]
    var selected1: String
    var selected2: String
    var onFocus: (FormField) -> Void
    var onSelect1: (String) -> Void
    var onSelect2: (String) -> Void
    var suggestionCount = 0
    var onMoveSuggestion: (Int) -> Void
    var onUseSuggestion: () -> Void
    var onCloseSuggestions: () -> Void
    var onSubmit: () -> Void
    var onReset: () -> Void
    var onCancel: () -> Void
    var onEscape: () -> Void
    var windowID = "worklog.main"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return PassThroughView()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sync(self)
    }

    final class Coordinator {
        var isForm = false
        var field = FormField.description
        var level1IDs: [String] = []
        var level2IDs: [String] = []
        var selected1 = ""
        var selected2 = ""
        var cursor1 = ""
        var cursor2 = ""
        var onFocus: (FormField) -> Void = { _ in }
        var onSelect1: (String) -> Void = { _ in }
        var onSelect2: (String) -> Void = { _ in }
        var suggestionCount = 0
        var onMoveSuggestion: (Int) -> Void = { _ in }
        var onUseSuggestion: () -> Void = {}
        var onCloseSuggestions: () -> Void = {}
        var onSubmit: () -> Void = {}
        var onReset: () -> Void = {}
        var onCancel: () -> Void = {}
        var onEscape: () -> Void = {}
        var windowID = "worklog.main"
        private var monitor: Any?

        func sync(_ view: FormKeyCatcher) {
            isForm = view.isForm
            field = view.field
            level1IDs = view.level1IDs
            level2IDs = view.level2IDs
            selected1 = view.selected1
            selected2 = view.selected2
            if level1IDs.contains(selected1) { cursor1 = selected1 }
            if level2IDs.contains(selected2) { cursor2 = selected2 }
            onFocus = view.onFocus
            onSelect1 = view.onSelect1
            onSelect2 = view.onSelect2
            suggestionCount = view.suggestionCount
            onMoveSuggestion = view.onMoveSuggestion
            onUseSuggestion = view.onUseSuggestion
            onCloseSuggestions = view.onCloseSuggestions
            onSubmit = view.onSubmit
            onReset = view.onReset
            onCancel = view.onCancel
            onEscape = view.onEscape
            windowID = view.windowID
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let keyCode = event.keyCode
                // Option, Command, and Control alone are not form keys. Handling
                // them here crashes when a double-tap is what opened the window.
                if DoubleModifierKind.isModifierKey(keyCode) { return event }
                let shift = event.modifierFlags.contains(.shift)
                let command = event.modifierFlags.contains(.command)
                let control = event.modifierFlags.contains(.control)
                let option = event.modifierFlags.contains(.option)
                let eventWindow = event.window?.identifier?.rawValue
                let consumed = MainActor.assumeIsolated {
                    self.handle(
                        keyCode: keyCode,
                        shift: shift,
                        command: command,
                        control: control,
                        option: option,
                        eventWindow: eventWindow
                    )
                }
                return consumed ? nil : event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(keyCode: UInt16, shift: Bool, command: Bool, control: Bool, option: Bool, eventWindow: String?) -> Bool {
            guard isForm, eventWindow == windowID else { return false }
            if TextEdit.handleShortcut(keyCode: keyCode, shift: shift, command: command, control: control, option: option) {
                return true
            }
            let extra = command || control || option
            if keyCode == 53, extra == false {
                if field == .description, suggestionCount > 0 {
                    onCloseSuggestions()
                    return true
                }
                onEscape()
                return true
            }
            if keyCode == 48, extra == false {
                move(by: shift ? -1 : 1)
                return true
            }
            if field == .description, suggestionCount > 0, extra == false, shift == false {
                if keyCode == 126 { onMoveSuggestion(-1); return true }
                if keyCode == 125 { onMoveSuggestion(1); return true }
            }
            if (keyCode == 36 || keyCode == 76), extra == false, shift == false {
                if field == .description, suggestionCount > 0 {
                    onUseSuggestion()
                    return true
                }
                if field == .submit { onSubmit(); return true }
                if field == .reset { onReset(); return true }
                if field == .cancel { onCancel(); return true }
            }
            if field == .reset || field == .cancel || field == .submit, extra == false, shift == false {
                if keyCode == 123, let next = stepButton(by: -1) { focus(next); return true }
                if keyCode == 124, let next = stepButton(by: 1) { focus(next); return true }
            }
            guard field == .level1 || field == .level2, extra == false, shift == false else { return false }
            if keyCode == 49 { toggleTag(); return true }
            if keyCode == 123 { moveTag(by: -1); return true }
            if keyCode == 124 { moveTag(by: 1); return true }
            return false
        }

        private func stepButton(by delta: Int) -> FormField? {
            let order: [FormField] = [.reset, .cancel, .submit]
            guard let index = order.firstIndex(of: field) else { return nil }
            let next = index + delta
            guard order.indices.contains(next) else { return nil }
            return order[next]
        }

        private func focus(_ next: FormField) {
            guard field != next else { return }
            field = next
            onFocus(field)
        }

        private func move(by delta: Int) {
            let order: [FormField] = [.description, .level1, .level2, .note, .submit]
            let current: FormField = (field == .reset || field == .cancel) ? .submit : field
            guard let index = order.firstIndex(of: current) else { return }
            let next = index + delta
            guard order.indices.contains(next) else { return }
            field = order[next]
            onFocus(field)
            ensureSelection()
        }

        /// Landing on a type row with nothing chosen picks the first tag.
        private func ensureSelection() {
            switch field {
            case .level1:
                guard level1IDs.contains(selected1) == false, let first = level1IDs.first else { return }
                cursor1 = first
                selected1 = first
                onSelect1(first)
            case .level2:
                guard level2IDs.contains(selected2) == false, let first = level2IDs.first else { return }
                cursor2 = first
                selected2 = first
                onSelect2(first)
            default:
                break
            }
        }

        private func toggleTag() {
            let level1 = field == .level1
            let ids = level1 ? level1IDs : level2IDs
            let selected = level1 ? selected1 : selected2
            let cursor = level1 ? cursor1 : cursor2
            let current = ids.contains(selected) ? selected : (ids.contains(cursor) ? cursor : ids.first)
            guard let current else { return }
            let next = selected == current ? "" : current
            if level1 {
                cursor1 = current
                selected1 = next
                onSelect1(next)
            } else {
                cursor2 = current
                selected2 = next
                onSelect2(next)
            }
        }

        private func moveTag(by delta: Int) {
            let level1 = field == .level1
            let ids = level1 ? level1IDs : level2IDs
            let selected = level1 ? selected1 : selected2
            let cursor = level1 ? cursor1 : cursor2
            let current = ids.contains(selected) ? selected : cursor
            guard let next = Self.step(ids, current: current, delta: delta) else { return }
            if level1 {
                cursor1 = next
                selected1 = next
                onSelect1(next)
            } else {
                cursor2 = next
                selected2 = next
                onSelect2(next)
            }
        }

        private static func step(_ ids: [String], current: String, delta: Int) -> String? {
            guard ids.isEmpty == false else { return nil }
            guard let index = ids.firstIndex(of: current) else {
                return delta > 0 ? ids[0] : ids[ids.count - 1]
            }
            let next = index + delta
            guard ids.indices.contains(next) else { return nil }
            return ids[next]
        }
    }

    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct DrawerOverlay: View {
    var place: DraftPlace = .main
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var openMenu: String?
    @State private var dropped = false
    @State private var menuFrames: [String: CGRect] = [:]
    @State private var draftPickerMonth = ""
    @State private var formField = FormField.description
    @State private var suggestions: [DescriptionSuggestion] = []
    @State private var suggestionIndex = 0
    @State private var holdSuggestions = false
    @FocusState private var descriptionFocused: Bool

    private var editing: ItemDraft? { model.editingDraft(place) }

    private var formWindowID: String { place == .quick ? "worklog.quick" : "worklog.main" }

    private var quickNight: Bool {
        switch model.quickAppearance {
        case .dark: true
        case .light: false
        case .system: colorScheme == .dark
        }
    }

    private var night: Bool { place == .quick && quickNight }

    private var fieldFill: Color { night ? Color(white: 0.24) : Color.white }

    private var fieldLine: Color {
        night ? Color.white.opacity(0.16) : Color(red: 0.867, green: 0.839, blue: 0.796)
    }

    /// Menu bar on the screen the card is attached to, so the title stays under the notch there.
    private var menuBarBand: CGFloat {
        let host = NSApp.windows.first { $0.identifier?.rawValue == "worklog.quick" }?.screen
        let screen = host
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let screen else { return NSStatusBar.system.thickness }
        return max(screen.frame.maxY - screen.visibleFrame.maxY, 1)
    }

    private var quickTopPadding: CGFloat { menuBarBand + 14 }

    var body: some View {
        if place == .quick {
            quickStage
        } else {
            mainStage
        }
    }

    private var mainStage: some View {
        ZStack(alignment: .top) {
            if model.draft != nil {
                Color(red: 40 / 255, green: 36 / 255, blue: 30 / 255).opacity(0.28)
                    .transition(.opacity)
                    .onTapGesture {
                        model.clearPasteDay()
                        model.cancelDraft()
                    }
            }
            if model.draft != nil {
                drawer
                    .frame(width: 420)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.move(edge: .top))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.draft != nil)
        .onChange(of: model.draft == nil) { _, closed in
            if closed { closeSuggestions() }
        }
        .allowsHitTesting(model.draft != nil)
    }

    private var quickStage: some View {
        ZStack(alignment: .top) {
            Color(red: 40 / 255, green: 36 / 255, blue: 30 / 255)
                .opacity(dropped ? 0.28 : 0)
                .allowsHitTesting(dropped)
                .onTapGesture { model.cancelDraft(.quick) }
            if dropped {
                quickCard
                    .fixedSize()
                    .transition(.move(edge: .top))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .environment(\.workNight, quickNight)
        .environment(\.colorScheme, quickNight ? .dark : .light)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: dropped)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                dropped = true
            }
        }
        .onChange(of: model.quickClosing) { _, closing in
            guard closing else { return }
            closeSuggestions()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                dropped = false
            }
        }
        .alert("描述不能为空", isPresented: quickAlertPresented) {
            Button("好") { model.dismissQuickAlert() }
        } message: {
            Text("写一下做了什么，再保存。")
        }
    }

    private var quickAlertPresented: Binding<Bool> {
        Binding(
            get: { model.quickAlertPresented },
            set: { if $0 == false { model.dismissQuickAlert() } }
        )
    }

    private var quickCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加事项")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(night ? Color.white : WorkColor.ink)
            formBody
        }
        .padding(.horizontal, 18)
        .padding(.top, quickTopPadding)
        .padding(.bottom, 14)
        .frame(width: 420)
        .background(night ? Color.black : WorkColor.card, in: UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
        .coordinateSpace(name: "drawerForm")
        .onPreferenceChange(PopupKey.self) { menuFrames = $0 }
        .compositingGroup()
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
        .overlay { floatingMenu }
        .overlay(alignment: .topLeading) { suggestionMenu }
        .animation(.easeOut(duration: 0.12), value: openMenu)
        .focusedValue(\.worklogFieldEditing, true)
    }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if model.draft?.purpose != .add {
                    Button("编辑") { model.beginEditSelected() }
                        .buttonStyle(.plain)
                        .foregroundStyle(WorkColor.blue)
                        .opacity(model.draft?.purpose == .view ? 1 : 0)
                        .disabled(model.draft?.purpose != .view)
                    Button { model.askDeleteSelected() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WorkColor.secondary)
                }
            }
            if model.draft?.purpose == .view {
                viewBody
            } else {
                formBody
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(WorkColor.card, in: UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
        .coordinateSpace(name: "drawerForm")
        .onPreferenceChange(PopupKey.self) { menuFrames = $0 }
        .compositingGroup()
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
        .overlay { floatingMenu }
        .overlay(alignment: .topLeading) { suggestionMenu }
        .animation(.easeOut(duration: 0.12), value: openMenu)
        .focusedValue(\.worklogFieldEditing, model.draft?.purpose != .view)
    }

    @ViewBuilder
    private var floatingMenu: some View {
        if let id = openMenu, let frame = menuFrames[id] {
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .onTapGesture { openMenu = nil }
                Group {
                    if id == "date" {
                        DayPicker(month: $draftPickerMonth, selectedDay: editing?.date ?? model.selectedDay) { day in
                            model.updateDraft(place) { $0.date = day }
                            openMenu = nil
                        }
                    } else {
                        menuCard(id: id, width: frame.width)
                    }
                }
                .offset(x: frame.minX, y: frame.maxY + 4)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var suggestionMenu: some View {
        if formField == .description, suggestions.isEmpty == false, let frame = menuFrames["suggest"], suggestions.indices.contains(suggestionIndex) {
            WorkMenuCard(width: frame.width, shadowed: false) {
                WorkMenuRows(maxHeight: 180, scrollToID: suggestions[suggestionIndex].description) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                        WorkMenuRow(title: item.description, selected: index == suggestionIndex) {
                            applySuggestion(item)
                        }
                        .id(item.description)
                    }
                }
            }
            .offset(x: frame.minX, y: frame.maxY + 4)
        }
    }

    private func menuCard(id: String, width: CGFloat) -> some View {
        let names = id == "type" ? model.types.map { ($0.id, $0.name) } : children.filter { $0.name.isEmpty == false }.map { ($0.id, $0.name) }
        let selection = id == "type" ? typeBinding : subTypeBinding
        return WorkMenuCard(width: width) {
            WorkMenuRows(maxHeight: 180) {
                if names.isEmpty {
                    Text("还没有类型")
                        .font(.system(size: 13))
                        .foregroundStyle(night ? Color(white: 0.48) : WorkColor.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                } else {
                    ForEach(names, id: \.0) { itemID, name in
                        WorkMenuRow(title: name, selected: selection.wrappedValue == itemID) {
                            selection.wrappedValue = itemID
                            openMenu = nil
                        }
                    }
                }
            }
        }
    }

    private var title: String {
        switch model.draft?.purpose {
        case .add: "添加事项"
        case .edit: "编辑事项"
        default: "事项"
        }
    }

    private var viewBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("日期").font(.system(size: 12)).foregroundStyle(WorkColor.secondary)
                Text(WorkCalendar.chineseYearMonthDay(model.draft?.date ?? "")).font(.system(size: 14))
                Text(WorkCalendar.weekdayName(of: model.draft?.date ?? "")).font(.system(size: 14))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TypeResultTags(names: [
                name(model.draft?.typeId ?? "", child: false),
                name(model.draft?.subTypeId ?? "", child: true)
            ])
            labeled("描述", model.draft?.description ?? "")
            noteLabel(model.draft?.note ?? "")
        }
    }

    private var formBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkField(title: "日期") {
                Button {
                    draftPickerMonth = WorkCalendar.monthKey(fromDay: editing?.date ?? model.selectedDay)
                    openMenu = openMenu == "date" ? nil : "date"
                } label: {
                    HStack {
                        Text(editing?.date ?? model.selectedDay)
                            .foregroundStyle(night ? Color.white : WorkColor.ink)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(night ? Color(white: 0.62) : WorkColor.secondary)
                            .rotationEffect(.degrees(openMenu == "date" ? 180 : 0))
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(fieldFill, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(openMenu == "date" ? WorkColor.blue.opacity(0.45) : fieldLine)
                    )
                }
                .buttonStyle(.plain)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: PopupKey.self, value: ["date": geo.frame(in: .named("drawerForm"))])
                    }
                }
            }
            WorkField(title: "描述") {
                HStack(spacing: 2) {
                    TextField("做了什么", text: descriptionBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(night ? Color.white : WorkColor.ink)
                        .focused($descriptionFocused)
                        .onSubmit { model.saveDraft(place) }
                    if editing?.description.isEmpty == false {
                        ClearMark { descriptionBinding.wrappedValue = "" }
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, editing?.description.isEmpty == false ? 6 : 8)
                .frame(height: 28)
                .background(fieldFill, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(fieldLine))
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: PopupKey.self, value: ["suggest": geo.frame(in: .named("drawerForm"))])
                    }
                }
            }
            flatTypes
            WorkField(title: "备注") {
                NoteEditor(text: noteBinding, placeholder: "选填", focused: formField == .note) {
                    if onActionButton, Self.isClick == false { return }
                    formField = .note
                }
                    .frame(height: 88)
                    .background(fieldFill, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(fieldLine))
            }
            HStack {
                Spacer()
                Button("重置") { model.resetDraft(place) }
                    .buttonStyle(WorkButtonStyle(focused: formField == .reset))
                Button("取消") { model.cancelDraft(place) }
                    .buttonStyle(WorkButtonStyle(focused: formField == .cancel))
                Button(editing?.purpose == .add ? "添加" : "保存") { model.saveDraft(place) }
                    .buttonStyle(WorkButtonStyle(prominent: true, focused: formField == .submit))
            }
        }
        .onAppear { focusDescription() }
        .onChange(of: editing?.purpose) { _, purpose in
            guard purpose == .add || purpose == .edit else { return }
            focusDescription()
        }
        .onChange(of: model.descriptionFocusRequest) { _, _ in
            guard place == .main else { return }
            focusDescription()
        }
        .onChange(of: model.quickDescriptionFocusRequest) { _, _ in
            guard place == .quick else { return }
            focusDescription()
        }
        .onChange(of: editing?.description) { _, text in
            reloadSuggestions(text ?? "")
        }
        .onChange(of: descriptionFocused) { _, focused in
            guard focused else { return }
            if onActionButton, Self.isClick == false {
                descriptionFocused = false
                return
            }
            formField = .description
        }
        .onChange(of: formField) { _, field in
            if field != .description { suggestions = [] }
            let wantsDescription = field == .description
            if descriptionFocused != wantsDescription { descriptionFocused = wantsDescription }
        }
        .background(formKeys)
    }

    private func focusDescription() {
        formField = .description
        scheduleDescriptionFocus(attempt: 0)
    }

    /// The empty-description alert is still closing on the first turn, so the caret is placed again until it sticks.
    private func scheduleDescriptionFocus(attempt: Int) {
        DispatchQueue.main.async {
            guard formField == .description else { return }
            NSApp.windows.first { $0.identifier?.rawValue == formWindowID }?.makeKey()
            descriptionFocused = true
            guard attempt < 4 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard formField == .description else { return }
                descriptionFocused = true
                scheduleDescriptionFocus(attempt: attempt + 1)
            }
        }
    }

    private static var isClick: Bool {
        let type = NSApp.currentEvent?.type
        return type == .leftMouseDown || type == .leftMouseUp
    }

    private var onActionButton: Bool {
        formField == .reset || formField == .cancel || formField == .submit
    }

    private func closeSuggestions() {
        suggestions = []
        suggestionIndex = 0
        holdSuggestions = false
    }

    private func reloadSuggestions(_ text: String) {
        if holdSuggestions {
            closeSuggestions()
            return
        }
        guard formField == .description else {
            suggestions = []
            return
        }
        let next = model.descriptionSuggestions(matching: text, place: place)
        suggestions = next
        if suggestions.indices.contains(suggestionIndex) == false { suggestionIndex = 0 }
    }

    private func moveSuggestion(_ delta: Int) {
        let next = suggestionIndex + delta
        guard suggestions.indices.contains(next) else { return }
        suggestionIndex = next
    }

    private func useHighlightedSuggestion() {
        guard suggestions.indices.contains(suggestionIndex) else { return }
        applySuggestion(suggestions[suggestionIndex])
    }

    private func applySuggestion(_ item: DescriptionSuggestion) {
        let same = editing?.description == item.description
        suggestions = []
        suggestionIndex = 0
        if same == false { holdSuggestions = true }
        model.updateDraft(place) {
            $0.description = item.description
            $0.typeId = item.typeId
            $0.subTypeId = item.subTypeId
        }
    }

    private var formKeys: FormKeyCatcher {
        FormKeyCatcher(
            isForm: true,
            field: formField,
            level1IDs: model.types.sorted { $0.order < $1.order }.map(\.id),
            level2IDs: children.filter { $0.name.isEmpty == false }.map(\.id),
            selected1: editing?.typeId ?? "",
            selected2: editing?.subTypeId ?? "",
            onFocus: { formField = $0 },
            onSelect1: { typeBinding.wrappedValue = $0 },
            onSelect2: { subTypeBinding.wrappedValue = $0 },
            suggestionCount: formField == .description ? suggestions.count : 0,
            onMoveSuggestion: moveSuggestion,
            onUseSuggestion: useHighlightedSuggestion,
            onCloseSuggestions: closeSuggestions,
            onSubmit: { model.saveDraft(place) },
            onReset: { model.resetDraft(place) },
            onCancel: { model.cancelDraft(place) },
            onEscape: {
                if openMenu != nil {
                    openMenu = nil
                } else {
                    model.cancelDraft(place)
                }
            },
            windowID: formWindowID
        )
    }

    private var flatTypes: some View {
        let roots = model.types.sorted { $0.order < $1.order }
        let subs = children.filter { $0.name.isEmpty == false }
        return VStack(alignment: .leading, spacing: 10) {
            typeGroup("一级类型") {
                if roots.isEmpty {
                    Text("还没有类型")
                        .font(.system(size: 12))
                        .foregroundStyle(night ? Color(white: 0.48) : WorkColor.tertiary)
                } else {
                    ChipWrap(spacing: 6) {
                        ForEach(roots) { type in
                            let chosen = editing?.typeId == type.id
                            TypeChip(title: type.name, selected: chosen, emphasized: formField == .level1 && chosen) {
                                formField = .level1
                                typeBinding.wrappedValue = chosen ? "" : type.id
                            }
                        }
                    }
                }
            }
            typeGroup("二级类型") {
                if editing?.typeId.isEmpty != false {
                    Text("先选择一级类型")
                        .font(.system(size: 12))
                        .foregroundStyle(night ? Color(white: 0.48) : WorkColor.tertiary)
                } else if subs.isEmpty {
                    Text("没有二级类型")
                        .font(.system(size: 12))
                        .foregroundStyle(night ? Color(white: 0.48) : WorkColor.tertiary)
                } else {
                    ChipWrap(spacing: 6) {
                        ForEach(subs) { sub in
                            let chosen = editing?.subTypeId == sub.id
                            TypeChip(title: sub.name, selected: chosen, emphasized: formField == .level2 && chosen) {
                                formField = .level2
                                subTypeBinding.wrappedValue = chosen ? "" : sub.id
                            }
                        }
                    }
                }
            }
        }
    }

    private func typeGroup(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(night ? Color(white: 0.48) : WorkColor.tertiary)
            content()
        }
    }

    private var children: [SubType] {
        model.types.first(where: { $0.id == editing?.typeId })?.children.sorted { $0.order < $1.order } ?? []
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12)).foregroundStyle(WorkColor.secondary)
            Text(value.isEmpty ? "—" : value).font(.system(size: 14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func noteLabel(_ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("备注").font(.system(size: 12)).foregroundStyle(WorkColor.secondary)
            if value.isEmpty {
                EmptyMark()
            } else {
                Text(value).font(.system(size: 14))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func name(_ id: String, child: Bool) -> String {
        guard let draft = model.draft else { return "" }
        if child {
            return TypeNames.childName(typeID: draft.typeId, subTypeID: id, types: model.types)
        }
        return TypeNames.parentName(typeID: id, types: model.types)
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { editing?.description ?? "" },
            set: { value in model.updateDraft(place) { $0.description = value } }
        )
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { editing?.note ?? "" },
            set: { value in model.updateDraft(place) { $0.note = value } }
        )
    }

    private var typeBinding: Binding<String> {
        Binding(
            get: { editing?.typeId ?? "" },
            set: { value in model.updateDraft(place) { $0.typeId = value } }
        )
    }

    private var subTypeBinding: Binding<String> {
        Binding(
            get: { editing?.subTypeId ?? "" },
            set: { value in model.updateDraft(place) { $0.subTypeId = value } }
        )
    }

}
