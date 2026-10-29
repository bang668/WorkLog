import AppKit
import ServiceManagement
import SwiftUI

struct TypeDragLayout {
    static func landingIndex(origin: Int, midYs: [CGFloat], y: CGFloat) -> Int {
        var target = 0
        for (index, midY) in midYs.enumerated() where index != origin {
            if y > midY { target += 1 }
        }
        return target
    }

    /// Wrapped tags. A slot counts as passed when the pointer is below its row, or on its row and past its center.
    static func tagLandingIndex(origin: Int, slots: [CGRect], point: CGPoint) -> Int {
        var target = 0
        for (index, slot) in slots.enumerated() where index != origin {
            let sameRow = point.y >= slot.minY - 4 && point.y <= slot.maxY + 4
            let passed = sameRow ? point.x > slot.midX : point.y > slot.midY
            if passed { target += 1 }
        }
        return min(max(target, 0), max(slots.count - 1, 0))
    }

    static func shift(index: Int, origin: Int, destination: Int, distance: CGFloat) -> CGFloat {
        if destination > origin, index > origin, index <= destination { return -distance }
        if destination < origin, index >= destination, index < origin { return distance }
        return 0
    }

    static func holeMinY(origin: Int, destination: Int, slots: [CGRect], spacing: CGFloat) -> CGFloat {
        let height = slots[origin].height
        let distance = height + spacing
        if destination == origin { return slots[origin].minY }
        if destination > origin {
            return slots[destination].maxY - distance + spacing
        }
        return slots[destination].minY + distance - spacing - height
    }

    /// Where each original tag should slide while a drag is in progress. Index `origin` is included.
    static func tagOffsets(origin: Int, destination: Int, slots: [CGRect], width: CGFloat, spacing: CGFloat) -> [CGSize] {
        guard slots.isEmpty == false, slots.indices.contains(origin), slots.indices.contains(destination) else {
            return Array(repeating: .zero, count: slots.count)
        }
        var order = Array(slots.indices)
        if origin != destination {
            let item = order.remove(at: origin)
            order.insert(item, at: min(max(destination, 0), order.count))
        }
        let sizes = order.map { CGSize(width: slots[$0].width, height: slots[$0].height) }
        let packed = pack(sizes: sizes, origin: CGPoint(x: slots[0].minX, y: slots[0].minY), width: width, spacing: spacing)
        var offsets = Array(repeating: CGSize.zero, count: slots.count)
        for (visual, original) in order.enumerated() {
            let target = packed[visual]
            let from = slots[original]
            offsets[original] = CGSize(width: target.minX - from.minX, height: target.minY - from.minY)
        }
        return offsets
    }

