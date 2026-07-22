import SwiftUI

struct ListeningView: View {
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
        .confirmationDialog("选择声音", isPresented: $isSelectingVoice, titleVisibility: .visible) {
            Button("系统默认") {
                viewModel.selectVoice(identifier: nil, announces: false)
            }
            ForEach(viewModel.voices) { voice in
                Button(voice.displayName) {
                    viewModel.selectVoice(identifier: voice.identifier, announces: false)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("Listening 提示", isPresented: errorPresented) {
            Button("重试") {
                viewModel.dismissError()
                viewModel.togglePlayback()
            }
            Button("关闭", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "发生未知错误")
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("返回阅读")
            .accessibilityIdentifier("listening.back")
            Spacer()
            Text("听书")
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
            .accessibilityLabel("当前句，\(viewModel.currentSentence)")
            .accessibilityIdentifier("listening.currentSentence")
    }

    private var primaryControls: some View {
        HStack(alignment: .top, spacing: 8) {
            controlButton(
                systemName: "backward.end.fill",
                label: "上一句",
                identifier: "listening.previous",
                action: { viewModel.previousSentence() }
            )
            controlButton(
                systemName: viewModel.state.isPlaying ? "pause.fill" : "play.fill",
                label: viewModel.state.isPlaying ? "暂停" : "播放",
                identifier: "listening.playPause",
                action: { viewModel.togglePlayback() }
            )
            controlButton(
                systemName: "forward.end.fill",
                label: "下一句",
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
                    Text("语速")
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
                .accessibilityLabel("语速")
                .accessibilityValue(ListeningViewModel.rateLabel(viewModel.rate))
                .accessibilityIdentifier("listening.rate")
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    isSelectingVoice = true
                } label: {
                    HStack {
                        Text("声音")
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
                .accessibilityLabel("声音")
                .accessibilityValue(selectedVoiceName)
                .accessibilityIdentifier("listening.voice")
            }
        }
    }

    private var selectedVoiceName: String {
        guard let identifier = viewModel.selectedVoiceIdentifier else { return "系统默认" }
        return viewModel.voices.first { $0.identifier == identifier }?.displayName ?? "无可用声音"
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }
}
