import SwiftUI

struct ImportView: View {
    @Environment(\.appStrings) private var strings
    @ObservedObject var coordinator: ImportCoordinator
    @ObservedObject var webTransferViewModel: WebTransferViewModel
    @State private var isPickingDocument = false
    private let importFieldBackground = Color(red: 0.937, green: 0.937, blue: 0.937)
    private let localImportTextColor = Color(red: 0.318, green: 0.318, blue: 0.318)

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    localImportSection
                    WebTransferView(viewModel: webTransferViewModel)
                }
                .padding()
            }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image("LocalImport")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(DesignTokens.onSurface)
                    .accessibilityHidden(true)
                Text(strings.localImportHeading)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.onSurface)
                Spacer()
                statusContent
            }

            Button {
                isPickingDocument = true
            } label: {
                VStack(spacing: 10) {
                    Image("LocalImport")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                    Text(strings.chooseFromDevice)
                        .font(.title3.weight(.bold))
                }
                .foregroundStyle(isBusy ? .secondary : localImportTextColor)
                .frame(maxWidth: .infinity, minHeight: 132)
                .background(importFieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(strings.chooseBookAccessibility)
            .accessibilityHint(strings.supportedImportHint)

            if case .failed = coordinator.state, let retryURL = coordinator.retrySourceURL {
                Button(strings.retry) {
                    Task { try? await coordinator.importBook(from: retryURL) }
                }
                .accessibilityHint(strings.retryPreviousImportHint)
            }
        }
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
