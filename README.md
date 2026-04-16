# EasyArchive

EasyArchive is a small native macOS utility for people who just want to zip or unzip files without learning technical tools.

It is:
- macOS only
- offline only
- local-only with no network, login, analytics, or cloud features
- built with SwiftUI and standard macOS system tools

## Project structure

The main app lives in the `EasyArchive/` folder:

- `EasyArchiveApp.swift`
- `ContentView.swift`
- `ArchiveService.swift`
- `FilePicker.swift`
- `Models.swift`
- `HistoryStore.swift`

The Xcode project is:

- `EasyArchive.xcodeproj`

## How to open in Xcode

1. Open `EasyArchive.xcodeproj` in Xcode on macOS.
2. Select the `EasyArchive` scheme.
3. Choose a macOS run destination such as `My Mac`.
4. Press `Run`.

## How to run

1. Launch the app from Xcode.
2. Drag files or folders into the large center drop area, or click `Select File`.
3. Click `Choose Output Folder`.
4. Click `Extract` for `.zip` files or `Compress` for files and folders.
5. Read the status message at the bottom for success or error details.

## Current supported formats

- Extract: `.zip`
- Compress: `.zip`

## MVP behavior

- Drag and drop files or folders into the main window
- Choose files and folders from Finder
- Extract `.zip` archives into a new output folder
- Compress selected files or folders into a `.zip` archive
- Prevent accidental overwrite by appending `copy`, `copy 2`, and so on
- Show status text and friendly success or error messages
- Keep a simple recent activity list in app state for the current app session

## Sample user flow

Example 1: Unzip photos from a school email

1. Open EasyArchive.
2. Drag `photos.zip` into the window.
3. Click `Choose Output Folder` and pick `Desktop`.
4. Click `Extract`.
5. EasyArchive creates a new folder like `photos` or `photos copy` on the Desktop.

Example 2: Create one zip file from a folder

1. Open EasyArchive.
2. Drag a folder such as `Tax Documents`.
3. Choose an output folder.
4. Click `Compress`.
5. EasyArchive creates `Tax Documents.zip` or a safe copied name if that file already exists.

## Localization note

The UI strings are centralized in code so they are easier to move into localization files later, including Chinese text support.

## Future improvement ideas

- Batch extract multiple zip files with per-item progress
- Quick action to extract into the same folder as the archive
- Quick action to compress directly to the Desktop
- Preview archive contents before extraction
- Keyboard shortcuts and menu commands
- Persistent history between launches
- Better progress reporting for long operations
- Expanded format support beyond ZIP

## Notes

- The app uses native macOS panels plus `Process` to call standard system archive tools in a controlled way.
- This repo may also contain older packaging or archive experiments, but `EasyArchive.xcodeproj` is the project to open for this MVP.