    static func pack(sizes: [CGSize], origin: CGPoint, width: CGFloat, spacing: CGFloat) -> [CGRect] {
        var x = origin.x
        var y = origin.y
        var rowHeight: CGFloat = 0
        var rects: [CGRect] = []
        let maxX = origin.x + max(width, 1)
        for size in sizes {
            if x > origin.x, x + size.width > maxX + 0.5 {
                y += rowHeight + spacing
                x = origin.x
                rowHeight = 0
            }
            rects.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return rects
    }
}

private struct TypeFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""
    @State private var drafts: [String: String] = [:]
    @State private var revertToken: [String: Int] = [:]
    @State private var frames: [String: CGRect] = [:]
    @State private var drag: TypeDrag?
    @State private var dragTranslation: CGSize = .zero
    @State private var toast: String?
    @State private var toastNonce = 0
    @State private var tab = 0
    @State private var launchOn = false
    @State private var launchNeedsApproval = false
    @State private var subtypeDialog: SubtypeDialogRequest?
    @State private var subtypeHover = SubtypeHover()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                WorkSegmented(titles: ["通用", "事项类型", "关于"], selection: $tab)
                Spacer()
            }
            .padding(.top, 16)
            .padding(.bottom, 4)
            Group {
                switch tab {
                case 0: generalPage
                case 1: typesPage
                default: aboutPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 520, height: 560)
        .overlay {
            if let subtypeDialog {
                SubtypeNameDialog(
                    title: subtypeDialog.childID == nil ? "添加二级类型" : "修改二级类型",
                    initialName: subtypeDialog.name,
                    onCancel: { self.subtypeDialog = nil },
                    onConfirm: { confirmSubtype($0) }
                )
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(WorkColor.ink.opacity(0.92), in: Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: toast)
        .background(WorkColor.card)
        .background(WindowReader { subtypeHover.window = $0 })
        .onAppear {
            refreshLaunch()
            subtypeHover.open = { subtypeDialog = $0 }
            subtypeHover.start()
        }
        .onChange(of: tab) { _, newValue in
            subtypeDialog = nil
            guard newValue != 1 else { return }
            drag = nil
            flushTypeDrafts()
        }
        .onDisappear {
            subtypeHover.stop()
            flushTypeDrafts()
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("编辑方式")
                    .font(.system(size: 13, weight: .semibold))
                Text("记在这台 Mac 上。")
                    .font(.system(size: 13))
                    .foregroundStyle(WorkColor.secondary)
                HStack(spacing: 8) {
                    ForEach(EditorKind.allCases) { kind in
                        choice(kind)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("开机启动")
                    .font(.system(size: 13, weight: .semibold))
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("登录后自动打开")
                            .font(.system(size: 13))
                        Text(launchNeedsApproval ? "还需要在系统设置里允许。" : "登录这台 Mac 后，自动打开 WorkLog。")
                            .font(.system(size: 12))
                            .foregroundStyle(WorkColor.secondary)
                    }
                    Spacer(minLength: 8)
                    Toggle("开机启动", isOn: launchBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(WorkColor.blue)
                }
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(WorkColor.line))
            }
            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private var typesPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("新的一级类型", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.867, green: 0.839, blue: 0.796)))
                    .onSubmit { addRoot() }
                Button("添加") { addRoot() }
                    .buttonStyle(WorkButtonStyle())
                    .disabled(model.hasLibrary == false)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("一级类型拖动前面的图标排序。二级类型是标签，拖动标签排序，点后面的加号添加，双击标签修改，点叉删除。")
                        .font(.system(size: 13))
                        .foregroundStyle(WorkColor.secondary)
                    if model.hasLibrary == false {
                        Text("先打开一个日志文件夹，再管理类型。")
                            .foregroundStyle(WorkColor.secondary)
                    } else if model.types.isEmpty {
                        Text("还没有类型。事项可以不选类型。")
                            .foregroundStyle(WorkColor.secondary)
                    }
                    let roots = model.types.sorted { $0.order < $1.order }
                    ForEach(Array(roots.enumerated()), id: \.element.id) { index, type in
                        typeCard(type, index: index)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .coordinateSpace(name: "settings")
                .onPreferenceChange(TypeFrameKey.self) { value in
                    if drag == nil { frames = value }
                }
                .overlay {
                    if let drag {
                        dragLayer(drag)
                    }
                }
            }
        }
    }

    private var aboutPage: some View {
        VStack(spacing: 6) {
            Text("WorkLog")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WorkColor.ink)
            Text("版本 \(appVersion)")
                .font(.system(size: 13))
                .foregroundStyle(WorkColor.secondary)
            Text("记在这台 Mac 上的工作日志。")
                .font(.system(size: 13))
                .foregroundStyle(WorkColor.secondary)
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.2"
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchOn },
            set: { setLaunch($0) }
        )
    }

    private func refreshLaunch() {
        let status = SMAppService.mainApp.status
        launchOn = status == .enabled || status == .requiresApproval
        launchNeedsApproval = status == .requiresApproval
    }

    private func setLaunch(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showToast("开机启动没有改成。")
        }
        refreshLaunch()
    }

    private func choice(_ kind: EditorKind) -> some View {
        let on = model.editorKind == kind
        return Button {
            model.editorKind = kind
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: on ? "circle.inset.filled" : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(on ? WorkColor.blue : WorkColor.tertiary)
                    Text(kind.title)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(kind.caption)
                    .font(.system(size: 12))
                    .foregroundStyle(WorkColor.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(on ? Color(red: 0.957, green: 0.976, blue: 1) : Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(on ? WorkColor.blue : WorkColor.line, lineWidth: on ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func typeCard(_ type: WorkType, index: Int, ghost: Bool = false) -> some View {
        let children = type.children
            .filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .sorted { $0.order < $1.order }
        let folding = drag != nil && drag?.parentID == nil
        let hidden = !ghost && folding && drag?.id == type.id
        return VStack(alignment: .leading, spacing: 8) {
            typeRow(id: type.id, parentID: nil, name: type.name, index: index, ghost: ghost)
            if folding == false {
                VStack(alignment: .leading, spacing: 8) {
                    ChipWrap(spacing: 6) {
                        ForEach(Array(children.enumerated()), id: \.element.id) { childIndex, child in
                            subtypeTag(id: child.id, parentID: type.id, name: child.name, index: childIndex, ghost: ghost)
                                    .opacity(!ghost && drag?.parentID == type.id && drag?.id == child.id ? 0 : 1)
                                    .offset(tagShift(parentID: type.id, index: childIndex))
                        }
                        if ghost == false {
                            Button {
                                discardEmptyChildren(of: type.id)
                                subtypeDialog = SubtypeDialogRequest(parentID: type.id, childID: nil, name: "")
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(WorkColor.secondary)
                                    .frame(width: 22, height: 22)
                                    .background(Color.white, in: Circle())
                                    .overlay(Circle().stroke(Color(red: 0.867, green: 0.839, blue: 0.796)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("添加二级类型")
                        }
                    }
                    .background { if !ghost { frameReader("tags:\(type.id)") } }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(red: 0.894, green: 0.875, blue: 0.839)).frame(width: 2)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WorkColor.line))
        .background { if !ghost { frameReader("card:\(type.id)") } }
        .opacity(hidden ? 0 : 1)
        .offset(y: ghost ? 0 : rootShift(index))
    }

    private func typeRow(id: String, parentID: String?, name: String, index: Int, prompt: String = "名称", ghost: Bool = false) -> some View {
        HStack(spacing: 4) {
            dragHandle(id: id, parentID: parentID, index: index, ghost: ghost)
            TypeNameField(
                name: name,
                prompt: prompt,
                revertToken: revertToken[id] ?? 0,
                onDraft: { drafts[id] = $0 },
                onFinish: { applyName(id: id, parentID: parentID, stored: name, typed: $0) }
            )
            .frame(maxWidth: .infinity)
            iconButton("chevron.up") { model.moveType(id: id, parentID: parentID, direction: -1) }
            iconButton("chevron.down") { model.moveType(id: id, parentID: parentID, direction: 1) }
            iconButton("trash") { model.deleteType(id: id, parentID: parentID) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if !ghost {
                frameReader(parentID == nil ? "title:\(id)" : "row:\(id)")
            }
        }
    }

    private func dragHandle(id: String, parentID: String?, index: Int, ghost: Bool) -> some View {
        let icon = Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WorkColor.tertiary)
            .frame(width: 22, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel("拖动调整顺序")
        return Group {
            if ghost {
                icon
            } else {
                icon
                    .onHover { inside in
                        if inside { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
                    }
                    .highPriorityGesture(reorderGesture(id: id, parentID: parentID, index: index))
            }
        }
    }

    private func reorderGesture(id: String, parentID: String?, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("settings"))
            .onChanged { value in
                subtypeHover.dragging = true
                NSCursor.closedHand.set()
                if drag == nil {
                    guard var session = beginDrag(id: id, parentID: parentID, index: index) else { return }
                    session.destinationIndex = session.originIndex
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        drag = session
                    }
                }
                guard drag?.id == id, let session = drag else { return }
                dragTranslation = value.translation
                let dest = landingIndex(of: session, point: value.location)
                if session.destinationIndex != dest {
                    withAnimation(.easeOut(duration: 0.16)) {
                        drag?.destinationIndex = dest
                    }
                }
            }
            .onEnded { value in
                subtypeHover.dragging = false
                NSCursor.arrow.set()
                guard let session = drag, session.id == id else {
                    drag = nil
                    dragTranslation = .zero
                    return
                }
                let dest = landingIndex(of: session, point: value.location)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    drag = nil
                    dragTranslation = .zero
                    if dest != session.originIndex {
                        model.moveType(id: session.id, parentID: session.parentID, to: dest)
                    }
                }
            }
    }

    private func dragLayer(_ drag: TypeDrag) -> some View {
        let hole = holeRect(for: drag)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: drag.parentID == nil ? 12 : 8, style: .continuous)
                .fill(WorkColor.blueSoft.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: drag.parentID == nil ? 12 : 8, style: .continuous)
                        .stroke(WorkColor.blue.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                )
                .frame(width: hole.width, height: hole.height)
                .offset(x: hole.minX, y: hole.minY)
                .animation(.easeOut(duration: 0.16), value: drag.destinationIndex)
            dragPreview(drag)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func dragPreview(_ drag: TypeDrag) -> some View {
        Group {
            if drag.parentID == nil, let type = model.types.first(where: { $0.id == drag.id }) {
                let index = model.types.sorted { $0.order < $1.order }.firstIndex(where: { $0.id == type.id }) ?? drag.originIndex
                typeCard(type, index: index, ghost: true)
            } else if let parentID = drag.parentID,
                      let parent = model.types.first(where: { $0.id == parentID }),
                      let child = parent.children.first(where: { $0.id == drag.id }) {
                let index = parent.children.sorted { $0.order < $1.order }.firstIndex(where: { $0.id == child.id }) ?? drag.originIndex
                subtypeTag(id: child.id, parentID: parentID, name: child.name, index: index, ghost: true)
            }
        }
        .frame(width: drag.start.width, height: drag.start.height, alignment: .topLeading)
        .offset(x: drag.lift.minX + dragTranslation.width, y: drag.lift.minY + dragTranslation.height)
        .compositingGroup()
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        .animation(nil, value: dragTranslation)
    }

    private func frameReader(_ key: String) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: TypeFrameKey.self, value: [key: geo.frame(in: .named("settings"))])
        }
    }

    private func beginDrag(id: String, parentID: String?, index: Int) -> TypeDrag? {
        if parentID == nil {
            return beginRootDrag(id: id, index: index)
        }
        guard let parentID else { return nil }
        guard let start = frames["row:\(id)"] else { return nil }
        let ids = model.types.first(where: { $0.id == parentID })?.children
            .filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .sorted { $0.order < $1.order }
            .map(\.id) ?? []
        let slots = ids.compactMap { frames["row:\($0)"] }
        guard slots.count == ids.count, slots.indices.contains(index) else { return nil }
        let inferred = slots.count >= 2 ? slots[1].minY - slots[0].maxY : 6
        let contentSpan = (slots.map(\.maxX).max() ?? 0) - (slots.map(\.minX).min() ?? 0)
        let wrapWidth = frames["tags:\(parentID)"]?.width ?? contentSpan
        return TypeDrag(
            id: id,
            parentID: parentID,
            originIndex: index,
            destinationIndex: index,
            start: start,
            lift: start,
            slots: slots,
            spacing: 6,
            wrapWidth: wrapWidth > 1 ? wrapWidth : (inferred > 0 ? inferred : 6)
        )
    }

    private func beginRootDrag(id: String, index: Int) -> TypeDrag? {
        let ids = model.types.sorted { $0.order < $1.order }.map(\.id)
        let cards = ids.compactMap { frames["card:\($0)"] }
        guard cards.count == ids.count, cards.indices.contains(index) else { return nil }
        let inferred = cards.count >= 2 ? cards[1].minY - cards[0].maxY : 12
        let spacing = inferred > 0 ? inferred : 12
        var y = cards[0].minY
        var slots: [CGRect] = []
        for (offset, card) in cards.enumerated() {
            let titleHeight = frames["title:\(ids[offset])"]?.height ?? 28
            let height = min(card.height, titleHeight + 16)
            slots.append(CGRect(x: card.minX, y: y, width: card.width, height: height))
            y += height + spacing
        }
        let grabbed = cards[index]
        let row = slots[index]
        return TypeDrag(
            id: id,
            parentID: nil,
            originIndex: index,
            destinationIndex: index,
            start: row,
            lift: CGRect(x: grabbed.minX, y: grabbed.minY, width: row.width, height: row.height),
            slots: slots,
            spacing: spacing,
            wrapWidth: 0
        )
    }

    private func landingIndex(of drag: TypeDrag, point: CGPoint) -> Int {
        if drag.parentID != nil {
            return TypeDragLayout.tagLandingIndex(origin: drag.originIndex, slots: drag.slots, point: point)
        }
        return TypeDragLayout.landingIndex(
            origin: drag.originIndex,
            midYs: drag.slots.map(\.midY),
            y: point.y
        )
    }

    private func holeRect(for drag: TypeDrag) -> CGRect {
        if drag.parentID != nil, drag.slots.indices.contains(drag.originIndex) {
            let shift = TypeDragLayout.tagOffsets(
                origin: drag.originIndex,
                destination: drag.destinationIndex,
                slots: drag.slots,
                width: drag.wrapWidth,
                spacing: drag.spacing
            )[drag.originIndex]
            let slot = drag.slots[drag.originIndex]
            return CGRect(x: slot.minX + shift.width, y: slot.minY + shift.height, width: slot.width, height: slot.height)
        }
        return CGRect(
            x: drag.start.minX,
            y: TypeDragLayout.holeMinY(
                origin: drag.originIndex,
                destination: drag.destinationIndex,
                slots: drag.slots,
                spacing: drag.spacing
            ),
            width: drag.start.width,
            height: drag.start.height
        )
    }

    private func tagShift(parentID: String, index: Int) -> CGSize {
        guard let drag, drag.parentID == parentID, index != drag.originIndex else { return .zero }
        let offsets = TypeDragLayout.tagOffsets(
            origin: drag.originIndex,
            destination: drag.destinationIndex,
            slots: drag.slots,
            width: drag.wrapWidth,
            spacing: drag.spacing
        )
        guard offsets.indices.contains(index) else { return .zero }
        return offsets[index]
    }

    private func rootShift(_ index: Int) -> CGFloat {
        guard let drag, drag.parentID == nil else { return 0 }
        return TypeDragLayout.shift(
            index: index,
            origin: drag.originIndex,
            destination: drag.destinationIndex,
            distance: drag.start.height + drag.spacing
        )
    }

    private func subtypeTag(id: String, parentID: String, name: String, index: Int, ghost: Bool) -> some View {
        let chip = HStack(spacing: 2) {
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(WorkColor.ink)
                .lineLimit(1)
                .padding(.leading, 8)
                .padding(.trailing, 2)
                .frame(height: 22)
                .contentShape(Rectangle())
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(WorkColor.secondary)
                .frame(width: 14, height: 14)
                .padding(.trailing, 4)
        }
        .frame(height: 22)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Color(red: 0.867, green: 0.839, blue: 0.796)))
        return Group {
            if ghost {
                chip
            } else {
                HStack(spacing: 2) {
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundStyle(WorkColor.ink)
                        .lineLimit(1)
                        .padding(.leading, 8)
                        .padding(.trailing, 2)
                        .frame(height: 22)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside {
                                NSCursor.openHand.set()
                                subtypeHover.request = SubtypeDialogRequest(parentID: parentID, childID: id, name: name)
                            } else {
                                NSCursor.arrow.set()
                                if subtypeHover.request?.childID == id { subtypeHover.request = nil }
                            }
                        }
                        .highPriorityGesture(reorderGesture(id: id, parentID: parentID, index: index))
                        .accessibilityLabel("拖动调整顺序，双击修改")
                    Button {
                        model.deleteType(id: id, parentID: parentID)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(WorkColor.secondary)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                    .accessibilityLabel("删除\(name)")
                }
                .frame(height: 22)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().stroke(Color(red: 0.867, green: 0.839, blue: 0.796)))
                .background { frameReader("row:\(id)") }
            }
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WorkColor.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private func addRoot() {
        if let error = model.addType(parentID: nil, name: newName) {
            showToast(error)
        } else {
            newName = ""
        }
    }

    private func discardEmptyChildren(of parentID: String) {
        guard let type = model.types.first(where: { $0.id == parentID }) else { return }
        for child in type.children where child.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.discardUnnamedChild(id: child.id, parentID: parentID)
            drafts[child.id] = nil
        }
    }

    private func confirmSubtype(_ typed: String) {
        guard let request = subtypeDialog else { return }
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            showToast("名称不能为空。")
            return
        }
        if let childID = request.childID {
            if trimmed == request.name {
                subtypeDialog = nil
                return
            }
            if let error = model.renameType(id: childID, parentID: request.parentID, name: trimmed) {
                showToast(error)
                return
            }
        } else if let error = model.addType(parentID: request.parentID, name: trimmed) {
            showToast(error)
            return
        }
        subtypeDialog = nil
    }

    private func commitDrafts(of type: WorkType) {
        let current = model.types.first(where: { $0.id == type.id }) ?? type
        for child in current.children where child.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let typed = drafts[child.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if typed.isEmpty {
                model.discardUnnamedChild(id: child.id, parentID: current.id)
                drafts[child.id] = nil
            }
        }
        let fresh = model.types.first(where: { $0.id == type.id }) ?? current
        let rows: [(String, String?, String)] = [(fresh.id, nil, fresh.name)] + fresh.children.map { ($0.id, fresh.id, $0.name) }
        for (id, parentID, stored) in rows {
            guard let typed = drafts[id] else { continue }
            _ = applyName(id: id, parentID: parentID, stored: stored, typed: typed)
        }
    }

    private func flushTypeDrafts() {
        for type in model.types {
            commitDrafts(of: type)
        }
    }

    @discardableResult
    private func applyName(id: String, parentID: String?, stored: String, typed: String) -> Bool {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedTrimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parentID, storedTrimmed.isEmpty, trimmed.isEmpty {
            model.discardUnnamedChild(id: id, parentID: parentID)
            drafts[id] = nil
            return false
        }
        if trimmed.isEmpty {
            showToast("名称不能为空。")
            drafts[id] = nil
            revertToken[id, default: 0] += 1
            return true
        }
        guard trimmed != storedTrimmed else {
            drafts[id] = nil
            return false
        }
        if let error = model.renameType(id: id, parentID: parentID, name: trimmed) {
            showToast(error)
            return false
        }
        drafts[id] = nil
        return false
    }

    private func showToast(_ message: String) {
        toastNonce += 1
        let nonce = toastNonce
        toast = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard toastNonce == nonce else { return }
            toast = nil
        }
    }
}

