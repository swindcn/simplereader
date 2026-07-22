import SwiftUI

struct ImportView: View {
    @ObservedObject var coordinator: ImportCoordinator
    @ObservedObject var webTransferViewModel: WebTransferViewModel
    @State private var isPickingDocument = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    localImportSection
                    WebTransferView(viewModel: webTransferViewModel)
                }
                .padding()
            }
            .navigationTitle("导入书籍")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $isPickingDocument) {
            DocumentPicker { url in
                isPickingDocument = false
                Task { try? await coordinator.importBook(from: url) }
            } onCancel: {
                isPickingDocument = false
            }
        }
    }

    private var localImportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image("LocalImport")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(DesignTokens.onSurface)
                    .accessibilityHidden(true)
                Text("选择本地书籍开始导入")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.onSurface)
                Spacer()
                statusContent
            }

            Button {
                isPickingDocument = true
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 48))
                    Text("从本机选择")
                        .font(.title3.weight(.bold))
                }
                .foregroundStyle(isBusy ? .secondary : DesignTokens.primary)
                .frame(maxWidth: .infinity, minHeight: 132)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel("选择要导入的书籍文件")
            .accessibilityHint("支持 TXT 和 EPUB")

            if case .failed = coordinator.state, let retryURL = coordinator.retrySourceURL {
                Button("重试") {
                    Task { try? await coordinator.importBook(from: retryURL) }
                }
                .accessibilityHint("重新导入上次选择的文件")
            }
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch coordinator.state {
        case .idle:
            EmptyView()
        case .copying:
            progress("正在复制文件")
        case .detecting:
            progress("正在识别格式")
        case .converting:
            progress("正在转换书籍")
        case .openingPublication:
            progress("正在验证书籍")
        case .completed:
            Text("导入完成")
                .font(.headline)
                .foregroundStyle(.green)
        case let .failed(failure):
            let userError = UserFacingError(importFailure: failure)
            VStack(spacing: 8) {
                Text(userError.message)
                    .foregroundStyle(.red)
                Text(userError.recoveryAction)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
