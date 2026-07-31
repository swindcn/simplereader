import SwiftUI
import UIKit

struct LibraryView: View {
    @Environment(\.appFontSize) private var appFontSize
    @Environment(\.appStrings) private var strings
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: LibraryViewModel
    @ObservedObject private var libraryRefresh: LibraryRefreshSignal
    @State private var renameTarget: Book?
    @State private var renameTitle = ""
    @State private var deleteTarget: Book?
    @State private var actionTarget: Book?
    let reservesMiniPlayerSpace: Bool
    private let onMagicTapListen: (Book) -> Void
    private let shelfColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    init(
        repository: any BookRepository,
        libraryRefresh: LibraryRefreshSignal = LibraryRefreshSignal(),
        webTransferViewModel: WebTransferViewModel? = nil,
        reservesMiniPlayerSpace: Bool = false,
        onOpenBook: @escaping (Book) -> Void = { _ in },
        onMagicTapListen: @escaping (Book) -> Void = { _ in }
    ) {
        self.libraryRefresh = libraryRefresh
        self.reservesMiniPlayerSpace = reservesMiniPlayerSpace
        self.onMagicTapListen = onMagicTapListen
        _viewModel = StateObject(
            wrappedValue: LibraryViewModel(
                repository: repository,
                receiveWebTransfers: webTransferViewModel.map { viewModel in
                    {
                        _ = await viewModel.receivePendingItems()
                        return viewModel.error
                    }
                },
                onOpenBook: onOpenBook
            )
        )
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                libraryHeader
                Divider()
                    .accessibilityHidden(true)
                Group {
                    if viewModel.isLoading && viewModel.continueReadingBook == nil && viewModel.shelfBooks.isEmpty {
                        ProgressView(strings.libraryLoading)
                    } else if viewModel.continueReadingBook == nil && viewModel.shelfBooks.isEmpty {
                        emptyState
                    } else {
                        libraryContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.background.ignoresSafeArea())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .task { await viewModel.load() }
        .onChange(of: libraryRefresh.generation) { _ in
            Task { await viewModel.load() }
        }
        .alert(strings.renameBookTitle, isPresented: renamePresented, presenting: renameTarget) { book in
            TextField(strings.bookNamePlaceholder, text: $renameTitle)
            Button(strings.cancel, role: .cancel) {}
            Button(strings.save) {
                Task { await viewModel.rename(book, to: renameTitle) }
            }
        } message: { book in
            Text(strings.renameBookMessage(book.title))
        }
        .sheet(item: $actionTarget) { book in
            BookActionsSheet(
                book: book,
                onRename: {
                    actionTarget = nil
                    beginRename(book)
                },
                onDelete: {
                    actionTarget = nil
                    deleteTarget = book
                },
                onCancel: { actionTarget = nil }
            )
            .appFontSize(appFontSize)
        }
        .sheet(item: $deleteTarget) { book in
            DeleteBookSheet(
                book: book,
                onCancel: { deleteTarget = nil },
                onDelete: {
                    deleteTarget = nil
                    Task { await viewModel.delete(book) }
                }
            )
            .appFontSize(appFontSize)
        }
        .alert(strings.operationFailed, isPresented: errorPresented) {
            Button(strings.ok, role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? strings.unknownError)
        }
        .accessibilityAction(.magicTap) {
            guard let book = viewModel.accessibilityMagicTapBook else {
                AccessibilityFeedback.notification(.warning)
                AccessibilityFeedback.announce(strings.libraryEmptyTitle)
                return
            }
            AccessibilityFeedback.doubleLightPulse()
            AccessibilityFeedback.announce(strings.continueListeningAnnouncement(book.title))
            onMagicTapListen(book)
        }
        .accessibilityAction(.escape) {
            AccessibilityFeedback.impact(.medium)
            AccessibilityFeedback.announce(strings.returned)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var libraryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let book = viewModel.continueReadingBook {
                    ContinueReadingSection(
                        book: book,
                        onOpen: { Task { await viewModel.open(book) } },
                        onRename: { presentAccessibilityOperation(.rename, for: book) },
                        onDelete: { presentAccessibilityOperation(.delete, for: book) }
                    )
                }

                if !viewModel.shelfBooks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(strings.myBooks)
                            .font(.title2.bold())
                            .foregroundStyle(DesignTokens.onSurface)
                        LazyVGrid(columns: shelfColumns, alignment: .leading, spacing: 18) {
                            ForEach(viewModel.shelfBooks) { book in
                                BookGridItem(
                                    book: book,
                                    accessibilityIdentifier: "library.shelf.book.\(book.id.uuidString)",
                                    onOpen: {
                                        AccessibilityFeedback.impact(.light)
                                        AccessibilityFeedback.announce(strings.enteredBook(book.title))
                                        Task { await viewModel.open(book) }
                                    },
                                    onRename: { presentAccessibilityOperation(.rename, for: book) },
                                    onDelete: { presentAccessibilityOperation(.delete, for: book) }
                                )
                            }
                        }
                        .accessibilityElement(children: .contain)
                    }
                } else if viewModel.continueReadingBook != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(strings.myBooks)
                            .font(.title2.bold())
                            .foregroundStyle(DesignTokens.onSurface)
                        Text(strings.onlyBookInContinue)
                            .font(.body)
                            .foregroundStyle(DesignTokens.onSurfaceVariant)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.edgeMargin)
            .padding(.vertical, DesignTokens.stackGap)
        }
        .refreshable { await viewModel.refreshAndReceiveWebTransfers() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let reservedHeight = LibraryBottomInsetPolicy.reservedHeight(isMiniPlayerVisible: reservesMiniPlayerSpace)
            if reservedHeight > 0 {
                DesignTokens.background
                    .ignoresSafeArea(edges: .bottom)
                    .frame(height: reservedHeight)
                    .accessibilityHidden(true)
            }
        }
    }

    private var libraryHeader: some View {
        HStack {
            brandTitle
            Spacer(minLength: 12)
            NavigationLink {
                HelpGuideView()
            } label: {
                Image("HelpAction")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(DesignTokens.onSurface)
                    .frame(width: 54, height: 54)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(strings.helpLibraryAccessibility)
            .accessibilityIdentifier("library.helpButton")

            Button {
                Task { await viewModel.refreshAndReceiveWebTransfers() }
            } label: {
                Image("RefreshAction")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(DesignTokens.onSurface)
                    .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                    .animation(
                        viewModel.isLoading
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: viewModel.isLoading
                    )
                    .frame(width: 54, height: 54)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .accessibilityLabel(strings.refreshLibraryAccessibility)
        }
        .padding(.horizontal, DesignTokens.edgeMargin)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(DesignTokens.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.header")
    }

    private struct BookGridItem: View {
        @Environment(\.appStrings) private var strings
        let book: Book
        let accessibilityIdentifier: String
        let onOpen: () -> Void
        let onRename: () -> Void
        let onDelete: () -> Void
        @ScaledMetric(relativeTo: .headline) private var titleReserveHeight: CGFloat = 46

        var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                cover
                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.onSurface)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: titleReserveHeight, alignment: .topLeading)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.onSurfaceVariant)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(percentage)%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(DesignTokens.onSurfaceVariant)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                ProgressView(value: progress)
                    .tint(DesignTokens.primary)
                    .frame(height: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(BookRow.accessibilityLabel(for: book, strings: strings))
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityHint(strings.doubleTapContinueHint)
            .accessibilityAction(named: Text(strings.rename), onRename)
            .accessibilityAction(named: Text(strings.delete), onDelete)
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in onDelete() })
        }

        private var cover: some View {
            GeometryReader { proxy in
                Group {
                    if let coverURL = book.coverFileURL,
                       let image = UIImage(contentsOfFile: coverURL.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            placeholderColor
                            Text(book.title.prefix(1))
                                .font(.system(size: 42, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
            }
            .aspectRatio(0.72, contentMode: .fit)
        }

        private var progress: Double {
            book.position?.progression ?? 0
        }

        private var percentage: Int {
            Int((progress * 100).rounded())
        }

        private var placeholderColor: Color {
            let colors: [Color] = [
                Color(red: 0.08, green: 0.22, blue: 0.42),
                Color(red: 0.42, green: 0.12, blue: 0.18),
                Color(red: 0.08, green: 0.32, blue: 0.24),
                Color(red: 0.20, green: 0.20, blue: 0.24)
            ]
            let stableIndex = Int(book.id.uuid.0)
            return colors[stableIndex % colors.count]
        }
    }

    private var brandTitle: some View {
        HStack(spacing: 12) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .opacity(colorScheme == .dark ? 0 : 1)
                .overlay {
                    Image("BrandLogoDark")
                        .resizable()
                        .scaledToFit()
                        .opacity(colorScheme == .dark ? 1 : 0)
                }
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
                .accessibilityIdentifier("library.brandLogo")
            Text(strings.brandName)
                .font(.title2.bold())
                .foregroundStyle(DesignTokens.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(strings.brandName)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.primary)
                .accessibilityHidden(true)
            Text(strings.libraryEmptyTitle)
                .font(.title3.bold())
                .foregroundStyle(DesignTokens.onSurface)
            Text(strings.libraryEmptyHint)
                .font(.body)
                .foregroundStyle(DesignTokens.onSurfaceVariant)
            Button {
                Task { await viewModel.refreshAndReceiveWebTransfers() }
            } label: {
                Label(strings.refreshWebTransfers, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
            .accessibilityHint(strings.refreshWebTransfersHint)
        }
        .multilineTextAlignment(.center)
        .padding(DesignTokens.edgeMargin)
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    private func beginRename(_ book: Book) {
        renameTitle = book.title
        renameTarget = book
    }

    private func presentAccessibilityOperation(_ operation: LibraryBookAccessibilityOperation, for book: Book) {
        switch operation.presentation {
        case .renameEditor:
            beginRename(book)
        case .deleteConfirmation:
            deleteTarget = book
        }
    }
}

enum LibraryBookActionPresentation: Equatable {
    case renameEditor
    case deleteConfirmation
}

enum LibraryBookAccessibilityOperation: Equatable {
    case rename
    case delete

    var presentation: LibraryBookActionPresentation {
        switch self {
        case .rename:
            return .renameEditor
        case .delete:
            return .deleteConfirmation
        }
    }
}

enum LibraryBottomInsetPolicy {
    static func reservedHeight(isMiniPlayerVisible: Bool) -> CGFloat {
        isMiniPlayerVisible ? DesignTokens.minimumTouchTarget + DesignTokens.stackGap : 0
    }
}

struct HelpGuideEntry: Equatable, Identifiable {
    enum Section: Equatable {
        case library
        case reader
    }

    enum Illustration: Equatable {
        case doubleTap
        case oneFingerDoubleTap
        case verticalSwipe
        case leftSwipe
        case rightSwipe
        case speed
        case scrub
    }

    let id: String
    let section: Section
    let gesture: String
    let title: String
    let description: String
    let illustration: Illustration
}

enum HelpGestureGuide {
    static func entries(strings: AppStrings) -> [HelpGuideEntry] {
        [
            HelpGuideEntry(
                id: "library-magic-tap",
                section: .library,
                gesture: strings.magicTapGesture,
                title: strings.libraryMagicTapHelpTitle,
                description: strings.libraryMagicTapHelpDescription,
                illustration: .doubleTap
            ),
            HelpGuideEntry(
                id: "library-open-book",
                section: .library,
                gesture: strings.doubleTapGesture,
                title: strings.bookActivateHelpTitle,
                description: strings.bookActivateHelpDescription,
                illustration: .oneFingerDoubleTap
            ),
            HelpGuideEntry(
                id: "library-actions",
                section: .library,
                gesture: strings.swipeUpDownGesture,
                title: strings.bookActionsHelpTitle,
                description: strings.bookActionsHelpDescription,
                illustration: .verticalSwipe
            ),
            HelpGuideEntry(
                id: "reader-magic-tap",
                section: .reader,
                gesture: strings.magicTapGesture,
                title: strings.playbackMagicTapHelpTitle,
                description: strings.playbackMagicTapHelpDescription,
                illustration: .doubleTap
            ),
            HelpGuideEntry(
                id: "reader-next-chapter",
                section: .reader,
                gesture: strings.threeFingerLeftGesture,
                title: strings.nextChapterHelpTitle,
                description: strings.nextChapterHelpDescription,
                illustration: .leftSwipe
            ),
            HelpGuideEntry(
                id: "reader-previous-chapter",
                section: .reader,
                gesture: strings.threeFingerRightGesture,
                title: strings.previousChapterHelpTitle,
                description: strings.previousChapterHelpDescription,
                illustration: .rightSwipe
            ),
            HelpGuideEntry(
                id: "reader-speech-rate",
                section: .reader,
                gesture: strings.threeFingerUpDownGesture,
                title: strings.speechRateHelpTitle,
                description: strings.speechRateHelpDescription,
                illustration: .speed
            ),
            HelpGuideEntry(
                id: "reader-escape",
                section: .reader,
                gesture: strings.scrubGesture,
                title: strings.escapeHelpTitle,
                description: strings.escapeHelpDescription,
                illustration: .scrub
            )
        ]
    }
}

private struct HelpGuideView: View {
    @Environment(\.appStrings) private var strings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(strings.helpIntro)
                        .font(.body)
                        .foregroundStyle(DesignTokens.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("help.intro")

                    helpSection(.library, title: strings.libraryGesturesSection)
                    helpSection(.reader, title: strings.readerGesturesSection)
                }
                .padding(.horizontal, DesignTokens.edgeMargin)
                .padding(.vertical, DesignTokens.stackGap)
            }
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 54, height: 54)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.primary)
            .accessibilityLabel(strings.backToLibrary)

            Spacer(minLength: 8)
            Text(strings.helpTitle)
                .font(.title2.bold())
                .foregroundStyle(DesignTokens.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 8)
            Color.clear
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DesignTokens.edgeMargin)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(DesignTokens.background)
    }

    private func helpSection(_ section: HelpGuideEntry.Section, title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(DesignTokens.onSurface)
            VStack(spacing: 12) {
                ForEach(HelpGestureGuide.entries(strings: strings).filter { $0.section == section }) { entry in
                    HelpGestureCard(entry: entry)
                }
            }
        }
    }
}

