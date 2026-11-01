import AppKit
import ApplicationServices
import Carbon
import SwiftUI

enum DoubleModifierKind: String, Equatable {
    case control
    case option
    case command

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .command: "⌘"
        }
    }

    var displayString: String { "双击 \(symbol)" }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .control: .control
        case .option: .option
        case .command: .command
        }
    }

    /// Left and right physical key codes.
    var keyCodes: Set<UInt16> {
        switch self {
        case .control: [59, 62]
        case .option: [58, 61]
        case .command: [55, 54]
        }
    }

    static func from(keyCode: UInt16) -> DoubleModifierKind? {
        allCases.first { $0.keyCodes.contains(keyCode) }
    }

    static func isModifierKey(_ code: UInt16) -> Bool {
        [54, 55, 56, 58, 59, 60, 61, 62].contains(code)
    }
}

extension DoubleModifierKind: CaseIterable {}

struct QuickHotKey: Equatable {
    var keyCode: UInt16
    var flags: NSEvent.ModifierFlags
    var doubleModifier: DoubleModifierKind?

    var carbonModifiers: UInt32 {
        var bits: UInt32 = 0
        if flags.contains(.command) { bits |= UInt32(cmdKey) }
        if flags.contains(.shift) { bits |= UInt32(shiftKey) }
        if flags.contains(.option) { bits |= UInt32(optionKey) }
        if flags.contains(.control) { bits |= UInt32(controlKey) }
        return bits
    }

    /// A bare letter would swallow typing everywhere, so the shortcut needs a real modifier.
    /// A clean double-tap of Control, Option, or Command is the other accepted form.
    var isRegisterable: Bool {
        if doubleModifier != nil { return true }
        return flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
    }

    var label: String {
        if let doubleModifier { return doubleModifier.displayString }
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        text += Self.keyName(keyCode)
        return text
    }

    static func keyName(_ code: UInt16) -> String {
        if let letter = letters[code] { return letter }
        if let symbol = symbols[code] { return symbol }
        return "键\(code)"
    }

    static func doubleTap(_ kind: DoubleModifierKind) -> QuickHotKey {
        QuickHotKey(keyCode: kind.keyCodes.min() ?? 0, flags: kind.flag, doubleModifier: kind)
    }

    private static let letters: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M"
    ]

    private static let symbols: [UInt16: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",",
        44: "/", 47: ".", 50: "`", 36: "↩", 48: "⇥", 49: "空格", 76: "⌅",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

/// Carbon hotkeys fire while another app is frontmost. A global event monitor cannot consume the key,
/// and it stays silent when WorkLog itself is active.
@MainActor
final class QuickHotKeyCenter {
    static let shared = QuickHotKeyCenter()
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var installed = false

    func install(_ hotKey: QuickHotKey?) -> Bool {
        prepare()
        unregister()
        DoubleTapHotKey.shared.stop()
        guard let hotKey else { return true }
        if let kind = hotKey.doubleModifier {
            DoubleTapHotKey.shared.start(kind)
            return true
        }
        guard hotKey.isRegisterable else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            hotKey.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        self.hotKey = ref
        return true
    }

    private func prepare() {
        guard installed == false else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), worklogHotKeyPressed, 1, &spec, nil, &handler)
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private static let signature = OSType(0x574C6F67)
}

private func worklogHotKeyPressed(
    _ handler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            QuickAddPanel.shared.summon()
        }
    }
    return noErr
}

@MainActor
final class QuickAddPanel {
    static let shared = QuickAddPanel()
    private var panels: [QuickPanel] = []
    private var cardPanel: QuickPanel?
    private var frames: [ObjectIdentifier: NSRect] = [:]
    private var closing = false
    private var closeTask: Task<Void, Never>?
    private var localClick: Any?
    private var globalClick: Any?
    private let presentGeneration = PresentTicket()
    /// Settings is application-modal. Opening it over this panel leaves both stuck.
    nonisolated(unsafe) private var showingQuickAdd = false
    nonisolated var isShowing: Bool { showingQuickAdd }