private struct TypeDrag {
    var id: String
    var parentID: String?
    var originIndex: Int
    var destinationIndex: Int
    var start: CGRect
    var lift: CGRect
    var slots: [CGRect]
    var spacing: CGFloat
    var wrapWidth: CGFloat
}

private struct TypeNameField: View {
    let name: String
    var prompt = "名称"
    var revertToken: Int
    let onDraft: (String) -> Void
    let onFinish: (String) -> Bool
    @State private var text: String
    @FocusState private var focused: Bool

    init(name: String, prompt: String = "名称", revertToken: Int = 0, onDraft: @escaping (String) -> Void, onFinish: @escaping (String) -> Bool) {
        self.name = name
        self.prompt = prompt
        self.revertToken = revertToken
        self.onDraft = onDraft
        self.onFinish = onFinish
        _text = State(initialValue: name)
    }

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundStyle(WorkColor.tertiary))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($focused)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.867, green: 0.839, blue: 0.796)))
            .onSubmit { if onFinish(text) { text = name } }
            .onChange(of: text) { _, newValue in onDraft(newValue) }
            .onChange(of: name) { _, newValue in
                text = newValue
                onDraft(newValue)
            }
            .onChange(of: focused) { _, isFocused in
                guard isFocused == false else { return }
                if onFinish(text) { text = name }
            }
            .onChange(of: revertToken) { _, _ in
                text = name
            }
            .onAppear {
                if name.isEmpty { focused = true }
            }
    }
}