private struct HelpGestureCard: View {
    let entry: HelpGuideEntry

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            GestureIllustration(kind: entry.illustration)
                .frame(width: 78, height: 78)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.gesture)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DesignTokens.primary)
                    .textCase(.uppercase)
                    .lineLimit(2)
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.description)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(DesignTokens.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .stroke(DesignTokens.outline.opacity(0.75), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.gesture)，\(entry.title)，\(entry.description)")
    }
}

private struct GestureIllustration: View {
    let kind: HelpGuideEntry.Illustration

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.fieldBackground)
            illustration
                .padding(10)
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch kind {
        case .doubleTap:
            FingerDots(count: 2)
            TapPulse()
        case .oneFingerDoubleTap:
            FingerDots(count: 1)
            TapPulse()
        case .verticalSwipe:
            FingerDots(count: 1)
            ArrowGlyph(systemName: "arrow.up.and.down")
        case .leftSwipe:
            FingerDots(count: 3)
            ArrowGlyph(systemName: "arrow.left")
        case .rightSwipe:
            FingerDots(count: 3)
            ArrowGlyph(systemName: "arrow.right")
        case .speed:
            FingerDots(count: 3)
            ArrowGlyph(systemName: "arrow.up.arrow.down")
        case .scrub:
            FingerDots(count: 2)
            ScrubPath()
        }
    }
}

