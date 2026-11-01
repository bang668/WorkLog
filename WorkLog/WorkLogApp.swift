import SwiftUI

struct FieldEditingKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var worklogFieldEditing: Bool? {
        get { self[FieldEditingKey.self] }
        set { self[FieldEditingKey.self] = newValue }
    }
}

@main
struct WorkLogApp: App {
    @NSApplicationDelegateAdaptor(AppRuntime.self) private var appRuntime
    @State private var model: AppModel

    init() {
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 640)
                .background(WindowChrome())
                .onAppear {
                    appRuntime.model = model
                    AppRuntime.current = appRuntime
                    model.installQuickHotKey = { QuickHotKeyCenter.shared.install($0) }
                    _ = QuickHotKeyCenter.shared.install(model.quickHotKey)
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建日志仓库") { model.pickNewFolder() }
                Button("打开其他的日志仓库") { model.pickExistingFolder() }
                Button("导入…") { model.showImport = true }
                    .disabled(model.hasLibrary == false)
                Divider()
                Button("导出…") { model.showExport = true }
                    .disabled(model.hasLibrary == false)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { TextEdit.undo(redo: false) }
                    .keyboardShortcut("z", modifiers: .command)
                Button("重做") { TextEdit.undo(redo: true) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button("剪切") { TextEdit.cut() }
                    .keyboardShortcut("x", modifiers: .command)
                Button("拷贝") { TextEdit.copy { model.copySelected() } }
                    .keyboardShortcut("c", modifiers: .command)
                Button("粘贴") { TextEdit.paste { model.paste() } }
                    .keyboardShortcut("v", modifiers: .command)
                Button("全选") { TextEdit.selectAll() }
                    .keyboardShortcut("a", modifiers: .command)
            }
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .help) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .appSettings) {
                SettingsCommand()
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// The global add panel and Settings both take over the screen. Opening Settings
/// on top of that panel leaves neither one able to close.
private struct SettingsCommand: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("设置…") {
            guard QuickAddPanel.shared.isShowing == false else { return }
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

/// Text-field shortcuts are handled here, at the moment of the key press.
/// Menu items built earlier cannot see which field is editing, and a disabled
/// menu item with the same shortcut only beeps.
enum TextEdit {
    static func copy(otherwise item: () -> Void) {
        guard let text = editingText else { item(); return }
        text.copy(nil)
    }

    static func paste(otherwise item: () -> Void) {
        guard let text = editingText else { item(); return }
        text.paste(nil)
    }

    static func cut() {
        editingText?.cut(nil)
    }

    static func selectAll() {
        editingText?.selectAll(nil)
    }

    static func undo(redo: Bool) {
        guard let text = editingText else { return }
        (text as? NSTextView)?.allowsUndo = true
        let manager = text.undoManager ?? text.window?.undoManager
        if redo {
            if manager?.canRedo == true { manager?.redo() }
        } else if manager?.canUndo == true {
            manager?.undo()
        }
    }

    /// Returns true when the key was used by a text field and should not reach the menu.
    static func handleShortcut(keyCode: UInt16, shift: Bool, command: Bool, control: Bool, option: Bool) -> Bool {
        guard command, control == false, option == false, editingText != nil else { return false }
        switch keyCode {
        case 0 where shift == false: selectAll()
        case 6: undo(redo: shift)
        case 7 where shift == false: cut()
        case 8 where shift == false: copy { }
        case 9 where shift == false: paste { }
        default: return false
        }
        return true
    }

    private static var editingText: NSText? {
        guard let window = NSApp.keyWindow else { return nil }
        var responder: NSResponder? = window.firstResponder
        while let current = responder {
            if let view = current as? NSTextView, view.isEditable {
                view.allowsUndo = true
                return view
            }
            if let field = current as? NSTextField, field.isEditable, let editor = field.currentEditor() {
                (editor as? NSTextView)?.allowsUndo = true
                return editor
            }
            if current is NSWindow { break }
            responder = current.nextResponder
        }
        return nil
    }
}

/// Drops the stock menus this app does not use, including the system writing tools in Edit.
final class MenuSlimmer: NSObject, NSMenuDelegate {
    static let shared = MenuSlimmer()

    private let droppedMenus = ["Format", "格式", "View", "显示", "Help", "帮助"]
    private let droppedItems = [
        "New Window", "新建窗口",
        "Writing Tools", "写作工具",
        "Services", "服务",
        "Find", "查找", "Find…", "查找…",
        "Spelling", "拼写", "Spelling and Grammar", "拼写和语法",
        "Substitutions", "替换",
        "Transformations", "转换",
        "Speech", "语音",
        "AutoFill", "自动填充",
        "Start Dictation…", "开始听写…",
        "Emoji & Symbols", "表情与符号"
    ]
    private var slimming = false

    func install() {
        guard slimming == false, let main = NSApp.mainMenu else { return }
        slimming = true
        defer { slimming = false }
        attach(main)
        dropTopLevel(main)
        for item in main.items {
            attach(item.submenu)
            if let submenu = item.submenu {
                slim(submenu)
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard slimming == false else { return }
        slimming = true
        defer { slimming = false }
        if menu == NSApp.mainMenu {
            dropTopLevel(menu)
            for item in menu.items { attach(item.submenu) }
            return
        }
        slim(menu)
    }

    private func attach(_ menu: NSMenu?) {
        guard let menu, menu.delegate !== self else { return }
        menu.delegate = self
    }

    private func dropTopLevel(_ menu: NSMenu) {
        for title in droppedMenus {
            guard let item = menu.item(withTitle: title) else { continue }
            menu.removeItem(item)
        }
    }

    private func slim(_ menu: NSMenu) {
        let parent = NSApp.mainMenu?.items.first { $0.submenu === menu }?.title ?? menu.title
        if parent == "编辑" || parent == "Edit" {
            let keep: Set<String> = [
                "撤销", "重做", "剪切", "拷贝", "粘贴", "全选",
                "Undo", "Redo", "Cut", "Copy", "Paste", "Select All"
            ]
            for item in menu.items.reversed() where keep.contains(item.title) == false || item.isEnabled == false {
                menu.removeItem(item)
            }
            tidySeparators(menu)
            return
        }
        for item in menu.items where droppedItems.contains(item.title) {
            menu.removeItem(item)
        }
        tidySeparators(menu)
    }

    private func tidySeparators(_ menu: NSMenu) {
        var index = 0
        var previousWasSeparator = true
        while index < menu.items.count {
            let item = menu.items[index]
            if item.isSeparatorItem, previousWasSeparator {
                menu.removeItem(at: index)
                continue
            }
            previousWasSeparator = item.isSeparatorItem
            index += 1
        }
        while let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
    }
}

private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.apply(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(to: nsView) }
    }

    private static func apply(to view: NSView) {
        guard let window = view.window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.tabbingMode = .disallowed
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(srgbRed: 0.953, green: 0.945, blue: 0.925, alpha: 1)
        window.identifier = NSUserInterfaceItemIdentifier("worklog.main")
    }
}
