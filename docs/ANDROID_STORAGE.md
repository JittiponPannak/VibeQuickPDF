# Android Storage & Native Bridge

On Android, VibeQuickPDF uses a custom Kotlin `MethodChannel` inside [`MainActivity.kt`](../android/app/src/main/kotlin/com/jittiponpannak/quick_vibe_pdf/MainActivity.kt) to integrate cleanly with Android Scoped Storage (`MediaStore`) and the Storage Access Framework (SAF) without broad storage permissions.

> **Path note:** `MainActivity.kt` resides at `android/app/src/main/kotlin/com/jittiponpannak/quick_vibe_pdf/MainActivity.kt`, while its Kotlin package, Android `namespace`, and `applicationId` are `com.jittiponpannak.vibe_quick_pdf`.

---

## 1. MethodChannel Contract

**Channel Name:** `com.jittiponpannak.vibe_quick_pdf/storage`

| Method | Arguments | Return Value | Purpose |
| :--- | :--- | :--- | :--- |
| `saveToDocuments` | `fileName: String`, `extension: String`, `bytes: Uint8List` | `Map { path, name, size, createdAt }` | Writes a PDF or ZIP into `Documents/VibeQuickPDF/` with automatic collision renaming (`_1`, `_2`, ...). |
| `pickPdfFile` | *(none)* | `Map { path, name, size, createdAt }` or `null` | Launches `Intent.ACTION_OPEN_DOCUMENT` filtered to `application/pdf`, takes persistable read permission, and returns URI metadata. |
| `findMatchingRegisteredPath` | `uri: String`, `registeredPaths: List<String>` | `String?` (matched registered path) | Runs on a background thread (`ioExecutor`) to determine whether a newly picked SAF URI refers to a file already in the registry. |
| `inspectUri` | `uri: String` | `Map { name, size, createdAt }` or `null` | Verifies the `content://` URI can be opened for reading and returns current metadata. Returns `null` if missing or revoked. |
| `openUri` | `uri: String`, `mimeType: String` | `bool` | Launches `Intent.ACTION_VIEW` with `FLAG_GRANT_READ_URI_PERMISSION`. |
| `copyUriToTempFile` | `uri: String`, `fileName: String` | `String?` (temp file path) | Copies a `content://` URI into `<cacheDir>/share_cache/<safeName>` so `share_plus` can share it reliably. |
| `deleteUri` | `uri: String` | `bool` | Deletes a SAF document via `DocumentsContract.deleteDocument` or a MediaStore entry via `contentResolver.delete`. |

---

## 2. Saving to `Documents/VibeQuickPDF/`

### Android 10+ (API 29+, Scoped Storage)
- Inserts a pending row into `MediaStore.Files.getContentUri("external")` with:
  - `RELATIVE_PATH = "Documents/VibeQuickPDF"`
  - `DISPLAY_NAME = <unique name>` (checked via `mediaStoreFileExists`, appending `_1`..`_9999` on collision)
  - `MIME_TYPE = "application/pdf"` or `"application/zip"`
  - `IS_PENDING = 1` while writing, updated to `IS_PENDING = 0` on completion.
- If writing fails, the incomplete MediaStore row is deleted immediately.
- No runtime storage permission is required on Android 10+.
- Returns the `content://media/...` URI string as `path`.

### Android 9 and Below (API ≤ 28)
- Checks `Manifest.permission.WRITE_EXTERNAL_STORAGE` (declared with `android:maxSdkVersion="28"` in `AndroidManifest.xml`), requesting it at runtime if not yet granted.
- Writes directly to `Environment.getExternalStoragePublicDirectory(DIRECTORY_DOCUMENTS)/VibeQuickPDF/` with `_1`, `_2` collision handling.
- Triggers `MediaScannerConnection.scanFile()` so the file appears immediately in file managers.
- Returns the absolute filesystem path as `path`.

---

