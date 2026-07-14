# V1 Offline Accessible Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a releasable iOS 15+ reader that imports local TXT, EPUB, and approved non-DRM MOBI files, renders publications with Readium, reads them aloud with Apple system voices, persists progress, and completes all core tasks with VoiceOver.

**Architecture:** SwiftUI owns the app shell and feature screens while focused service protocols isolate storage, import, Readium, and speech behavior. All imported formats become a canonical EPUB before reading, and Core Data stores metadata and locations while book files remain in Application Support. Stitch project `14191187057079968133` is the visual source of truth; native accessibility semantics replace generated HTML semantics.

**Tech Stack:** Swift 6, SwiftUI, UIKit bridge, iOS 15, XcodeGen, Core Data, Readium Swift Toolkit 3.8.0, AVFoundation, MediaPlayer, XCTest, XCUITest

---

## Scope Boundary

This plan delivers V1 offline functionality. StoreKit credits, cloud LLM refinement, and website transfer are separate implementation plans. The V1 app contains disabled-by-absence behavior for those features: it does not show unfinished buttons or placeholder screens.

## Fixed Commands

Run all simulator tests with:

```bash
xcodebuild test \
  -project PureVoice.xcodeproj \
  -scheme PureVoice \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

Run a generic build with:

```bash
xcodebuild build \
  -project PureVoice.xcodeproj \
  -scheme PureVoice \
  -destination 'generic/platform=iOS Simulator'
```

## File Map

```text
project.yml                                      Reproducible Xcode project definition
PureVoice/App/                                   App entry point, dependency container, tab shell
PureVoice/DesignSystem/                          Stitch-derived colors, typography, spacing, controls
PureVoice/Core/Models/                           Book, chapter, import, reader and speech value types
PureVoice/Core/Persistence/                      Core Data stack and repository implementation
PureVoice/Core/Files/                            Application Support storage and safe file operations
PureVoice/Features/Library/                      Bookshelf, recent books and book actions
PureVoice/Features/Import/                       Picker, detector, TXT/EPUB/MOBI conversion pipeline
PureVoice/Features/Reader/                       Readium opener, navigator bridge and reader toolbar
PureVoice/Features/Speech/                       Readium speech orchestration and remote controls
PureVoice/Features/Settings/                     Reading and speech preferences
PureVoice/Resources/                             Info.plist, assets and localization
PureVoiceTests/                                  Unit and integration tests
PureVoiceUITests/                                VoiceOver-oriented UI semantics and flow tests
docs/adr/                                        MOBI license and integration decision
```

### Task 1: Reproducible Xcode Project

**Files:**
- Create: `project.yml`
- Create: `PureVoice/App/PureVoiceApp.swift`
- Create: `PureVoice/App/RootTabView.swift`
- Create: `PureVoice/Resources/Info.plist`
- Create: `PureVoice/Resources/Assets.xcassets/Contents.json`
- Create: `PureVoiceTests/ProjectSmokeTests.swift`
- Create: `PureVoiceUITests/AppLaunchUITests.swift`

- [ ] **Step 1: Install the project generator**

Run: `brew install xcodegen`

Expected: `xcodegen --version` prints an installed version and exits 0.

- [ ] **Step 2: Define the project and pin Readium**

Create `project.yml` with iOS 15, Swift 6, application/test targets, and exact Readium 3.8.0 package products:

```yaml
name: PureVoice
options:
  bundleIdPrefix: com.taotaoxiaoshuo
  deploymentTarget:
    iOS: "15.0"
packages:
  Readium:
    url: https://github.com/readium/swift-toolkit.git
    exactVersion: 3.8.0
  ZIPFoundation:
    # Readium 3.8.0 depends on this fork and its 3.x product name.
    url: https://github.com/readium/ZIPFoundation.git
    exactVersion: 3.0.1