    func summon() {
        guard closing == false else { return }
        guard let model = AppRuntime.current?.model, model.hasLibrary else { return }
        if panels.isEmpty == false {
            present()
            return
        }
        let screens = NSScreen.screens
        guard screens.isEmpty == false else { return }
        model.beginQuickAdd()
        guard model.quickDraft != nil else { return }
        let target = Self.currentScreen() ?? screens[0]
        let cardIndex = screens.firstIndex { $0.frame.equalTo(target.frame) } ?? 0
        for (index, screen) in screens.enumerated() {
            let wantsCard = index == cardIndex
            let panel = makePanel(frame: screen.frame, keyable: wantsCard)
            panel.setFrame(screen.frame, display: false)
            if wantsCard {
                panel.identifier = NSUserInterfaceItemIdentifier("worklog.quick")
                let host = QuickHostingView(rootView: DrawerOverlay(place: .quick).environment(model))
                host.safeAreaRegions = []
                host.frame = NSRect(origin: .zero, size: screen.frame.size)
                host.autoresizingMask = [.width, .height]
                panel.contentView = host
                cardPanel = panel
            } else {
                panel.identifier = NSUserInterfaceItemIdentifier("worklog.quick.catch")
                let catcher = OutsideClickView(frame: NSRect(origin: .zero, size: screen.frame.size))
                catcher.autoresizingMask = [.width, .height]
                catcher.onClick = {
                    MainActor.assumeIsolated {
                        QuickAddPanel.shared.dismissFromOutsideClick()
                    }
                }
                panel.contentView = catcher
            }
            frames[ObjectIdentifier(panel)] = screen.frame
            panels.append(panel)
        }
        showingQuickAdd = true
        model.onQuickWillClose = { [weak self] in self?.beginClose() }
        startClickMonitors()
        present()
    }

