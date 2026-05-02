# MarkMacZip

**MarkMacZip v1.0.0** is a local archive app for macOS. It helps you compress and extract files without uploading anything to a server.

## What You Can Do

- Drag files or folders into the app.
- Create ZIP, 7Z, TAR, TAR.GZ, or GZIP archives.
- Extract ZIP, RAR, 7Z, TAR, TAR.GZ, and GZIP files into the folder you choose.
- Add a password for ZIP and 7Z archive workflows, or password-protected RAR extraction.
- See progress while a job is running.
- Review recent activity with speed, size, and compression details.
- Use light or dark mode.
- Switch between English and Simplified Chinese.

## Privacy

MarkMacZip works on your Mac.

- Your files stay on your device.
- There is no cloud upload.
- There is no analytics tracking.
- There is no account or sign-in.

## Requirements

- macOS 11.6 or newer
- Apple Silicon or Intel Mac

Some archive formats use macOS built-in tools. 7Z support requires a local `7z` or `7zz` command-line tool. RAR extraction requires `unar`, `unrar`, `7z`, or `7zz`. If a required tool is not installed, the app will show a clear message instead of silently failing.

## How To Use

1. Open MarkMacZip.
2. Drop files or folders into the main window, or use **Select File**.
3. Choose an output folder.
4. Pick an archive format if you are compressing.
5. Click **Compress** or **Extract**.

## Format Notes

- ZIP: compress and extract.
- RAR: extract when `unar`, `unrar`, `7z`, or `7zz` is installed.
- 7Z: compress and extract when `7z` or `7zz` is installed.
- TAR: compress and extract.
- TAR.GZ / TGZ: compress and extract.
- GZIP: compresses one file at a time.

## Download

The macOS app is distributed through GitHub Releases:

[Download MarkMacZip](https://github.com/marksui/MacZip/releases)

If macOS says the app cannot be opened because it was downloaded from the internet, right-click the app and choose **Open**.

## Source Code

MarkMacZip is open source:

[github.com/marksui/MacZip](https://github.com/marksui/MacZip)