targets:
  PureVoice:
    type: application
    platform: iOS
    sources:
      - PureVoice
    info:
      path: PureVoice/Resources/Info.plist
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.taotaoxiaoshuo.purevoice
        SWIFT_VERSION: "6.0"
        TARGETED_DEVICE_FAMILY: "1,2"
    dependencies:
      - package: Readium
        product: ReadiumShared
      - package: Readium
        product: ReadiumStreamer
      - package: Readium
        product: ReadiumNavigator
      - package: ZIPFoundation
        product: ReadiumZIPFoundation
  PureVoiceTests:
    type: bundle.unit-test
    platform: iOS
    sources: [PureVoiceTests]
    dependencies:
      - target: PureVoice
  PureVoiceUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [PureVoiceUITests]
    dependencies:
      - target: PureVoice
schemes:
  PureVoice:
    build:
      targets:
        PureVoice: all
    test:
      targets:
        - PureVoiceTests
        - PureVoiceUITests
```

- [ ] **Step 3: Add the minimal app and launch tests**

Create an app whose initial tabs are fixed as `书架`, `导入`, and `设置`. The UI test must assert these three labels exist and `听书` is not a permanent tab.

```swift
func testFixedTabsAreVisible() {
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["书架"].exists)
    XCTAssertTrue(app.tabBars.buttons["导入"].exists)
    XCTAssertTrue(app.tabBars.buttons["设置"].exists)
    XCTAssertFalse(app.tabBars.buttons["听书"].exists)
}
```

- [ ] **Step 4: Generate and build**

Run: `xcodegen generate && xcodebuild build -project PureVoice.xcodeproj -scheme PureVoice -destination 'generic/platform=iOS Simulator'`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add project.yml PureVoice PureVoiceTests PureVoiceUITests PureVoice.xcodeproj
git commit -m "build: scaffold PureVoice iOS app"
```

### Task 2: Stitch Design System and Stable App Shell

**Files:**
- Create: `PureVoice/DesignSystem/DesignTokens.swift`
- Create: `PureVoice/DesignSystem/AccessibleIconButton.swift`
- Create: `PureVoice/App/AppTab.swift`
- Modify: `PureVoice/App/RootTabView.swift`
- Test: `PureVoiceTests/DesignTokensTests.swift`

- [ ] **Step 1: Write failing token tests**

```swift
import XCTest
@testable import PureVoice

final class DesignTokensTests: XCTestCase {
    func testMinimumTouchTargetMatchesApprovedDesign() {
        XCTAssertEqual(DesignTokens.minimumTouchTarget, 60)
        XCTAssertLessThanOrEqual(DesignTokens.cardRadius, 8)
    }
}
```

- [ ] **Step 2: Verify the test fails**

Run: `xcodebuild test -project PureVoice.xcodeproj -scheme PureVoice -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:PureVoiceTests/DesignTokensTests`

Expected: FAIL because `DesignTokens` does not exist.

- [ ] **Step 3: Implement tokens and the icon-button contract**

```swift
import SwiftUI

enum DesignTokens {
    static let minimumTouchTarget: CGFloat = 60
    static let cardRadius: CGFloat = 8
    static let edgeMargin: CGFloat = 24
    static let stackGap: CGFloat = 16
    static let primary = Color(red: 0, green: 65 / 255, blue: 200 / 255)
    static let surface = Color(red: 250 / 255, green: 248 / 255, blue: 1)
    static let onSurface = Color(red: 25 / 255, green: 27 / 255, blue: 37 / 255)
}

struct AccessibleIconButton: View {
    let systemName: String
    let label: LocalizedStringKey
    let hint: LocalizedStringKey?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 28, weight: .semibold))
                .frame(minWidth: DesignTokens.minimumTouchTarget,
                       minHeight: DesignTokens.minimumTouchTarget)
        }
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
    }
}
```

Define `AppTab` as a fixed `CaseIterable` enum ordered `.library`, `.importBooks`, `.settings`; render it with native `TabView` so VoiceOver announces tab position.

- [ ] **Step 4: Run tests and inspect at large text**

Run the token test, then launch with Accessibility Inspector using the largest Dynamic Type size.

Expected: tests PASS; all tab labels remain visible without overlap.

