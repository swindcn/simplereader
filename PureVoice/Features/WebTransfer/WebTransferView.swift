import SwiftUI
import UIKit

struct WebTransferView: View {
    @ObservedObject var viewModel: WebTransferViewModel
    @State private var clipboardMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            transferInstructions

            if let pairingCode = viewModel.pairingCode {
                pairingCodeView(pairingCode)
            }

            if !clipboardMessage.isEmpty {
                Text(clipboardMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(clipboardMessage)
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

    private var transferInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("让家人打开下面的网站，输入传书码后上传 TXT 或 EPUB。")
                .font(.callout)
                .foregroundStyle(.secondary)
            infoRow(
                title: "网站地址",
                value: viewModel.webTransferPageURL.absoluteString,
                actionTitle: "复制网站地址",
                accessibilityValue: viewModel.webTransferPageURL.absoluteString,
                copyValue: viewModel.webTransferPageURL.absoluteString
            )
            infoRow(
                title: "设备传书 ID",
                value: viewModel.deviceTransferID,
                actionTitle: nil,
                accessibilityValue: groupedIdentifier(viewModel.deviceTransferID),
                copyValue: nil
            )
            Text("设备传书 ID 是 App 生成的本机标识，不是 iPhone IMEI。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func infoRow(
        title: String,
        value: String,
        actionTitle: String?,
        accessibilityValue: String,
        copyValue: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .center, spacing: 8) {
                Text(value)
                    .font(.callout.monospaced())
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityLabel("\(title) \(accessibilityValue)")
                Spacer(minLength: 8)
                if let actionTitle, let copyValue {
                    Button(actionTitle) {
                        copyToPasteboard(copyValue, message: "\(title)已复制")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("复制后可以发给家人打开网站传书")
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func pairingCodeView(_ pairingCode: TransferPairingCode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(pairingCode.code)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .textSelection(.enabled)
                    .accessibilityLabel("传书码 \(pairingCode.code.map(String.init).joined(separator: " "))")
                Spacer(minLength: 8)
                Button("复制传书码") {
                    copyToPasteboard(pairingCode.code, message: "传书码已复制")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("复制后可以发给家人在网站中输入")
            }
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

    private func groupedIdentifier(_ identifier: String) -> String {
        identifier.map(String.init).joined(separator: " ")
    }

    private func copyToPasteboard(_ value: String, message: String) {
        UIPasteboard.general.string = value
        clipboardMessage = message
    }
}
