import SwiftUI
import UIKit

struct ImportView: View {
    @Environment(\.appStrings) private var strings
    @ObservedObject var coordinator: ImportCoordinator
    @ObservedObject var webTransferViewModel: WebTransferViewModel
    @State private var isPickingDocument = false
    private let chooseFromDeviceTextColor = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .pureVoiceOnSurface
                : UIColor(red: 0.318, green: 0.318, blue: 0.318, alpha: 1)
        }
    )

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    localImportSection
                    WebTransferView(viewModel: webTransferViewModel)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .hidingScrollContentBackgroundIfAvailable()
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle(strings.importTitle)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                sectionIcon("LocalImport")
                Text(strings.localImportHeading)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer()
            }

            Button {
                isPickingDocument = true
            } label: {
                VStack(spacing: 14) {
                    Image("LocalImport")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.000, green: 0.478, blue: 1.000),
                                    Color(red: 0.408, green: 0.337, blue: 0.929)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: DesignTokens.primary.opacity(0.22), radius: 14, y: 8)
                    Text(strings.chooseFromDevice)
                        .font(.title3.weight(.bold))
                    Text(strings.supportedImportHint)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DesignTokens.onSurfaceVariant)
                }
                .foregroundStyle(isBusy ? DesignTokens.onSurfaceVariant : chooseFromDeviceTextColor)
                .frame(maxWidth: .infinity, minHeight: 184)
                .background(DesignTokens.surfaceElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            DesignTokens.outline.opacity(0.52),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5])
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(strings.chooseBookAccessibility)
            .accessibilityHint(strings.supportedImportHint)

            statusContent

            if case .failed = coordinator.state, let retryURL = coordinator.retrySourceURL {
                Button(strings.retry) {
                    Task { try? await coordinator.importBook(from: retryURL) }
                }
                .accessibilityHint(strings.retryPreviousImportHint)
            }
        }
    }

    private func sectionIcon(_ name: String) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundStyle(DesignTokens.primary)
            .frame(width: 44, height: 44)
            .background(DesignTokens.primary.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch coordinator.state {
        case .idle:
            EmptyView()
        case .copying:
            progress(strings.copyingFile)
        case .detecting:
            progress(strings.detectingFormat)
        case .converting:
            progress(strings.convertingBook)
        case .openingPublication:
            progress(strings.validatingBook)
        case .completed:
            Text(strings.importCompleted)
                .font(.headline)
                .foregroundStyle(.green)
        case let .failed(failure):
            let userError = UserFacingError(importFailure: failure)
            VStack(spacing: 8) {
                Text(userError.message)
                    .foregroundStyle(.red)
                Text(userError.recoveryAction)
                    .font(.callout)
                    .foregroundStyle(DesignTokens.onSurfaceVariant)
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