    func beginClose() {
        guard panels.isEmpty == false, closing == false else { return }
        closing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.42
            for panel in panels where panel !== cardPanel {
                panel.animator().alphaValue = 0
            }
        }
        closeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(480))
            guard Task.isCancelled == false else { return }
            self.tearDown()
            AppRuntime.current?.model?.finishQuickClose()
        }
    }

    /// Showing the panel inside the hotkey's task makes SwiftUI handle the
    /// pointer while that task is still current, and its hover test crashes.
    private func present() {
        if let screen = Self.currentScreen(), let card = cardPanel {
            frames[ObjectIdentifier(card)] = screen.frame
        }
        presentGeneration.value += 1
        let ticket = presentGeneration.value
        let generation = presentGeneration
        let windows = panels
        let card = cardPanel
        let frameMap = frames
        DispatchQueue.main.async {
            guard generation.value == ticket else { return }
            Self.show(windows, card: card, frames: frameMap)
        }
    }

    private static func show(_ windows: [QuickPanel], card: QuickPanel?, frames: [ObjectIdentifier: NSRect]) {
        guard let card else { return }
        let mouseFrame = currentScreen()?.frame
        for panel in windows {
            panel.collectionBehavior = panelBehavior
            // isFloatingPanel resets the level to floating, which sits under
            // another app's fullscreen window. Set the level after it.
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            var frame = frames[ObjectIdentifier(panel)] ?? panel.frame
            if panel === card, let mouseFrame {
                frame = mouseFrame
            }
            panel.setFrame(frame, display: false)
            panel.orderFrontRegardless()
            panel.setFrame(frame, display: true)
        }
        if let mouseFrame {
            card.setFrame(mouseFrame, display: true)
        }
        // makeKeyAndOrderFront / NSApp.activate switch to the main window's
        // space. A nonactivating panel can take the keys without that switch.
        card.orderFrontRegardless()
        card.makeKey()
    }

    private func dismissFromOutsideClick() {
        guard closing == false else { return }
        AppRuntime.current?.model?.cancelDraft(.quick)
    }

    private func tearDown() {
        showingQuickAdd = false
        presentGeneration.value += 1
        stopClickMonitors()
        let windows = panels
        panels = []
        cardPanel = nil
        frames = [:]
        for window in windows {
            window.orderOut(nil)
        }
        closing = false
        closeTask = nil
    }

    /// Join the space the user is in, including another app's fullscreen space.
    /// moveToActiveSpace is omitted: once WorkLog activates, that flag follows
    /// the main window onto its own space.
    private static let panelBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary
    ]

    private func makePanel(frame: NSRect, keyable: Bool) -> QuickPanel {
        let panel = QuickPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.allowsKey = keyable
        panel.isFloatingPanel = true
        panel.collectionBehavior = Self.panelBehavior
        // statusBar and popUpMenu sit under another app's fullscreen window.
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func startClickMonitors() {
        stopClickMonitors()
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            let id = event.window?.identifier?.rawValue ?? ""
            if id == "worklog.quick" || id == "worklog.quick.catch" { return event }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    QuickAddPanel.shared.dismissFromOutsideClick()
                }
            }
            return nil
        }
        globalClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    QuickAddPanel.shared.dismissFromOutsideClick()
                }
            }
        }
    }

    private func stopClickMonitors() {
        if let localClick {
            NSEvent.removeMonitor(localClick)
            self.localClick = nil
        }
        if let globalClick {
            NSEvent.removeMonitor(globalClick)
            self.globalClick = nil
        }
    }

    /// The display under the pointer. NSScreen.main is WorkLog's own screen
    /// while another app is fullscreen, so it is not used.
    private static func currentScreen() -> NSScreen? {
        screenUnderMouse() ?? NSScreen.screens.first
    }

    private static func screenWithFullscreenWindow() -> NSScreen? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard let pid = ownerPID(info), pid != ownPID else { continue }
            let layer = intValue(info, kCGWindowLayer) ?? 0
            if layer >= 24 { continue }
            guard let bounds = quartzBounds(info),
                  let screen = screen(containingQuartz: bounds) else { continue }
            let cocoa = cocoaRect(bounds)
            if cocoa.width >= screen.frame.width * 0.85, cocoa.height >= screen.frame.height * 0.85 {
                return screen
            }
        }
        return nil
    }

    private static func screenUnderMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }

    private static func screenOfFrontmostWindow() -> NSScreen? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let pid = app.processIdentifier
        for info in list {
            guard Self.ownerPID(info) == pid else { continue }
            let layer = intValue(info, kCGWindowLayer) ?? 0
            if layer >= 24 { continue }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            if alpha < 0.01 { continue }
            guard let bounds = quartzBounds(info), bounds.width > 80, bounds.height > 80 else { continue }
            if let screen = screen(containingQuartz: bounds) { return screen }
        }
        return nil
    }

    private static func quartzBounds(_ info: [String: Any]) -> CGRect? {
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict)
    }

    private static func intValue(_ info: [String: Any], _ key: CFString) -> Int? {
        let name = key as String
        if let value = info[name] as? Int { return value }
        if let value = info[name] as? NSNumber { return value.intValue }
        return nil
    }

    private static func cocoaRect(_ bounds: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first(where: { $0.frame.contains(CGPoint.zero) }) ?? NSScreen.screens.first else {
            return bounds
        }
        return CGRect(
            x: bounds.origin.x,
            y: primary.frame.height - bounds.origin.y - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }

    private static func ownerPID(_ info: [String: Any]) -> Int32? {
        let key = kCGWindowOwnerPID as String
        if let pid = info[key] as? Int32 { return pid }
        if let pid = info[key] as? Int { return Int32(pid) }
        if let pid = info[key] as? NSNumber { return pid.int32Value }
        return nil
    }

    /// Quartz window bounds start at the top-left of the primary display.
    private static func screen(containingQuartz bounds: CGRect) -> NSScreen? {
        guard let primary = NSScreen.screens.first(where: { $0.frame.contains(CGPoint.zero) }) ?? NSScreen.screens.first else {
            return nil
        }
        let center = CGPoint(x: bounds.midX, y: primary.frame.height - bounds.midY)
        if let match = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -4, dy: -4).contains(center) }) {
            return match
        }
        return NSScreen.screens.min { lhs, rhs in
            let left = hypot(lhs.frame.midX - center.x, lhs.frame.midY - center.y)
            let right = hypot(rhs.frame.midX - center.x, rhs.frame.midY - center.y)
            return left < right
        }
    }
}

private final class PresentTicket: @unchecked Sendable {
    var value = 0
}

/// Forwards hover one turn later. SwiftUI's mouse-move hit test crashes if it
/// runs nested inside the double-tap event that opened this window.
private final class QuickHostingView<Content: View>: NSHostingView<Content> {
    private var deliveringMove = false

    override var needsPanelToBecomeKey: Bool { true }

    override func mouseMoved(with event: NSEvent) {
        if deliveringMove {
            super.mouseMoved(with: event)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.deliveringMove = true
            self.mouseMoved(with: event)
            self.deliveringMove = false
        }
    }
}