private struct SubtypeDialogRequest {
    var parentID: String
    var childID: String?
    var name: String
}

/// Double-click on a tag opens the editor. The drag gesture keeps the mouse, so this watches the click instead.
private final class SubtypeHover {
    var request: SubtypeDialogRequest?
    var dragging = false
    weak var window: NSWindow?
    var open: ((SubtypeDialogRequest) -> Void)?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let self,
                  event.clickCount == 2,
                  event.window === self.window,
                  self.dragging == false,
                  let request = self.request else { return event }
            let open = self.open
            DispatchQueue.main.async { open?(request) }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}

private struct SubtypeNameDialog: View {
    let title: String
    let initialName: String
    let onCancel: () -> Void
    let onConfirm: (String) -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(title: String, initialName: String, onCancel: @escaping () -> Void, onConfirm: @escaping (String) -> Void) {
        self.title = title
        self.initialName = initialName
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _text = State(initialValue: initialName)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WorkColor.ink)
                TextField("", text: $text, prompt: Text("请输入二级类型名称").foregroundStyle(WorkColor.tertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.867, green: 0.839, blue: 0.796)))
                    .onSubmit { onConfirm(text) }
                HStack(spacing: 8) {
                    Spacer()
                    Button("取消", action: onCancel)
                        .buttonStyle(WorkButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("确定") { onConfirm(text) }
                        .buttonStyle(WorkButtonStyle(prominent: true))
                }
            }
            .padding(16)
            .frame(width: 300)
            .background(WorkColor.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WorkColor.line))
            .contentShape(Rectangle())
            .onTapGesture {}
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        }
        .onAppear {
            focused = true
            guard initialName.isEmpty == false else { return }
            DispatchQueue.main.async {
                (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
            }
        }
    }
}
