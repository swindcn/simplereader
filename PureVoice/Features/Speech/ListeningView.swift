import SwiftUI

struct ListeningView: View {
    @Environment(\.appStrings) private var strings
    @ObservedObject var viewModel: ListeningViewModel
    let onBack: () -> Void
    @State private var isSelectingVoice = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 24) {
                    bookIdentity
                    currentSentence
                    primaryControls
                    settings
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .onAppear { viewModel.ensureStarted() }
        .onDisappear { Task { await viewModel.flushProgress() } }
        .confirmationDialog(strings.chooseVoice, isPresented: $isSelectingVoice, titleVisibility: .visible) {
            Button(strings.systemDefault) {
                viewModel.selectVoice(identifier: nil, announces: false)
            }
            ForEach(viewModel.voices) { voice in
                Button(voice.displayName) {
                    viewModel.selectVoice(identifier: voice.identifier, announces: false)
                }
            }
            Button(strings.cancel, role: .cancel) {}
        }
        .alert(strings.listeningNotice, isPresented: errorPresented) {
            Button(strings.retry) {
                viewModel.dismissError()
                viewModel.togglePlayback()
            }
            Button(strings.close, role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? strings.unknownError)
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(strings.backToReading)
            .accessibilityIdentifier("listening.back")
            Spacer()
            Text(strings.listen)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .background(.regularMaterial)
    }

    private var bookIdentity: some View {
        VStack(spacing: 10) {
            cover
                .frame(width: 128, height: 176)
                .accessibilityHidden(true)
            Text(viewModel.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(viewModel.author)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cover: some View {
        if let url = viewModel.coverURL,
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
                .cornerRadius(6)
        } else {
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.secondary)
            }
            .cornerRadius(6)
        }
    }

    private var currentSentence: some View {
        Text(viewModel.currentSentence)
            .font(.title3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(8)
            .accessibilityLabel(strings.currentSentenceAccessibility(viewModel.currentSentence))
            .accessibilityIdentifier("listening.currentSentence")
    }

    private var primaryControls: some View {
        HStack(alignment: .top, spacing: 8) {
            controlButton(
                systemName: "backward.end.fill",
                label: strings.previousSentence,
                identifier: "listening.previous",
                action: { viewModel.previousSentence() }
            )
            controlButton(
                systemName: viewModel.state.isPlaying ? "pause.fill" : "play.fill",
                label: viewModel.state.isPlaying ? strings.pause : strings.play,
                identifier: "listening.playPause",
                action: { viewModel.togglePlayback() }
            )
            controlButton(
                systemName: "forward.end.fill",
                label: strings.nextSentence,
                identifier: "listening.next",
                action: { viewModel.nextSentence() }
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButton(
        systemName: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 52, height: 52)
                Text(label)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var settings: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(strings.speechRate)
                    Spacer()
                    Text(ListeningViewModel.rateLabel(viewModel.rate))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { viewModel.rate },
                        set: { viewModel.setRate($0, announces: false) }
                    ),
                    in: 0.5 ... 2,
                    step: 0.25
                )
                .accessibilityLabel(strings.speechRate)
                .accessibilityValue(ListeningViewModel.rateLabel(viewModel.rate))
                .accessibilityIdentifier("listening.rate")
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    isSelectingVoice = true
                } label: {
                    HStack {
                        Text(strings.voice)
                            .foregroundStyle(DesignTokens.onSurface)
                        Spacer()
                        Text(selectedVoiceName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(strings.voice)
                .accessibilityValue(selectedVoiceName)
                .accessibilityIdentifier("listening.voice")
            }
        }
    }

    private var selectedVoiceName: String {
        guard let identifier = viewModel.selectedVoiceIdentifier else { return strings.systemDefault }
        return viewModel.voices.first { $0.identifier == identifier }?.displayName ?? strings.unavailableVoice
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }
}
