# MarkMacZip

MarkMacZip is an open-source, local-only archive utility for macOS.

It is designed for two audiences:
- End users who want a clean, reliable app for compressing and extracting files.
- Interviewers/reviewers who want to evaluate product thinking, engineering tradeoffs, and implementation quality.

---

## 1) Product Overview

MarkMacZip focuses on practical daily workflows:
- Drag files/folders into the app.
- Choose output location and archive format.
- Compress or extract with visible progress.
- Review operation history with performance metrics.

### Core product principles
- **Local-first**: no cloud upload, no analytics pipeline.
- **Minimal UI**: clear states, low cognitive load.
- **Operational transparency**: status + activity metrics after each task.

---

## 2) Features

### Archive formats
- ZIP
- 7Z (requires local 7z/7zz binary)
- TAR
- TAR.GZ / TGZ
- GZIP

### UX capabilities
- Light/Dark theme
- English / Simplified Chinese
- Adjustable UI font scale
- Settings popover + About popover
- Copyable status text

### Workflow helpers
- Remove individual selected files
- Editable output archive name (default: `Archive`)
- Output folder auto-suggestion from last selected item
- Delete entries in Recent Activity

### Activity metrics (per operation)
- Latency (seconds)
- Throughput (MB/s)
- Approximate CPU usage (%)
- Compression ratio + input/output sizes

---

## 3) Compatibility

- **OS**: macOS 11.6+
- **CPU**: Apple Silicon and Intel
- **UI stack**: SwiftUI (macOS app)
- **Execution model**: local process invocation (`zip`, `tar`, `unzip`, `ditto`, `gzip`, optional `7z/7zz`)

---

## 4) Security & Privacy Model

MarkMacZip intentionally keeps a narrow trust boundary:
- Files are processed locally on the machine.
- No telemetry endpoint, no user analytics service, no remote processing.
- No password cracking/brute-force features.

Password support is limited to legitimate archive operations (ZIP/7Z workflows).

---

## 5) Project Structure

```text
MarkMacZip/MarkMacZip/MarkMacZipApp.swift
MarkMacZip/MarkMacZip/ContentView.swift
MarkMacZip/MarkMacZip/HistoryStore.swift
MarkMacZip/MarkMacZip/FilePicker.swift
MarkMacZip/MarkMacZip/ArchiveService.swift
MarkMacZip/MarkMacZip/Models.swift
MarkMacZip/Products/MarkMacZip.app
docs/index.html
```

### Key modules
- `ContentView.swift`
  - Main UI + view model orchestration
  - Selection, operation triggers, progress updates, status handling
- `ArchiveService.swift`
  - Compression/extraction engine
  - Format-specific command routing
  - Progress parsing and operation result reporting
- `Models.swift`
  - Domain models, localization strings, format definitions
- `HistoryStore.swift`
  - In-memory history records and mutation helpers
- `docs/index.html`
  - Public project landing page (GitHub Pages)

---

## 6) Running the App

### In Xcode
1. Open `MarkMacZip.xcodeproj`
2. Select app target/scheme
3. Build and run

### Optional dependency for 7Z
Install one of these executables in common local paths:
- `7zz`
- `7z`

If unavailable, 7Z-specific actions are disabled/fail gracefully with a clear message.

---

## 7) Format Notes / Known Limitations

- **GZIP compression** supports a single file input only.
- **7Z support** depends on local binary availability.
- Progress precision varies by backend command output granularity.
- CPU usage is an approximate process-level delta, not a profiler-grade metric.

---

## 8) Interviewer Notes (Engineering Rationale)

This project demonstrates:
- **Product framing**: minimal experience for non-technical users while still exposing meaningful metrics.
- **Pragmatic architecture**: native SwiftUI UI + command-line backend orchestration instead of heavy third-party archive SDKs.
- **Reliability-minded behavior**:
  - Multi-format command routing
  - Format-specific guardrails (e.g., GZIP single-file constraint)
  - Error propagation into user-facing status/history
- **Operational visibility**:
  - progress states
  - post-operation metrics
  - explicit failure surfaces
- **Localization/theming discipline**:
  - centralized string model
  - persisted app settings

---

## 9) Website / Portfolio Page

`docs/index.html` is prepared for GitHub Pages and includes:
- Product narrative
- SoC-performance framing
- EN/简体中文 switch
- Download + GitHub CTA placeholders

Replace placeholder links before publishing:
- `YOUR_DOWNLOAD_LINK_HERE`
- `YOUR_GITHUB_RELEASES_LINK_HERE`

---

## 10) Roadmap (Practical Next Steps)

- Cancelable operations (safe process termination + UI state recovery)
- Archive content preview before extraction
- Batch queue with retry and structured result export

---

## License

Open source. Add your preferred license file (MIT/Apache-2.0/etc.) if not already included.