- [ ] **Step 5: Commit**

```bash
git add PureVoice/DesignSystem PureVoice/App PureVoiceTests/DesignTokensTests.swift
git commit -m "feat: add Stitch-based accessible app shell"
```

### Task 3: Domain Models and Repository Contract

**Files:**
- Create: `PureVoice/Core/Models/Book.swift`
- Create: `PureVoice/Core/Models/BookFormat.swift`
- Create: `PureVoice/Core/Models/ReadingPosition.swift`
- Create: `PureVoice/Core/Models/ImportState.swift`
- Create: `PureVoice/Core/Persistence/BookRepository.swift`
- Create: `PureVoice/Core/Persistence/InMemoryBookRepository.swift`
- Create: `PureVoiceTests/Support/Book+Fixture.swift`
- Test: `PureVoiceTests/InMemoryBookRepositoryTests.swift`

- [ ] **Step 1: Write failing repository tests**

Test that saving a book makes it fetchable, updating its position preserves metadata, and deleting removes it.

```swift
func testSaveUpdateAndDeleteBook() async throws {
    let repository = InMemoryBookRepository()
    var book = Book.fixture(title: "活着")
    try await repository.save(book)
    XCTAssertEqual(try await repository.book(id: book.id)?.title, "活着")

    book.position = ReadingPosition(href: "chapter-12.xhtml", progression: 0.35)
    try await repository.save(book)
    XCTAssertEqual(try await repository.book(id: book.id)?.position?.progression, 0.35)

    try await repository.delete(id: book.id)
    XCTAssertNil(try await repository.book(id: book.id))
}
```

- [ ] **Step 2: Verify the tests fail**

Expected: FAIL because the model and repository types do not exist.

- [ ] **Step 3: Implement minimal sendable domain types**

`Book` contains `id`, `title`, `author`, `format`, `originalFileURL`, `canonicalFileURL`, `coverFileURL`, `position`, `lastOpenedAt`, and `createdAt`. `BookFormat` has exactly `txt`, `epub`, and `mobi`. `ReadingPosition` stores Readium-compatible `href`, optional `locationsJSON`, and progression clamped to `0...1`.

Implement `BookRepository` with async `allBooks`, `recentBooks(limit:)`, `book(id:)`, `save`, and `delete`, then implement the actor-backed in-memory repository used by tests and previews.

Create the test fixture factory with fixed defaults so every later test uses the same valid model:

```swift
extension Book {
    static func fixture(
        id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        title: String = "活着",
        author: String = "余华",
        format: BookFormat = .epub
    ) -> Book {
        Book(
            id: id,
            title: title,
            author: author,
            format: format,
            originalFileURL: URL(fileURLWithPath: "/tmp/\(id.uuidString)/original.epub"),
            canonicalFileURL: URL(fileURLWithPath: "/tmp/\(id.uuidString)/publication.epub"),
            coverFileURL: nil,
            position: nil,
            lastOpenedAt: nil,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
```

- [ ] **Step 4: Run tests**

Expected: repository tests PASS under Thread Sanitizer.

- [ ] **Step 5: Commit**

```bash
git add PureVoice/Core PureVoiceTests/InMemoryBookRepositoryTests.swift
git commit -m "feat: define book domain and repository contract"
```

### Task 4: Core Data Persistence and File Storage

**Files:**
- Create: `PureVoice/Core/Persistence/PersistenceController.swift`
- Create: `PureVoice/Core/Persistence/CoreDataBookRepository.swift`
- Create: `PureVoice/Core/Files/BookFileStore.swift`
- Test: `PureVoiceTests/CoreDataBookRepositoryTests.swift`
- Test: `PureVoiceTests/BookFileStoreTests.swift`

- [ ] **Step 1: Write failing persistence and file tests**

Use an in-memory `NSPersistentStoreDescription` and a temporary directory. Assert repository round trips every `Book` field and that deleting a book removes only its own UUID directory.

- [ ] **Step 2: Verify failures**

