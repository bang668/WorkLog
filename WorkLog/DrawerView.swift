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

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NoteTextView else { return }
        textView.placeholder = placeholder
        guard textView.hasMarkedText() == false, textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor

        init(_ parent: NoteEditor) { self.parent = parent }

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
            .foregroundColor: FieldMetrics.placeholderColor
        ])
    }

    private func lockMetrics() {
        let font = FieldMetrics.font
        let inset = NSSize(width: FieldMetrics.inset, height: FieldMetrics.inset)
        if self.font?.pointSize != FieldMetrics.fontSize { self.font = font }
        if (typingAttributes[.font] as? NSFont)?.pointSize != FieldMetrics.fontSize {
            typingAttributes[.font] = font
        }
        if textContainerInset != inset { textContainerInset = inset }
        if textContainer?.lineFragmentPadding != 0 { textContainer?.lineFragmentPadding = 0 }
    }
}

private struct TypeChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(selected ? WorkColor.ink : WorkColor.secondary)
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
        if selected { return WorkColor.blueSoft }
        if hovering { return Color.black.opacity(0.04) }
        return Color.white
    }

    private var line: Color {
        hovering ? Color(red: 0.78, green: 0.75, blue: 0.70) : Color(red: 0.867, green: 0.839, blue: 0.796)
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

struct DrawerOverlay: View {
    @Environment(AppModel.self) private var model
    @State private var openMenu: String?
    @State private var menuFrames: [String: CGRect] = [:]
    @State private var draftPickerMonth = ""

    var body: some View {
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
        .allowsHitTesting(model.draft != nil)
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
                        DayPicker(month: $draftPickerMonth, selectedDay: model.draft?.date ?? model.selectedDay) { day in
                            model.updateDraft { $0.date = day }
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

    private func menuCard(id: String, width: CGFloat) -> some View {
        let names = id == "type" ? model.types.map { ($0.id, $0.name) } : children.filter { $0.name.isEmpty == false }.map { ($0.id, $0.name) }
        let selection = id == "type" ? typeBinding : subTypeBinding
        return WorkMenuCard(width: width) {
            WorkMenuRows(maxHeight: 180) {
                if names.isEmpty {
                    Text("还没有类型")
                        .font(.system(size: 13))
                        .foregroundStyle(WorkColor.tertiary)
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
                    draftPickerMonth = WorkCalendar.monthKey(fromDay: model.draft?.date ?? model.selectedDay)
                    openMenu = openMenu == "date" ? nil : "date"
                } label: {
                    HStack {
                        Text(model.draft?.date ?? model.selectedDay)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(WorkColor.secondary)
                            .rotationEffect(.degrees(openMenu == "date" ? 180 : 0))
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(openMenu == "date" ? WorkColor.blue.opacity(0.45) : Color(red: 0.867, green: 0.839, blue: 0.796))
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
                TextField("做了什么", text: descriptionBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.867, green: 0.839, blue: 0.796)))
                    .onSubmit { model.saveDraft() }
            }
            flatTypes
            WorkField(title: "备注") {
                NoteEditor(text: noteBinding, placeholder: "选填")
                    .frame(height: 88)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.867, green: 0.839, blue: 0.796)))
            }
            HStack {
                Spacer()
                Button("取消") { model.cancelDraft() }
                    .buttonStyle(WorkButtonStyle())
                Button(model.draft?.purpose == .add ? "添加" : "保存") { model.saveDraft() }
                    .buttonStyle(WorkButtonStyle(prominent: true))
            }
        }
    }

    private var flatTypes: some View {
        let roots = model.types.sorted { $0.order < $1.order }
        let subs = children.filter { $0.name.isEmpty == false }
        return VStack(alignment: .leading, spacing: 10) {
            typeGroup("一级类型") {
                if roots.isEmpty {
                    Text("还没有类型")
                        .font(.system(size: 12))
                        .foregroundStyle(WorkColor.tertiary)
                } else {
                    ChipWrap(spacing: 6) {
                        ForEach(roots) { type in
                            TypeChip(title: type.name, selected: model.draft?.typeId == type.id) {
                                typeBinding.wrappedValue = model.draft?.typeId == type.id ? "" : type.id
                            }
                        }
                    }
                }
            }
            typeGroup("二级类型") {
                if model.draft?.typeId.isEmpty != false {
                    Text("先选择一级类型")
                        .font(.system(size: 12))
                        .foregroundStyle(WorkColor.tertiary)
                } else if subs.isEmpty {
                    Text("没有二级类型")
                        .font(.system(size: 12))
                        .foregroundStyle(WorkColor.tertiary)
                } else {
                    ChipWrap(spacing: 6) {
                        ForEach(subs) { sub in
                            TypeChip(title: sub.name, selected: model.draft?.subTypeId == sub.id) {
                                subTypeBinding.wrappedValue = model.draft?.subTypeId == sub.id ? "" : sub.id
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
                .foregroundStyle(WorkColor.tertiary)
            content()
        }
    }

    private var children: [SubType] {
        model.types.first(where: { $0.id == model.draft?.typeId })?.children.sorted { $0.order < $1.order } ?? []
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
            get: { model.draft?.description ?? "" },
            set: { value in model.updateDraft { $0.description = value } }
        )
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { model.draft?.note ?? "" },
            set: { value in model.updateDraft { $0.note = value } }
        )
    }

    private var typeBinding: Binding<String> {
        Binding(
            get: { model.draft?.typeId ?? "" },
            set: { value in model.updateDraft { $0.typeId = value } }
        )
    }

    private var subTypeBinding: Binding<String> {
        Binding(
            get: { model.draft?.subTypeId ?? "" },
            set: { value in model.updateDraft { $0.subTypeId = value } }
        )
    }

}
