import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var fileURL: URL?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("导入")
                .font(.system(size: 18, weight: .semibold))
            Text("已经记下的事项会原样保留，只把文件里新的事项追加到对应日期后面。不会改掉，也不会删掉原有记录。同一天、同一句描述已经有的，不再加一遍。")
                .font(.system(size: 13))
                .foregroundStyle(WorkColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("文本格式")
                .font(.system(size: 13, weight: .medium))
            Text("日期单独占一行，写成 2026-10-22。这一天的事项写在下面，每条前面缩进。备注和类型先空着，导入之后可以再补。")
                .font(.system(size: 13))
                .foregroundStyle(WorkColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(example)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(red: 0.227, green: 0.227, blue: 0.235))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(red: 0.965, green: 0.957, blue: 0.937), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text("文本文件")
                    .font(.system(size: 12))
                    .foregroundStyle(WorkColor.tertiary)
                HStack(spacing: 8) {
                    Text(fileURL?.lastPathComponent ?? "还没有选择文件")
                        .font(.system(size: 13))
                        .foregroundStyle(fileURL == nil ? WorkColor.tertiary : WorkColor.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("选择文件") { pickFile() }
                        .buttonStyle(WorkButtonStyle())
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 36)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(red: 0.867, green: 0.839, blue: 0.796))
                )
            }
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(WorkColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(WorkButtonStyle())
                Button("确认导入") { confirm() }
                    .buttonStyle(WorkButtonStyle(prominent: true))
                    .disabled(fileURL == nil)
            }
        }
        .padding(18)
        .frame(width: 520)
        .background(WorkColor.card)
    }

    private var example: String {
        """
        2026-10-22
        \tfastjson版本升级
        \t国际散航采购开发
        2026-10-23
        \tHermes版本整理
        \tAI运价识别
        """
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsOtherFileTypes = true
        panel.prompt = "选择"
        panel.message = "选择按日期分行的文本文件。"
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                fileURL = url
                message = nil
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else if panel.runModal() == .OK {
            fileURL = panel.url
            message = nil
        }
    }

    private func confirm() {
        guard let fileURL else { return }
        let checked = model.reviewImport(at: fileURL)
        if let text = checked.message {
            message = text
            return
        }
        if let review = checked.review {
            message = nil
            model.commitImport(review) { dismiss() }
        }
    }
}
