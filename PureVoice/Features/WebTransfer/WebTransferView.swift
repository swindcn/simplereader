import SwiftUI

struct WebTransferView: View {
    @ObservedObject var viewModel: WebTransferViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let pairingCode = viewModel.pairingCode {
                pairingCodeView(pairingCode)
            }

            Button {
                Task { await viewModel.generateCode() }
            } label: {
                Label(viewModel.pairingCode == nil ? "生成传书码" : "重新生成传书码", systemImage: "number")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isBusy)
            .accessibilityHint("生成网页上传书籍时需要输入的传书码")

            inboxContent
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .alert("网站传书提示", isPresented: errorPresented) {
            Button("好", role: .cancel) { viewModel.error = nil }
        } message: {
            Text(viewModel.error?.message ?? "")
        }
    }

    private var header: some View {
        HStack {
            Label("网站传书", systemImage: "globe")
                .font(.headline)
            Spacer()
            Button("刷新") {
                Task { await viewModel.refreshInbox() }
            }
            .disabled(viewModel.isBusy)
            .accessibilityHint("刷新待接收文件列表")
        }
    }

    private func pairingCodeView(_ pairingCode: TransferPairingCode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pairingCode.code)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .textSelection(.enabled)
                .accessibilityLabel("传书码 \(pairingCode.code.map(String.init).joined(separator: " "))")
            Text("长期有效，重新生成后旧码失效")
                .foregroundStyle(.secondary)
            Text("上传的书籍保留 72 小时")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var inboxContent: some View {
        if viewModel.inbox.isEmpty {
            Text("暂无待接收文件")
                .foregroundStyle(.secondary)
                .accessibilityLabel("暂无待接收文件")
        } else {
            VStack(spacing: 12) {
                ForEach(viewModel.inbox) { item in
                    inboxRow(item)
                }
            }
        }
    }

    private func inboxRow(_ item: TransferInboxItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(item.format.uppercased()) · \(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("导入") {
                Task { await viewModel.importItem(item) }
            }
            .disabled(viewModel.isBusy)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("删除", role: .destructive) {
                Task { await viewModel.deleteItem(item) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.filename)，\(item.format.uppercased())，\(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))")
        .accessibilityHint("点按导入到书架，长按可删除")
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )
    }
}