Expected: FAIL because production persistence types do not exist.

- [ ] **Step 3: Implement persistence without generated managed-object subclasses**

Build the `NSManagedObjectModel` in `PersistenceController.makeModel()` with one `BookEntity` and explicit attributes matching the domain model. Map `ReadingPosition` to JSON `Data`. Configure production storage in Application Support and test storage as in-memory.

Implement file layout exactly as:

```text
Application Support/PureVoice/Books/<book UUID>/original.<extension>
Application Support/PureVoice/Books/<book UUID>/publication.epub
Application Support/PureVoice/Books/<book UUID>/cover
```

`BookFileStore.importOriginal(from:bookID:)` must coordinate security-scoped access, copy instead of move, reject files larger than 250 MB, and translate Cocoa out-of-space errors to `BookFileError.outOfSpace`.

- [ ] **Step 4: Run tests**

Expected: Core Data round-trip and isolated-delete tests PASS.

- [ ] **Step 5: Commit**

```bash
git add PureVoice/Core/Persistence PureVoice/Core/Files PureVoiceTests
git commit -m "feat: persist library and imported files"
```

### Task 5: Bookshelf UI and Accessible Book Actions

**Files:**
- Create: `PureVoice/Features/Library/LibraryViewModel.swift`
- Create: `PureVoice/Features/Library/LibraryView.swift`
- Create: `PureVoice/Features/Library/BookRow.swift`
- Create: `PureVoice/Features/Library/ContinueReadingSection.swift`
- Test: `PureVoiceTests/LibraryViewModelTests.swift`
- Test: `PureVoiceUITests/LibraryAccessibilityUITests.swift`

- [ ] **Step 1: Write failing view-model and UI tests**

Seed four books through the launch environment. Assert the most recently opened book is the continue-reading item, only three recent rows render, and each row exposes one combined accessibility label such as `活着，余华，已读百分之三十五`.

- [ ] **Step 2: Verify failures**

Expected: FAIL because the library feature is absent.

- [ ] **Step 3: Implement the Stitch modern bookshelf**

Match the Stitch screen's cover treatment, typography, progress presentation, and bottom navigation. Keep each book row as one `Button`, mark the cover `.accessibilityHidden(true)`, combine visible text with `.accessibilityElement(children: .ignore)`, and expose rename/delete as accessibility actions and context-menu commands.

- [ ] **Step 4: Run tests at standard and accessibility text sizes**

Expected: logic and UI tests PASS; no title truncates at the largest accessibility size in portrait.

- [ ] **Step 5: Commit**

```bash
git add PureVoice/Features/Library PureVoiceTests PureVoiceUITests
git commit -m "feat: build accessible modern bookshelf"
```

### Task 6: Import State Machine, Format Detection, and Document Picker

**Files:**
- Create: `PureVoice/Features/Import/ImportCoordinator.swift`
- Create: `PureVoice/Features/Import/ImportError.swift`
- Create: `PureVoice/Features/Import/BookFormatDetector.swift`
- Create: `PureVoice/Features/Import/DocumentPicker.swift`
- Create: `PureVoice/Features/Import/ImportView.swift`
- Test: `PureVoiceTests/BookFormatDetectorTests.swift`
- Test: `PureVoiceTests/ImportCoordinatorTests.swift`

- [ ] **Step 1: Write failing detector and state tests**

Cover case-insensitive extensions, EPUB ZIP signature, MOBI `BOOKMOBI` signature, unsupported files, cancellation, successful state order, and preservation of the original file on conversion failure.

- [ ] **Step 2: Verify failures**

Expected: FAIL because detector and coordinator are absent.

- [ ] **Step 3: Implement the explicit state machine**

Use these states only:

```swift
enum ImportState: Equatable, Sendable {
    case idle
    case copying
    case detecting
    case converting(BookFormat)
    case openingPublication
    case completed(Book.ID)
    case failed(ImportFailure)
}
```

The coordinator copies first, detects from content plus extension, invokes the format converter, validates the canonical EPUB through the publication opener, saves metadata last, and cleans partial canonical files without deleting the original.

