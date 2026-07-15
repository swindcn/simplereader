import SwiftUI
import UIKit
@preconcurrency import ReadiumShared

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ReaderViewModel
    @StateObject private var commands = EPUBNavigatorCommands()

    private let onListen: (OpenedPublication, Locator?) -> Void
    private let onSettings: () -> Void

    init(
        book: Book,
        repository: any BookRepository,
        onListen: @escaping (OpenedPublication, Locator?) -> Void = { _, _ in },
        onSettings: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(book: book, repository: repository))
        self.onListen = onListen
        self.onSettings = onSettings
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("正在打开这本书")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage, viewModel.openedPublication == nil {
                failureView(message)
            } else if let publication = viewModel.openedPublication {
                reader(publication)
            } else {
                ProgressView()
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .task { await viewModel.open() }
        .onDisappear { Task { await viewModel.flushProgress() } }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                Task { await viewModel.flushProgress() }
            }
        }
        .sheet(isPresented: $viewModel.isTableOfContentsPresented) {
            tableOfContents
        }
        .alert("阅读器提示", isPresented: nonfatalErrorPresented) {
            Button("好", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "发生未知错误")
        }
    }

    private func reader(_ publication: OpenedPublication) -> some View {
        VStack(spacing: 0) {
            AccessibilityChapterHeading(
                title: displayedHeading(for: publication),
                focusGeneration: viewModel.chapterFocusGeneration
            )
            .frame(maxWidth: .infinity, minHeight: 52)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 64)

            ReaderHeaderToolbar(
                onBack: closeReader,
                onTableOfContents: { viewModel.isTableOfContentsPresented = true }
            )

            ZStack(alignment: .topLeading) {
                EPUBNavigatorController(
                    publication: publication,
                    initialLocation: viewModel.initialLocator,
                    navigationRequest: viewModel.navigationRequest,
                    commands: commands,
                    onLocationChange: viewModel.receive(locator:),
                    onNavigationFailure: viewModel.reportNavigationFailure,
                    onError: viewModel.reportNavigatorError
                )
                .accessibilityLabel("阅读内容")
                .accessibilityAction(named: Text("上一页"), commands.previousPage)
                .accessibilityAction(named: Text("下一页"), commands.nextPage)
#if DEBUG
                if ProcessInfo.processInfo.environment["PUREVOICE_UI_TEST_READER_EPUB"] != nil {
                    Text(debugLocatorLabel)
                        .font(.system(size: 1))
                        .frame(width: 2, height: 2)
                        .foregroundStyle(.clear)
                        .accessibilityLabel(debugLocatorLabel)
                        .accessibilityIdentifier("reader.debug.locator")
                }
#endif
            }

            ReaderToolbar(
                onPreviousPage: commands.previousPage,
                onNextPage: commands.nextPage,
                onListen: { onListen(publication, viewModel.currentLocator) },
                onSettings: onSettings
            )
        }
    }

    private var tableOfContents: some View {
        NavigationView {
            List(viewModel.tableOfContents) { entry in
                Button {
                    viewModel.selectChapter(entry)
                } label: {
                    Text(entry.title)
                        .padding(.leading, CGFloat(entry.level) * 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("reader.toc.\(entry.id)")
            }
            .navigationTitle("目录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { viewModel.isTableOfContentsPresented = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("无法打开这本书")
                .font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("返回书架", action: closeReader)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reader.failure.back")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nonfatalErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && viewModel.openedPublication != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    private func closeReader() {
        Task {
            if await viewModel.flushProgress() {
                dismiss()
            }
        }
    }

    private func displayedHeading(for publication: OpenedPublication) -> String {
#if DEBUG
        if let override = ProcessInfo.processInfo.environment["PUREVOICE_UI_TEST_READER_HEADING"] {
            return override
        }
#endif
        return viewModel.chapterTitle.isEmpty ? publication.title : viewModel.chapterTitle
    }

#if DEBUG
    private var debugLocatorLabel: String {
        guard let locator = viewModel.currentLocator else { return "等待定位" }
        let progression = locator.locations.totalProgression ?? locator.locations.progression ?? 0
        return "\(locator.href.string)|\(progression)"
    }
#endif
}

private struct AccessibilityChapterHeading: UIViewRepresentable {
    let title: String
    let focusGeneration: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.backgroundColor = .systemBackground.withAlphaComponent(0.92)
        label.isAccessibilityElement = true
        label.accessibilityTraits = .header
        label.accessibilityIdentifier = "reader.chapterHeading"
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = title
        label.accessibilityLabel = title
        guard focusGeneration > 0,
              focusGeneration != context.coordinator.lastPostedGeneration
        else { return }
        context.coordinator.lastPostedGeneration = focusGeneration
        UIAccessibility.post(notification: .layoutChanged, argument: label)
    }

    final class Coordinator {
        var lastPostedGeneration = 0
    }
}