## 3. Importing External PDFs & Deduplication

When the user taps **Import PDF From File**, `MainActivity.kt` launches `ACTION_OPEN_DOCUMENT` (`application/pdf`) with `FLAG_GRANT_READ_URI_PERMISSION | FLAG_GRANT_PERSISTABLE_URI_PERMISSION` and attempts `contentResolver.takePersistableUriPermission()` so access survives app restarts.

### Multi-Stage Duplicate Detection
Android often exposes the exact same file under different URIs depending on how it was created or picked—for example:
- Exported via MediaStore: `content://media/external/file/99`
- Picked via SAF External Storage: `content://com.android.externalstorage.documents/document/primary%3ADocuments%2FVibeQuickPDF%2FExported.pdf`
- Picked via OEM / third-party file manager provider

To prevent duplicate entries in the Home list, `FileService.importPdfFromFile()` first checks exact URI equality in Dart, then delegates to `findMatchingRegisteredPathSync()` on Android's background `ioExecutor`:

1. **Fast Identity Resolution (`resolveFileIdentity`)** — Extracts as many identifiers as possible from each path/URI:
   - **MediaStore `_ID`**: Parsed from `content://media/...`, `com.android.providers.media.documents`, `msf:` downloads IDs, or via `MediaStore.getMediaUri()` (Android 10+).
   - **Canonical File Path**: Resolved from `file://`, raw paths, `primary:` external storage document IDs, `raw:` IDs, or MediaStore `DATA` / `RELATIVE_PATH + DISPLAY_NAME`.
   - **Primary Relative Path**: Normalized lowercase path relative to primary external storage root (e.g., `documents/vibequickpdf/exported.pdf`).
2. **Fast Match Pass**: Matches if any registered entry shares the same `mediaId`, `filePath`, or `relativePath`.
3. **SHA-256 Content Hash Fallback**: If no fast match succeeds, filters registered entries with the exact same non-zero byte `size` and compares streaming `SHA-256` hashes (`8 KB` buffer).

If a match is found, `ImportPdfStatus.alreadyRegistered` is returned and the user is notified via snackbar.

---

## 4. Android Manifest Permissions & Intent Filters

Defined in [`android/app/src/main/AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml):

### Permissions
- `READ_EXTERNAL_STORAGE` (`maxSdkVersion="32"`)
- `WRITE_EXTERNAL_STORAGE` (`maxSdkVersion="28"`)

### Launch Mode & Intent Filters
`MainActivity` uses `android:launchMode="singleTask"` so incoming shares route cleanly into the running app instance:
- `ACTION_SEND` & `ACTION_SEND_MULTIPLE` for `image/*`
- `ACTION_SEND` & `ACTION_SEND_MULTIPLE` for archives:
  - `application/zip`, `application/x-zip-compressed`, `application/x-zip`
  - `application/x-tar`, `application/gzip`, `application/x-gzip`
  - `application/octet-stream`
- `ACTION_VIEW` (`content://` and `file://` schemes) for `application/zip` and `application/x-zip-compressed`

---

## 5. Platform Capability Matrix

| Capability | Android | iOS / Desktop / Web |
| :--- | :--- | :--- |
| Convert images to PDF / ZIP (Merge & Split) | Full support | Supported (where `image_picker` / `dart:io` are supported) |
| Save location | Public `Documents/VibeQuickPDF/` | Private `<AppDocuments>/VibeQuickPDF/` |
| Private file registry (`vibe_pdf_registry.json`) | Full support | Full support |
| Import PDF From File (SAF) | Full support | Unsupported (`ImportPdfStatus.unsupported`) |
| Incoming Share Intents & Archive Extraction | Configured in `AndroidManifest.xml` | Not configured natively |
| Temporary PDF Preview & Auto-Cleanup | Full support | Supported via `open_filex` |
| Dark Mode & Thai/English Switching | Full support | Full support |
