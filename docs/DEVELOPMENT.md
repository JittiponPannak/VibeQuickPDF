# Development & Build Guide

This guide documents the exact toolchain, dependencies, build commands, tests, and known caveats for **VibeQuickPDF** (`v1.3.2`) so anyone cloning or forking this archived repository can reproduce builds reliably.

---

## 1. Verified Toolchain Versions

| Component | Version | Source |
| :--- | :--- | :--- |
| Flutter SDK | `3.47.9` (`stable` channel, rev `6b182d2c75`) | `.metadata` & commit `a152851` |
| Dart SDK | `^3.11.4` | `pubspec.yaml` |
| Android Gradle Plugin (AGP) | `9.1.0` | `android/settings.gradle.kts` |
| Gradle Wrapper | `9.3.1` | `android/gradle/wrapper/gradle-wrapper.properties` |
| Kotlin Android Plugin | `2.4.0` | `android/settings.gradle.kts` |
| Java / JVM Target | `Java 17` (`JVM_17`) | `android/app/build.gradle.kts` |
| App Version | `1.3.2+1` | `pubspec.yaml` |
| Android Application ID | `com.jittiponpannak.vibe_quick_pdf` | `android/app/build.gradle.kts` |

---

## 2. Key Dependencies

Defined in [`pubspec.yaml`](../pubspec.yaml):

| Package | Version | Role |
| :--- | :--- | :--- |
| `pdf` | `^3.12.0` | Pure-Dart PDF generation from image bytes |
| `archive` | `^4.3.0` | Decoding shared archives (`.zip`, `.tar`, `.gz`) and encoding ZIP exports |
| `image_picker` | `^1.2.3` | Camera capture and multi-image gallery picking |
| `flutter_sharing_intent` | `^2.0.4` | Receiving images and archives shared from external apps |
| `share_plus` | `^13.2.1` | Invoking the OS share sheet and checking `ShareResultStatus` |
| `open_filex` | `^5.0.0` | Opening saved files and temporary preview PDFs |
| `path_provider` | `^2.1.6` | Resolving application documents and temporary cache directories |
| `path` | `^1.9.1` | Cross-platform file path and extension helpers |
| `intl` | `^0.20.3` | Locale-aware date formatting on the Home screen |
| `package_info_plus` | `^10.2.1` | Displaying the live version string in the Home AppBar |
| `flutter_launcher_icons` *(dev)* | `^0.14.4` | Generating Android (`launcher_icon`) and iOS app icons from `assets/icon.png` |
| `flutter_lints` *(dev)* | `^6.0.0` | Static analysis lint rules (`analysis_options.yaml`) |

---

## 3. Common Commands

### Install Dependencies
```bash
flutter pub get
```

### Run Static Analysis
```bash
flutter analyze
```

### Run on a Device / Emulator
```bash
flutter run
```

### Build Split Release APKs (Android)
```bash
flutter build apk --split-per-abi
```
Output APKs are written to `build/app/outputs/flutter-apk/`. On Windows, running [`build.bat`](../build.bat) runs this command and opens the output directory in Explorer.

### Regenerate App Launcher Icons
If you replace `assets/icon.png`:
```bash
dart run flutter_launcher_icons
```

---

## 4. Test Suite

Run all automated tests with:
```bash
flutter test
```

| Test File | Coverage |
| :--- | :--- |
| [`test/widget_test.dart`](../test/widget_test.dart) | Thai/English localization, Home screen centered header & overflow menu (Refresh/Theme/Language), Conversion screen empty hub, page reordering & reorder modal, Export Format PDF/ZIP switching, and `SharedMediaDialog` options (Append / Create New / Quick PDF & Share). |
| [`test/file_registry_test.dart`](../test/file_registry_test.dart) | Private registry isolation (ignoring unregistered files in `VibeQuickPDF/`), saving & registering, Android MethodChannel mocks (`saveToDocuments`, `pickPdfFile`, `inspectUri`, `deleteUri`), SAF duplicate import blocking across differing URIs, and HomeScreen UI flows for generated vs. imported file deletion. |
| [`test/archive_service_test.dart`](../test/archive_service_test.dart) | Image/archive extension detection and ZIP creation (multi-image numbered naming and single-image naming). |
| [`test/archive_extract_test.dart`](../test/archive_extract_test.dart) | Archive extraction filtering (excluding non-images and `__MACOSX` metadata) and alphabetical sorting. |
| [`test/preview_test.dart`](../test/preview_test.dart) | Temporary preview PDF creation, preview modal display, and cleanup on dismissal. **Note:** Marked `skip: true` by default to prevent hanging during headless CLI test runs. |

---

## 5. Known Limitations & Notes for Future Forks

Because this project is archived at `v1.3.2`, the following design choices and limitations are documented as-is:

1. **Android Release Signing**: `android/app/build.gradle.kts` configures `buildTypes.release` to use `signingConfigs.getByName("debug")`. If publishing to Google Play or distributing production builds, configure a real release keystore.
2. **Android-Only Native Features**: `Import PDF From File` (SAF), public `Documents/VibeQuickPDF/` MediaStore storage, and OS Share-In intent filters are implemented for Android only. On iOS, `Info.plist` does not yet configure Share Extensions or camera/photo usage descriptions beyond the default Flutter template.
3. **In-Memory Theme & Locale State**: `appThemeModeNotifier` and `appLocaleNotifier` are not persisted to disk (`SharedPreferences`), so manual theme/language overrides reset to system defaults when the app restarts.
4. **Archive Decoding Formats**: `ArchiveService._archiveExtensions` recognizes `.bz2`, `.tbz2`, and `.xz` in addition to `.zip`, `.tar`, `.gz`, and `.tgz`, while `extractImagesFromArchive()` explicitly decodes `.zip`, `.tar.gz`/`.tgz`, `.tar`, and `.gz` (falling back to ZIP/TAR decoding for other extensions).
5. **Unused Legacy Widget**: `lib/widgets/theme_toggle_button.dart` remains in the repository as a reusable widget after the theme toggle was moved into the Home Screen overflow menu in `v1.3.0a`.
6. **Generated Reports**: `android/build/reports/problems/problems-report.html` was committed in an earlier build and can safely be ignored or removed in a fork.