private struct FingerDots: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { _ in
                Capsule()
                    .fill(DesignTokens.onSurface)
                    .frame(width: 9, height: 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ArrowGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(DesignTokens.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

private struct TapPulse: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(DesignTokens.primary.opacity(0.45), lineWidth: 3)
                .frame(width: 38, height: 38)
            Circle()
                .fill(DesignTokens.primary)
                .frame(width: 12, height: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

private struct ScrubPath: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 18, y: 18))
            path.addLine(to: CGPoint(x: 44, y: 18))
            path.addLine(to: CGPoint(x: 18, y: 44))
            path.addLine(to: CGPoint(x: 44, y: 44))
        }
        .stroke(
            DesignTokens.primary,
            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

private struct BookActionsSheet: View {
    @Environment(\.appStrings) private var strings
    let book: Book
    let onRename: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.title3.bold())
                    .foregroundStyle(DesignTokens.onSurface)
                    .lineLimit(2)
                Text(book.author)
                    .font(.body)
                    .foregroundStyle(DesignTokens.onSurfaceVariant)
                    .lineLimit(1)
            }

            VStack(spacing: 12) {
                Button(action: onRename) {
                    Label(strings.rename, systemImage: "pencil")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("library.action.rename")

                Button(role: .destructive, action: onDelete) {
                    Label(strings.delete, systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("library.action.delete")

                Button(strings.cancel, action: onCancel)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .accessibilityIdentifier("library.action.cancel")
            }
        }
        .padding(24)
        .accessibilityElement(children: .contain)
    }
}

private struct DeleteBookSheet: View {
    @Environment(\.appStrings) private var strings
    let book: Book
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text(strings.deleteBookTitle)
                    .font(.title3.bold())
                    .foregroundStyle(DesignTokens.onSurface)
                Text(strings.deleteBookMessage(book.title))
                    .font(.body)
                    .foregroundStyle(DesignTokens.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button(strings.cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .accessibilityIdentifier("library.delete.cancel")
                Button(strings.delete, role: .destructive, action: onDelete)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .accessibilityIdentifier("library.delete.confirm")
            }
        }
        .padding(24)
        .accessibilityElement(children: .contain)
    }
}