Implement `UIDocumentPickerViewController` for `public.plain-text`, `org.idpf.epub-container`, and filename extensions `mobi`, `azw`, and `azw3`.

- [ ] **Step 4: Run tests**

Expected: all state transitions are deterministic and tests PASS.

- [ ] **Step 5: Commit**

```bash
git add PureVoice/Features/Import PureVoiceTests
git commit -m "feat: add local import pipeline"
```

### Task 7: TXT Decoding, Chapter Parsing, and Canonical EPUB

**Files:**
- Create: `PureVoice/Features/Import/TXT/TXTDecoder.swift`
- Create: `PureVoice/Features/Import/TXT/ChapterParser.swift`
- Create: `PureVoice/Features/Import/TXT/EPUBBuilder.swift`
- Create: `PureVoice/Core/Models/Chapter.swift`
- Test: `PureVoiceTests/TXTDecoderTests.swift`
- Test: `PureVoiceTests/ChapterParserTests.swift`
- Test: `PureVoiceTests/EPUBBuilderTests.swift`
- Test Resource: `PureVoiceTests/Fixtures/txt/utf8-novel.txt`
- Test Resource: `PureVoiceTests/Fixtures/txt/gb18030-novel.txt`

- [ ] **Step 1: Write failing fixture-driven tests**

Assert UTF-8 and GB18030 decode correctly; headings such as `第十二章 重逢`, `第 12 章`, and `Chapter 12` split chapters; ordinary sentences containing `章节` do not split; and the produced EPUB contains `mimetype`, `META-INF/container.xml`, OPF, navigation document, and one XHTML file per chapter.

- [ ] **Step 2: Verify failures**

Expected: FAIL because TXT components are absent.

- [ ] **Step 3: Implement deterministic conversion**

Try UTF-8, UTF-16 little/big endian, GB18030, and GBK in that order, rejecting decodes with excessive replacement characters. Use anchored regular expressions for chapter headings. Escape XML through `XMLDocument` or a dedicated XML encoder rather than string substitution.

Build EPUB 3 with uncompressed first `mimetype` entry and ZIP remaining entries. Normalize paragraphs but preserve meaningful blank-line section breaks. If no headings are found, create one chapter named `正文`.

- [ ] **Step 4: Validate the EPUB with Readium**

Open the generated fixture through `PublicationOpener`; assert title, reading order count, and table of contents count.

Expected: all TXT and EPUB-builder tests PASS.

- [ ] **Step 5: Commit**

```bash
git add PureVoice/Features/Import/TXT PureVoice/Core/Models/Chapter.swift PureVoiceTests
git commit -m "feat: convert TXT novels to canonical EPUB"
```

### Task 8: Readium Publication Service and EPUB Import

**Files:**
- Create: `PureVoice/Features/Reader/ReadiumContainer.swift`
- Create: `PureVoice/Features/Reader/PublicationService.swift`
- Test: `PureVoiceTests/PublicationServiceTests.swift`
- Test Resource: `PureVoiceTests/Fixtures/epub/minimal.epub`
- Test Resource: `PureVoiceTests/Fixtures/epub/malformed.epub`

- [ ] **Step 1: Write failing publication tests**

Assert a valid EPUB opens, metadata and cover can be extracted, malformed EPUB maps to a localized import failure, and DRM-protected formats are rejected without a passphrase prompt.

- [ ] **Step 2: Verify failures**

Expected: FAIL because the publication service is absent.

- [ ] **Step 3: Implement the verified Readium 3.8 API path**

Construct the Readium services exactly as follows:

```swift
let httpClient: HTTPClient = DefaultHTTPClient()
let assetRetriever = AssetRetriever(httpClient: httpClient)
let publicationOpener = PublicationOpener(
    parser: DefaultPublicationParser(
        httpClient: httpClient,
        assetRetriever: assetRetriever,
        pdfFactory: DefaultPDFDocumentFactory()
    ),
    contentProtections: []
)

guard let absoluteURL = FileURL(url: fileURL) else {
    throw PublicationServiceError.invalidFileURL
}
let asset = try await assetRetriever.retrieve(url: absoluteURL).get()
let publication = try await publicationOpener.open(
    asset: asset,
    allowUserInteraction: false,
    sender: nil
).get()
```