private final class QuickPanel: NSPanel {
    var allowsKey = true
    override var canBecomeKey: Bool { allowsKey }
    /// Becoming the main window makes macOS switch to that window's space.
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Dims one other display and accepts the first click, even while this panel is not key.
private final class OutsideClickView: NSView {
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 40 / 255, green: 36 / 255, blue: 30 / 255, alpha: 0.28).cgColor
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onClick?() }
}

/// Clean taps only: modifier down, then up, with no other key in between.
/// Fires on the second clean lift, so ⌘V never looks like a double-tap.
struct DoubleModifierTapDetector {
    var interval: TimeInterval = 0.35

    private var armed: DoubleModifierKind?
    private var armedAt: Date?
    private var pressKind: DoubleModifierKind?
    private var pressContaminated = false

    enum Event {
        case modifierDown(DoubleModifierKind)
        case modifierUp(DoubleModifierKind)
        case otherKey
    }

    mutating func reset() {
        armed = nil
        armedAt = nil
        pressKind = nil
        pressContaminated = false
    }

    mutating func handle(_ event: Event, now: Date = Date()) -> DoubleModifierKind? {
        switch event {
        case .otherKey:
            if pressKind != nil { pressContaminated = true }
            armed = nil
            armedAt = nil
            return nil
        case .modifierDown(let kind):
            pressKind = kind
            pressContaminated = false
            return nil
        case .modifierUp(let kind):
            let contaminated = pressKind == kind && pressContaminated
            if pressKind == kind {
                pressKind = nil
                pressContaminated = false
            }
            if contaminated {
                if armed == kind {
                    armed = nil
                    armedAt = nil
                }
                return nil
            }
            if let armed, armed == kind, let armedAt, now.timeIntervalSince(armedAt) <= interval {
                reset()
                return kind
            }
            self.armed = kind
            self.armedAt = now
            return nil
        }
    }
}

/// Listens for a double-tap of Control, Option, or Command. Carbon cannot express that.
@MainActor
final class DoubleTapHotKey {
    static let shared = DoubleTapHotKey()

    private var kind: DoubleModifierKind?
    private var detector = DoubleModifierTapDetector(interval: NSEvent.doubleClickInterval)
    private var lastFlags: NSEvent.ModifierFlags = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var askedForAccessibility = false
    private(set) var isListening = false

    var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start(_ kind: DoubleModifierKind) {
        self.kind = kind
        detector = DoubleModifierTapDetector(interval: NSEvent.doubleClickInterval)
        lastFlags = []
        startMonitors()
        if globalMonitor == nil { askForAccessibilityIfNeeded() }
    }

    func stop() {
        kind = nil
        detector.reset()
        lastFlags = []
        stopMonitors()
        isListening = false
    }

    func refreshIfNeeded() {
        guard kind != nil else { return }
        if localMonitor == nil || (accessibilityTrusted && globalMonitor == nil) {
            startMonitors()
        }
    }

    private func askForAccessibilityIfNeeded() {
        guard askedForAccessibility == false else { return }
        askedForAccessibility = true
        Self.promptAccessibility()
    }

    private func startMonitors() {
        stopMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let type = event.type
            let code = event.keyCode
            let flags = event.modifierFlags
            Task { @MainActor in
                self?.handle(type: type, code: code, flags: flags)
            }
            return event
        }
        if accessibilityTrusted {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                let type = event.type
                let code = event.keyCode
                let flags = event.modifierFlags
                Task { @MainActor in
                    self?.handle(type: type, code: code, flags: flags)
                }
            }
        }
        isListening = localMonitor != nil
    }

    private func stopMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    private func handle(type: NSEvent.EventType, code: UInt16, flags: NSEvent.ModifierFlags) {
        guard kind != nil else { return }
        if type == .keyDown {
            if DoubleModifierKind.from(keyCode: code) == nil {
                _ = detector.handle(.otherKey)
            }
            return
        }
        guard type == .flagsChanged else { return }
        guard let changed = DoubleModifierKind.from(keyCode: code) else {
            _ = detector.handle(.otherKey)
            lastFlags = flags.intersection([.control, .option, .command, .shift])
            return
        }
        let nowDown = flags.contains(changed.flag)
        let wasDown = lastFlags.contains(changed.flag)
        lastFlags = flags.intersection([.control, .option, .command, .shift])
        if nowDown && !wasDown {
            _ = detector.handle(.modifierDown(changed))
        } else if !nowDown && wasDown {
            if let fired = detector.handle(.modifierUp(changed)), fired == kind {
                QuickAddPanel.shared.summon()
            }
        }
    }
}
