# MacZip (MyArchive)

MacZip is a macOS-first archive tool with:
- a C++ core library (`ArchiveCore`) for packing and unpacking
- a CLI (`myarchive-cli`)
- a SwiftUI GUI target (`MyArchiveGUI`) built via Swift Package Manager

## Requirements

- macOS 12 or newer (from `Package.swift`)
- Xcode 15+ or recent Swift 5.10 toolchain
- OpenSSL and zlib development libraries

Homebrew setup:

```bash
brew install openssl@3 zlib
```

## Project Layout

- `Package.swift`: SwiftPM manifest and targets
- `Sources/ArchiveCore`: C++ archive implementation
- `Sources/ArchiveBridge`: C bridge for archive core
- `Sources/MyArchiveCLI`: command-line app
- `Sources/MyArchiveGUI`: SwiftUI GUI app entry and views
- `MarkMacZip/`: alternate SwiftUI app source set (not wired as a SwiftPM target)
- `scripts/smoke_test_cli.sh`: end-to-end CLI smoke test
- `scripts/package_app_macos.sh`: packages `MyArchiveGUI` as `.app`

## Build

From repo root:

```bash
cd MacZip
swift build
```

Build specific products:

```bash
swift build -c release --product myarchive-cli
swift build -c release --product MyArchiveGUI
```

## Run

CLI help:

```bash
.build/debug/myarchive-cli --help
```

Release binary:

```bash
.build/release/myarchive-cli --help
```

Run GUI executable directly after building:

```bash
.build/release/MyArchiveGUI
```

## Package macOS App Bundle

Create `dist/MyArchive.app`:

```bash
chmod +x scripts/package_app_macos.sh
./scripts/package_app_macos.sh
```

Output:
- `dist/MyArchive.app`

## CLI Smoke Test

```bash
chmod +x scripts/smoke_test_cli.sh
./scripts/smoke_test_cli.sh
```

This verifies pack/unpack behavior by creating test input, archiving it, extracting it, and diffing results.

## Notes

- The packaging script bundles Swift runtime libraries and attempts ad-hoc signing.
- If OpenSSL is installed via Homebrew, packaging/build scripts automatically export `PKG_CONFIG_PATH`, `CPPFLAGS`, and `LDFLAGS`.
- `MarkMacZip/` files are present in the repo but are currently separate from the active SwiftPM GUI target in `Sources/MyArchiveGUI`.
