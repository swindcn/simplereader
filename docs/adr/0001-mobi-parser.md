# ADR 0001: MOBI Parser and Conversion Gate

- Status: Proposed / Deferred / Pending legal approval
- Date: 2026-07-18
- Owner: PureVoice iOS

## Context

PureVoice V1 needs a reliable offline import path for TXT and EPUB. Product wants MOBI eventually, but MOBI conversion introduces licensing, App Store distribution, DRM, fixture provenance, and memory-risk questions that must be resolved before shipping.

The current primary-source check found:

- `libmobi` describes itself as a C library for Mobipocket/Kindle ebook documents and lists support for PalmDOC/PDB, PRC/MOBI, newer KF8 AZW/AZW3, and AZW4. Source: https://github.com/bfabiszewski/libmobi
- The upstream README states the supported build system is autotools; CMake and Xcode are optional and not regularly tested/updated. Source: https://github.com/bfabiszewski/libmobi
- Upstream `libmobi` license is LGPL, either version 3 or later. GitHub shows LGPL-3.0, and Homebrew lists `LGPL-3.0-or-later`. Sources: https://github.com/bfabiszewski/libmobi and https://formulae.brew.sh/formula/libmobi
- The latest upstream release observed on 2026-07-18 is `v0.12`, released 2024-06-17. Sources: https://github.com/bfabiszewski/libmobi and https://formulae.brew.sh/formula/libmobi

These are engineering observations, not legal advice. Legal counsel must decide whether any proposed iOS/App Store distribution method satisfies LGPL and App Store requirements.

## Decision

MOBI import remains disabled for shipping V1 until legal approval exists. The app must not ship `libmobi`, a `MOBIConverter`, a MOBI parser, or any LGPL binary/source integrated into the application target before that approval.

V1 product behavior while pending:

- The document picker advertises only TXT and EPUB.
- MOBI/AZW/AZW3 files selected through any path are rejected before conversion with a clear pending-approval message.
- TXT and EPUB import behavior remains unaffected.
- No cloud conversion may replace local conversion.
- No DRM circumvention may be implemented.

## Acceptance Criteria For Any Future MOBI Approval

Before changing this ADR to Accepted and enabling a MOBI adapter, the implementation must demonstrate all of the following:

- Local conversion only; no file upload or cloud conversion.
- No DRM circumvention; protected input must be rejected before extraction.
- App Store compatible distribution method approved by counsel.
- Source, notice, license, and relinking obligations approved by counsel.
- arm64 device build, not only macOS or simulator.
- Deterministic canonical EPUB output.
- Bounded memory on a 250 MB input.
- Extraction of title, author, cover, TOC, text, images, and embedded resources needed by the canonical EPUB.
- Typed errors for protected, unsupported, corrupt, out-of-space, and cancelled cases.
- Licensed fixtures or documented fixture provenance for PalmDOC, MOBI7, KF8, joint MOBI/KF8, DRM marker, and corrupt input.

## Spike Results

All spike artifacts were kept outside the app target under `/tmp/purevoice-libmobi-spike-verify-20260718223441` and Xcode DerivedData. No `libmobi` source or binary was added to the app worktree.

### Source Checkout

Commands:

```sh
SPIKE_ROOT="/tmp/purevoice-libmobi-spike-verify-$(date +%Y%m%d%H%M%S)"
mkdir -p "$SPIKE_ROOT"
cd "$SPIKE_ROOT"
git clone --depth 1 --branch v0.12 https://github.com/bfabiszewski/libmobi.git
cd libmobi
git rev-parse HEAD
git describe --tags --always
```

Observed:

- Commit: `85dcfe803fc2a21020ddcf15c3eb66b93d388add`
- Tag: `v0.12`

### iOS Simulator / Device-Style Build Attempts

Command:

```sh
cd /tmp/purevoice-libmobi-spike-verify-20260718223441/libmobi
xcodebuild -list -project mobi.xcodeproj
xcodebuild build -project mobi.xcodeproj -scheme mobi -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Observed:

- Xcode project schemes: `mobi`, `mobidrm`, `mobimeta`, `mobitool`.
- iOS Simulator build failed because the `mobi` scheme exposes only macOS destinations. No simulator binary was produced.

Command:

```sh
cd /tmp/purevoice-libmobi-spike-verify-20260718223441/libmobi
./autogen.sh
SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
mkdir -p /tmp/purevoice-libmobi-spike-verify-20260718223441/build-sim-arm64
cd /tmp/purevoice-libmobi-spike-verify-20260718223441/build-sim-arm64
../libmobi/configure --host=arm-apple-darwin --disable-shared --enable-static --without-libxml2 --without-zlib CC="$(xcrun --sdk iphonesimulator --find clang)" CFLAGS="-arch arm64 -isysroot $SIM_SDK -mios-simulator-version-min=15.0" LDFLAGS="-arch arm64 -isysroot $SIM_SDK -mios-simulator-version-min=15.0"
make -j"$(sysctl -n hw.ncpu)"
```

Observed:

- `./autogen.sh` failed because `autoreconf` was not installed.
- No autotools iOS simulator or device binary was produced.

Command:

```sh
cmake --version
```

Observed:

- `cmake` was not installed, so the optional CMake iOS route was not available.

### macOS-Only Xcode Datapoint

Command:

```sh
cd /tmp/purevoice-libmobi-spike-verify-20260718223441/libmobi
xcodebuild build -project mobi.xcodeproj -scheme mobi -destination 'generic/platform=macOS' -configuration Release CODE_SIGNING_ALLOWED=NO
```

Observed:

- The macOS build failed because `src/config.h` includes generated `../config.h`, which was absent.
- No macOS binary-size datapoint was recorded from this verification run.
- No iOS device or simulator XCFramework slice was produced.
- Therefore no App Store-ready XCFramework was demonstrated.

### Fixture / Extraction Check

Command:

```sh
cd /tmp/purevoice-libmobi-spike-verify-20260718223441/libmobi
find tests -maxdepth 3 -type f | sort
find . -maxdepth 3 \( -iname '*.mobi' -o -iname '*.azw' -o -iname '*.azw3' -o -iname '*.prc' -o -iname '*.pdb' \) -print | sort
```

Observed:

- Upstream includes sample MOBI fixtures such as `sample-textread.mobi`, `sample-ncx.mobi`, `sample-multimedia.mobi`, `sample-unicode-uncompressed.mobi`, and DRM samples.
- These fixtures are useful for upstream spike behavior but are not yet approved as app test fixtures. Provenance/license review is still required before copying any fixture into this repo.

No extraction command was run in this verification pass because neither the library nor `mobitool` built from the available local Xcode/autotools routes. Extraction capability, deterministic EPUB output, bounded memory, all required variants, and legal suitability remain unproven.

## Consequences

- Shipping V1 supports TXT and EPUB only.
- MOBI remains visible in internal model/storage only where needed for future compatibility or existing metadata tests, but not enabled for import or conversion.
- Legal review is an external blocker for MOBI.
- A future approved implementation should land in a separate task with contract tests and licensed fixtures before any user-facing enablement.
