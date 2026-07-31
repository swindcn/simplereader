import SwiftUI
import UIKit

struct WebTransferView: View {
    @Environment(\.appStrings) private var strings
    @ObservedObject var viewModel: WebTransferViewModel
    @State private var clipboardMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            transferCard
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
        HStack(spacing: 14) {
            Image("NetworkTransfer")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(DesignTokens.primary)
                .frame(width: 44, height: 44)
                .background(DesignTokens.primary.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text(strings.webTransferSubtitle)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(strings.webTransferSubtitle)
    }

    private var transferCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            transferCodeBlock

            Divider()
                .overlay(DesignTokens.outline.opacity(0.55))

            transferWebsiteBlock

            if !clipboardMessage.isEmpty {
                Text(clipboardMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DesignTokens.onSurfaceVariant)
                    .accessibilityLabel(clipboardMessage)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(DesignTokens.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DesignTokens.outline.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
    }

    private var transferCodeBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            labelText(strings.transferCode)
            if let pairingCode = viewModel.pairingCode {
                HStack(spacing: 12) {
                    Text(pairingCode.code)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.48)
                        .lineLimit(1)
                        .accessibilityLabel(strings.transferCodeAccessibility(pairingCode.code))
                    Spacer(minLength: 12)
                    iconCopyButton(value: pairingCode.code, message: strings.transferCodeCopied, label: strings.copyTransferCode)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
                .background(DesignTokens.fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(strings.transferCodeInstruction)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DesignTokens.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView(strings.generatingTransferCode)
                    .frame(maxWidth: .infinity, minHeight: 86)
                    .background(DesignTokens.fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var transferWebsiteBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            labelText(strings.transferURL)
            HStack(spacing: 12) {
                Text(viewModel.webTransferPageURL.absoluteString)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .accessibilityLabel(strings.transferURLAccessibility(viewModel.webTransferPageURL.absoluteString))
                Spacer(minLength: 12)
                iconCopyButton(value: viewModel.webTransferPageURL.absoluteString, message: strings.transferURLCopied, label: strings.copyTransferURL)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .center)
            .background(DesignTokens.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func labelText(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.subheadline.weight(.bold))
            .foregroundStyle(DesignTokens.onSurfaceVariant)
    }

    private func iconCopyButton(value: String, message: String, label: String) -> some View {
        Button {
            copyToPasteboard(value, message: message)
        } label: {
            Image("CopyAction")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 23, height: 23)
                .foregroundStyle(DesignTokens.onSurfaceVariant)
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
                .font(.callout.weight(.medium))
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
        .background(DesignTokens.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DesignTokens.outline.opacity(0.65), lineWidth: 1)
        )
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
