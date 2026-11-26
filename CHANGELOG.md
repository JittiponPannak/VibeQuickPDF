# Changelog

All notable changes to **VibeQuickPDF** are documented in this file.  
The project is considered finished and archived at **v1.3.2**.

---

## [1.3.2] — 2026-11-10

### Added
- **Public Documents Storage**: Saved PDF and ZIP files on Android are now written to `Documents/VibeQuickPDF/` via `MediaStore` (Android 10+) or legacy external storage (Android ≤9) instead of app-private storage.
- **Private File Registry (`vibe_pdf_registry.json`)**: Home screen now displays files tracked in a private JSON registry rather than scanning directories, with automatic one-time migration from the legacy `VibePDFs/` folder.
- **Import PDF From File**: Added an Android Storage Access Framework (`ACTION_OPEN_DOCUMENT`) picker in the Home screen menu to register existing external PDFs into the app's list, marked with an *Imported* badge.
- **Safe Delete for Imported PDFs**: Deleting an imported file now offers a choice between *Remove from List* (unregister only) and *Delete File* (delete from device storage and unregister).
- **Duplicate Import Prevention**: Prevented importing PDFs that are already registered—even when picked via a different SAF/OEM URI—using MediaStore ID, canonical/relative path, and size + SHA-256 hash matching.
- **Registry Unit & Widget Tests**: Added `test/file_registry_test.dart`.

### Changed
- **Android Build Toolchain Upgrade**: Updated Android Gradle setup for Flutter `3.47.9` (Gradle `9.3.1`, AGP `9.1.0`, Kotlin `2.4.0`, Java 17) and removed the redundant explicit `kotlin-android` plugin declaration in `android/app/build.gradle.kts`.
- Updated AI model usage table in `README.md` (`v1.3.0 – v1.3.2` using Gemini 3.8 Flash).

---

## [1.3.1] — 2026-10-09

### Added
- **Quick PDF & Share (on Incoming Share)**: Reintroduced one-tap Quick PDF generation as a third option in the shared media bottom sheet, immediately converting received images to PDF and launching the system share sheet without opening the editor.
- Updated dependencies (`pubspec.yaml` / `pubspec.lock`).

---

## [1.3.0a] — 2026-10-04

### Added
- **Temporary PDF Preview**: Added a *Preview* button in the conversion screen that builds a temporary PDF, opens it via the system viewer, and automatically deletes the temporary file once the preview modal is dismissed or the screen closes (`test/preview_test.dart`).
- **Dark Mode**: Added Light, Dark, and System theme support across the app.
- **ZIP Export & Archive Extraction**:
  - Added an **Export Format** dropdown (`PDF` / `ZIP`) above the merge switch on the conversion screen, supporting both merged and split ZIP archives.
  - Added automatic image extraction when receiving archive files (`.zip`, `.tar`, `.tar.gz`, `.tgz`, `.gz`) via Android share intents (`ArchiveService`, `test/archive_service_test.dart`, `test/archive_extract_test.dart`).
- **Enhanced Page Reordering & Shared Media Flow**: Added drag-and-drop grid reordering, tap-to-reorder modal, and a unified shared media bottom sheet (Append / Create New).

### Changed
- Consolidated the Home screen AppBar actions (Refresh, Theme toggle, Language switcher) into a single overflow popup menu (`Icons.more_vert`) and centered the app title/version header.
- Removed the legacy in-screen Quick PDF toggle switch on the conversion screen.

---

## [1.2.2] — 2026-08-11

### Added
- Finalized camera capture buttons, launcher icons (`assets/icon.png`, `assets/icon.svg`, Android/iOS mipmaps), and MIT License (`LICENSE`).
- Changed Android package ID / namespace to `com.jittiponpannak.vibe_quick_pdf` (commit `91dd580` shortly after tag `1.2.2`).

---

## [1.2.1] — 2026-08-11

### Added
- Added a prompt for handling PDF creation when images are shared from external apps.
- Added camera photo capture options alongside gallery selection.
- Updated project metadata and dependencies.

---

## [1.1.0] — 2026-08-07

### Added
- **Quick Create & Export PDF**: Initial implementation of fast PDF creation and sharing.
- **Share Verification & Retry**: Upgraded to `SharePlus` and added a retry dialog when sharing does not report success.
- **Visible Version Display**: Displayed the app version number in the Home screen header (`package_info_plus`).
- Added initial screenshots and expanded `README.md`.

---

## [1.0.0] — 2026-07-20

### Added
- Initial release of **VibeQuickPDF**.
- Multi-image selection, merge/split PDF generation (`pdf` package), local file listing, opening, sharing, and deleting.
- Thai and English localization support.
