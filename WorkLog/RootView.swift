import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("worklog.sidebarWidth") private var sidebarWidth = 212.0
    @AppStorage("worklog.sidebarCollapsed") private var sidebarCollapsed = false
    @State private var liveWidth: Double?
    @State private var dragOriginX: CGFloat?
    @State private var widthAtStart: Double?

    var body: some View {
        Group {
            if model.hasLibrary {
                HStack(spacing: 0) {
                    if sidebarCollapsed == false {
                        SidebarView()
                            .frame(width: liveWidth ?? sidebarWidth)
                        sidebarHandle
                    }
                    MainCanvas()
                }
                .coordinateSpace(name: "root")
                .ignoresSafeArea(edges: .top)
            } else {
                WelcomeView()
            }
        }
        .background(WorkColor.paper)
        .alert(model.alertTitle ?? "", isPresented: alertPresented) {
            Button("好") { model.alertTitle = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .alert(model.confirmTitle ?? "", isPresented: confirmPresented) {
            Button(model.confirmCancelTitle, role: .cancel) {
                model.confirmAction = nil
                model.pendingDeleteItemID = nil
            }
            Button(model.confirmAcceptTitle, role: .destructive) {
                model.confirmAction?()
                model.confirmAction = nil
            }
        } message: {
            Text(model.confirmMessage ?? "")
        }
        .sheet(isPresented: exportPresented) {
            ExportSheet()
                .environment(model)
        }
        .sheet(isPresented: importPresented) {
            ImportSheet()
                .environment(model)
        }
    }

    private var sidebarHandle: some View {
        Rectangle()
            .fill(WorkColor.line)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("root"))
                            .onChanged { value in
                                if dragOriginX == nil {
                                    dragOriginX = value.startLocation.x
                                    widthAtStart = liveWidth ?? sidebarWidth
                                }
                                let delta = value.location.x - (dragOriginX ?? value.startLocation.x)
                                liveWidth = min(360, max(84, (widthAtStart ?? sidebarWidth) + delta))
                                NSCursor.resizeLeftRight.set()
                            }
                            .onEnded { _ in
                                if let liveWidth { sidebarWidth = liveWidth }
                                liveWidth = nil
                                dragOriginX = nil
                                widthAtStart = nil
                                NSCursor.arrow.set()
                            }
                    )
                    .onHover { inside in
                        if inside || dragOriginX != nil {
                            NSCursor.resizeLeftRight.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
            }
    }

    private var alertPresented: Binding<Bool> {
        Binding(get: { model.alertTitle != nil }, set: { if !$0 { model.alertTitle = nil } })
    }

    private var confirmPresented: Binding<Bool> {
        Binding(get: { model.confirmTitle != nil }, set: { if !$0 { model.confirmTitle = nil; model.confirmAction = nil } })
    }

    private var exportPresented: Binding<Bool> {
        Binding(get: { model.showExport }, set: { model.showExport = $0 })
    }

    private var importPresented: Binding<Bool> {
        Binding(get: { model.showImport }, set: { model.showImport = $0 })
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            let today = Date()
            let parts = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: today)
            VStack(spacing: 2) {
                Text("\(parts.month ?? 1)月")
                    .font(.system(size: 11))
                Text("\(parts.day ?? 1)")
                    .font(.system(size: 26, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 72, height: 72)
            .background(
                LinearGradient(colors: [Color(red: 0.30, green: 0.64, blue: 1), WorkColor.blue], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .shadow(color: WorkColor.blue.opacity(0.28), radius: 12, y: 8)
            Text("把日志放在一个文件夹里")
                .font(.system(size: 22, weight: .semibold))
            Text("第一次使用时新建，或打开已有的文件夹。\n这个选择会记在这台 Mac 上。")
                .foregroundStyle(WorkColor.secondary)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 12) {
                Button("新建文件夹") { model.pickNewFolder() }
                    .buttonStyle(WorkButtonStyle(prominent: true))
                Button("打开已有文件夹") { model.pickExistingFolder() }
                    .buttonStyle(WorkButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
