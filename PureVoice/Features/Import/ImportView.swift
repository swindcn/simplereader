import SwiftUI

struct ImportView: View {
    @ObservedObject var coordinator: ImportCoordinator
    @State private var isPickingDocument = false
    @State private var retryURL: URL?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                statusContent

                Button {
                    isPickingDocument = true
                } label: {
                    Label("选择文件", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
                .accessibilityLabel("选择要导入的书籍文件")
                .accessibilityHint("支持 TXT 和 EPUB")

                if case .failed = coordinator.state, let retryURL {
                    Button("重试") {
                        Task { try? await coordinator.importBook(from: retryURL) }
                    }
                    .accessibilityHint("重新导入上次选择的文件")
                }
            }
            .padding()
            .navigationTitle("导入书籍")
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $isPickingDocument) {
            DocumentPicker { url in
                retryURL = url
                isPickingDocument = false
                Task { try? await coordinator.importBook(from: url) }
            } onCancel: {
                isPickingDocument = false
            }
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch coordinator.state {
        case .idle:
            Text("选择本地书籍开始导入")
        case .copying:
            progress("正在复制文件")
        case .detecting:
            progress("正在识别格式")
        case .converting:
            progress("正在转换书籍")
        case .openingPublication:
            progress("正在验证书籍")
        case .completed:
            Label("导入完成", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(failure):
            Text(failure.userMessage)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private func progress(_ text: String) -> some View {
        ProgressView(text)
            .accessibilityLabel(text)
    }

    private var isBusy: Bool {
        switch coordinator.state {
        case .copying, .detecting, .converting, .openingPublication:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }
}