Return an app-owned `OpenedPublication` that keeps the Readium `Publication` alive while exposing normalized title, author, cover, table of contents, and locator conversion.

- [ ] **Step 4: Run publication tests**

Expected: valid fixture PASS; malformed and protected fixture errors match user-facing categories.

- [ ] **Step 5: Commit**

```bash
git add PureVoice/Features/Reader PureVoiceTests
git commit -m "feat: open EPUB publications with Readium"
```

### Task 9: Visual Reader, Progress, and VoiceOver Navigation

**Files:**
- Create: `PureVoice/Features/Reader/ReaderView.swift`
- Create: `PureVoice/Features/Reader/EPUBNavigatorController.swift`
- Create: `PureVoice/Features/Reader/ReaderToolbar.swift`
- Create: `PureVoice/Features/Reader/ReaderViewModel.swift`
- Test: `PureVoiceTests/ReaderViewModelTests.swift`
- Test: `PureVoiceUITests/ReaderAccessibilityUITests.swift`

- [ ] **Step 1: Write failing progress and UI tests**

Assert locator restoration, throttled progress persistence, chapter-title focus after opening, labelled previous/next page actions, directory access, and labelled reading/listening/settings toolbar buttons.

- [ ] **Step 2: Verify failures**

Expected: FAIL because reader components are absent.

- [ ] **Step 3: Implement Readium navigation and native overlay controls**

Create `EPUBNavigatorViewController(publication:initialLocation:config:)` with persisted `EPUBPreferences`. Wrap it in `UIViewControllerRepresentable`. Use Readium delegates to save locators and chapter changes. Render the Stitch paper-reading appearance through Readium preferences and native toolbars, not by wrapping the Stitch HTML.

Expose page turns as `.accessibilityAction(named: "上一页")` and `.accessibilityAction(named: "下一页")`. When a chapter change completes, post one `.layoutChanged` notification targeting the chapter heading; do not announce every progress update.

- [ ] **Step 4: Run tests and manual VoiceOver pass**

Expected: automated tests PASS; a tester can open a book, turn pages, open the directory, select a chapter, and return to the shelf without looking at the screen.

- [ ] **Step 5: Commit**

```bash
git add PureVoice/Features/Reader PureVoiceTests PureVoiceUITests
git commit -m "feat: add accessible Readium reader"
```

### Task 10: Apple TTS, Listening Screen, and Remote Controls

**Files:**
- Create: `PureVoice/Features/Speech/SpeechService.swift`
- Create: `PureVoice/Features/Speech/ReadiumSpeechService.swift`
- Create: `PureVoice/Features/Speech/ListeningViewModel.swift`
- Create: `PureVoice/Features/Speech/ListeningView.swift`
- Create: `PureVoice/Features/Speech/MiniPlayerView.swift`
- Create: `PureVoice/Features/Speech/RemoteCommandController.swift`
- Test: `PureVoiceTests/ListeningViewModelTests.swift`
- Test: `PureVoiceTests/RemoteCommandControllerTests.swift`
- Test: `PureVoiceUITests/ListeningAccessibilityUITests.swift`

- [ ] **Step 1: Write failing speech-state tests**

Use a fake `SpeechService` to assert start-from-current-locator, pause/resume, previous/next utterance, rate changes, voice persistence, interruption recovery, mini-player visibility, and exactly one spoken-state announcement per user action.

- [ ] **Step 2: Verify failures**

Expected: FAIL because speech types are absent.

- [ ] **Step 3: Implement Readium speech orchestration**

Wrap `PublicationSpeechSynthesizer` behind `SpeechService`. Treat its delegate state as the single source of truth. Filter `availableVoices` to the publication/default language, sort by quality and gender metadata, and persist the unique voice identifier. Configure `AVAudioSession` for long-form spoken audio and register play, pause, next-track, and previous-track remote commands.

