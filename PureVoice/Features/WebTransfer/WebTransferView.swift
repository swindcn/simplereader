import SwiftUI
import UIKit

struct WebTransferView: View {
    @Environment(\.appStrings) private var strings
    @ObservedObject var viewModel: WebTransferViewModel
    @State private var clipboardMessage = ""
    private let transferFieldBackground = Color(red: 0.937, green: 0.937, blue: 0.937)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            transferCard

            if !clipboardMessage.isEmpty {
                Text(clipboardMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(clipboardMessage)
            }

            inboxContent
        }
        .accessibilityElement(children: .contain)
        .task { await viewModel.prepareTransferCode() }
        .alert(strings.webTransferAlertTitle, isPresented: errorPresented) {
            Button(strings.ok, role: .cancel) { viewModel.error = nil }
        } message: {
            Text(viewModel.error?.message ?? "")
        }
    }

    private var header: some View {
        HStack {
            Image("NetworkTransfer")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .foregroundStyle(DesignTokens.onSurface)
                .accessibilityHidden(true)
            Text(strings.webTransferTitle)
                .font(.title3.weight(.semibold))
            Text(strings.webTransferSubtitle)
                .font(.headline)
            Spacer(minLength: 0)
        }
    }

    private var transferCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text(strings.transferCode)
                    .font(.headline)
                if let pairingCode = viewModel.pairingCode {
                    HStack(spacing: 12) {
                        Text(pairingCode.code)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                            .accessibilityLabel(strings.transferCodeAccessibility(pairingCode.code))
                        Spacer(minLength: 16)
                        iconCopyButton(value: pairingCode.code, message: strings.transferCodeCopied, label: strings.copyTransferCode)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
                    .background(transferFieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    ProgressView(strings.generatingTransferCode)
                        .frame(maxWidth: .infinity, minHeight: 82)
                        .background(transferFieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(strings.transferURL)
                    .font(.headline)
                HStack(spacing: 12) {
                    Text(viewModel.webTransferPageURL.absoluteString)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.52)
                        .accessibilityLabel(strings.transferURLAccessibility(viewModel.webTransferPageURL.absoluteString))
                    Spacer(minLength: 16)
                    iconCopyButton(value: viewModel.webTransferPageURL.absoluteString, message: strings.transferURLCopied, label: strings.copyTransferURL)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
                .background(transferFieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func iconCopyButton(value: String, message: String, label: String) -> some View {
        Button {
            copyToPasteboard(value, message: message)
        } label: {
            Image("CopyAction")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(DesignTokens.onSurface)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(strings.copyTransferHint)
    }

    @ViewBuilder
    private var inboxContent: some View {
        if viewModel.inbox.isEmpty {
            Text(strings.noPendingFiles)
                .foregroundStyle(.secondary)
                .accessibilityLabel(strings.noPendingFiles)
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
            Button(strings.importAction) {
                Task { await viewModel.importItem(item) }
            }
            .disabled(viewModel.isBusy)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button(strings.delete, role: .destructive) {
                Task { await viewModel.deleteItem(item) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.filename)，\(item.format.uppercased())，\(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))")
        .accessibilityHint(strings.importItemHint)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )
    }

    private func copyToPasteboard(_ value: String, message: String) {
        UIPasteboard.general.string = value
        withAnimation(.easeOut(duration: 0.2)) {
            clipboardMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if clipboardMessage == message {
                withAnimation(.easeIn(duration: 0.2)) {
                    clipboardMessage = ""
                }
            }
        }
    }
}
