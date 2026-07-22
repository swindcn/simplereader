import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var viewModel: ListeningViewModel
    let onOpen: () -> Void
    let onClose: () -> Void
    var reservesTabBarSpace = false

    var body: some View {
        if viewModel.isMiniPlayerVisible {
            HStack(spacing: 12) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(viewModel.currentSentence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回听书，\(viewModel.title)")
                .accessibilityIdentifier("miniPlayer.open")

                Button(action: { viewModel.togglePlayback() }) {
                    Image(systemName: viewModel.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(viewModel.state.isPlaying ? "暂停" : "播放")
                .accessibilityIdentifier("miniPlayer.playPause")

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("关闭听书")
                .accessibilityIdentifier("miniPlayer.close")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
            .padding(.bottom, reservesTabBarSpace ? DesignTokens.minimumTouchTarget : 0)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("miniPlayer")
        }
    }
}