Build the Stitch listening layout with three dominant controls: previous sentence, play/pause, next sentence. Give rate and voice controls native adjustable semantics. Decorative cover art is hidden from VoiceOver when the title is already announced.

- [ ] **Step 4: Run automated and physical-device audio tests**

Expected: unit/UI tests PASS; lock screen, Bluetooth headset, interruption, background, and two-hour playback checks preserve position and do not duplicate sentences.

- [ ] **Step 5: Commit**

```bash
git add PureVoice/Features/Speech PureVoiceTests PureVoiceUITests
git commit -m "feat: add accessible offline listening"
```

### Task 11: Reading and Speech Settings

**Files:**
- Create: `PureVoice/Features/Settings/ReaderPreferences.swift`
- Create: `PureVoice/Features/Settings/PreferencesStore.swift`
- Create: `PureVoice/Features/Settings/SettingsView.swift`
- Test: `PureVoiceTests/PreferencesStoreTests.swift`
- Test: `PureVoiceUITests/SettingsAccessibilityUITests.swift`

- [ ] **Step 1: Write failing preference tests**

Assert defaults, persistence, invalid-value clamping, per-book overrides, system Dynamic Type interaction, and resetting to defaults.

- [ ] **Step 2: Verify failures**

Expected: FAIL because settings types are absent.

- [ ] **Step 3: Implement native controls**

Persist font family, font scale, line height, theme, page/scroll mode, default voice identifier, and speech rate. Use segmented controls for modes, toggles for binary settings, sliders/steppers for numeric settings, and menus for font/voice lists. Do not implement custom drawn controls where native semantics exist.

- [ ] **Step 4: Run tests at all accessibility configurations**

Expected: tests PASS and controls expose label, value, and adjustable trait where appropriate.

- [ ] **Step 5: Commit**

```bash
git add PureVoice/Features/Settings PureVoiceTests PureVoiceUITests
git commit -m "feat: add reader and speech preferences"
```

### Task 12: MOBI License Gate and Conversion Adapter

**Files:**
- Create: `docs/adr/0001-mobi-parser.md`
- Create: `PureVoice/Features/Import/MOBI/MOBIConverter.swift`
- Create: `PureVoice/Features/Import/MOBI/MOBIProtectionDetector.swift`
- Test: `PureVoiceTests/MOBIProtectionDetectorTests.swift`
- Test: `PureVoiceTests/MOBIConverterContractTests.swift`
- Test Resources: `PureVoiceTests/Fixtures/mobi/` containing licensed test fixtures for PalmDOC, MOBI7, KF8, joint MOBI/KF8, DRM marker, and corrupt input

- [ ] **Step 1: Record the non-negotiable decision criteria**

The ADR must require: local conversion, no DRM circumvention, App Store compatible distribution, source-notice compliance, arm64 device build, deterministic EPUB output, bounded memory on a 250 MB input, and extraction of title/author/cover/TOC/images.

- [ ] **Step 2: Build a throwaway libmobi XCFramework spike outside the app target**

Compile libmobi 0.12 for simulator and device, run its fixtures, and document binary size, memory, supported variants, notices, relinking obligations, and counsel decision. Do not merge the library into the shipping target during the spike.

- [ ] **Step 3: Apply the gate**

If legal approves the distribution method, record `Accepted` in the ADR with required notices and artifact delivery. If legal rejects it, record `Rejected`; V1 ships EPUB/TXT while MOBI remains outside the App Store binary until an approved pure-Swift or separately licensed implementation exists. Do not silently replace local conversion with cloud upload.

- [ ] **Step 4: Implement the approved adapter and contract tests**

`MOBIConverter.convert(source:destination:)` must reject protected input before extraction, convert supported variants to the same canonical EPUB contract as TXT, preserve the original, and return typed errors for protected, unsupported, corrupt, out-of-space, and cancelled cases.

- [ ] **Step 5: Commit the ADR and, only when accepted, the adapter**

```bash
git add docs/adr PureVoice/Features/Import/MOBI PureVoiceTests
git commit -m "feat: add approved non-DRM MOBI conversion"
```

### Task 13: Localization, Error Recovery, and App-State Restoration

**Files:**
- Create: `PureVoice/Resources/zh-Hans.lproj/Localizable.strings`
- Create: `PureVoice/Core/Models/UserFacingError.swift`
- Create: `PureVoice/App/AppStateRestorer.swift`
- Modify: import, reader, and speech view models
- Test: `PureVoiceTests/UserFacingErrorTests.swift`
- Test: `PureVoiceTests/AppStateRestorerTests.swift`

- [ ] **Step 1: Write failing mapping and restoration tests**

Cover protected file, corrupt file, unsupported format, encoding failure, out of space, cancellation, Readium opening failure, audio interruption, and process termination during import or playback.

- [ ] **Step 2: Verify failures**

Expected: FAIL because centralized mapping/restoration is absent.

- [ ] **Step 3: Implement one Chinese message and recovery action per error**

Errors must never expose raw framework text. Persist resumable app state after state transitions, resume safe work on launch, and mark non-resumable conversions as failed while preserving originals. Post one accessible announcement for completion or failure; do not narrate every import percentage.

- [ ] **Step 4: Run tests and force-quit scenarios**

Expected: tests PASS; force quitting during import, reading, and listening never loses an existing book or saved position.

- [ ] **Step 5: Commit**

```bash
git add PureVoice/Resources PureVoice/Core PureVoice/App PureVoice/Features PureVoiceTests
git commit -m "feat: add localized recovery and restoration"
```

### Task 14: Accessibility Audit, Performance Gates, and TestFlight Readiness

**Files:**
- Create: `docs/testing/voiceover-core-flows.md`
- Create: `docs/testing/format-fixture-matrix.md`
- Create: `PureVoiceUITests/CoreJourneyUITests.swift`
- Create: `PureVoiceTests/ImportPerformanceTests.swift`
- Create: `PureVoiceTests/LongSpeechStateTests.swift`
- Modify: `README.md`

- [ ] **Step 1: Automate the eight core journeys where platform APIs permit**

Cover continue reading, choose another book, directory jump, page turns, return to shelf, start/pause/resume listening, change rate/voice, and rename/delete. Assert no visible icon-only control lacks an accessibility label.

- [ ] **Step 2: Add performance gates**

Measure a 20 MB TXT import, a 100 MB EPUB open, repeated locator saves, and simulated two-hour speech state transitions. Set baselines after the first physical-device run and fail CI when duration or peak-memory regress by more than 25%.

- [ ] **Step 3: Run the full automated suite**

Run the fixed full test command from this plan.

Expected: `** TEST SUCCEEDED **` with zero failing tests.

- [ ] **Step 4: Complete the physical-device matrix**

Run on one iOS 15-capable device and one current device with VoiceOver, maximum Dynamic Type, Bold Text, Increase Contrast, Reduce Motion, Bluetooth audio, lock screen, incoming call interruption, and low-storage simulation. Record tester, device, OS, result, and issue link for each row.

- [ ] **Step 5: Conduct external accessibility testing**

Distribute through TestFlight to at least three blind users and three low-vision users. No core-journey blocker remains open at release candidate approval.

- [ ] **Step 6: Commit readiness evidence**

```bash
git add docs/testing PureVoiceTests PureVoiceUITests README.md
git commit -m "test: complete V1 accessibility release gates"
```

## Final Verification

1. Run `xcodegen generate` and confirm no uncommitted project drift.
2. Run the full simulator test command and generic build command.
3. Run `git diff --check` and `git status --short`.
4. Confirm the VoiceOver matrix and format fixture matrix are complete.
5. Confirm the MOBI ADR is accepted before exposing MOBI in the document picker or App Store description.
6. Archive with the Release configuration and validate the archive in Xcode Organizer.
