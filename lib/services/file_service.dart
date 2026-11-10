import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/pdf_file.dart';

enum ImportPdfStatus {
  imported,
  alreadyRegistered,
  cancelled,
  unsupported,
  error,
}

class ImportPdfResult {
  final ImportPdfStatus status;
  final PdfFile? file;
  final String? errorMessage;

  const ImportPdfResult._({
    required this.status,
    this.file,
    this.errorMessage,
  });

  factory ImportPdfResult.imported(PdfFile file) =>
      ImportPdfResult._(status: ImportPdfStatus.imported, file: file);

  factory ImportPdfResult.alreadyRegistered(PdfFile file) =>
      ImportPdfResult._(status: ImportPdfStatus.alreadyRegistered, file: file);

  const factory ImportPdfResult.cancelled() = ImportPdfResult._cancelled;

  const factory ImportPdfResult.unsupported() = ImportPdfResult._unsupported;

  factory ImportPdfResult.error(String message) =>
      ImportPdfResult._(status: ImportPdfStatus.error, errorMessage: message);

  const ImportPdfResult._cancelled() : status = ImportPdfStatus.cancelled, file = null, errorMessage = null;
  const ImportPdfResult._unsupported() : status = ImportPdfStatus.unsupported, file = null, errorMessage = null;
}

class FileService {
  static const MethodChannel _storageChannel =
      MethodChannel('com.jittiponpannak.vibe_quick_pdf/storage');
  static const String _registryFileName = 'vibe_pdf_registry.json';
  static const String _documentsSubfolder = 'VibeQuickPDF';
  static const String _legacySubfolder = 'VibePDFs';

  final bool? _isAndroidOverride;

  FileService({bool? isAndroid}) : _isAndroidOverride = isAndroid;

  bool get _isAndroid => _isAndroidOverride ?? Platform.isAndroid;

  bool _isContentUri(String path) => path.startsWith('content://');

  Future<File> get _registryFile async {
    final appDocs = await getApplicationDocumentsDirectory();
    return File(p.join(appDocs.path, _registryFileName));
  }

  Future<String> get _fallbackDocumentsPath async {
    final directory = await getApplicationDocumentsDirectory();
    final pdfDirectory = Directory(p.join(directory.path, _documentsSubfolder));
    if (!(await pdfDirectory.exists())) {
      await pdfDirectory.create(recursive: true);
    }
    return pdfDirectory.path;
  }

  Future<List<PdfFile>> _readRegistry() async {
    final registryFile = await _registryFile;
    if (await registryFile.exists()) {
      try {
        final raw = await registryFile.readAsString();
        if (raw.trim().isEmpty) return [];
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((item) => PdfFile.fromJson(Map<String, dynamic>.from(item)))
              .where((entry) => entry.path.isNotEmpty)
              .toList();
        }
      } catch (e) {
        debugPrint("Error reading registry: $e");
      }
      return [];
    }

    // One-time migration from legacy private VibePDFs folder if it exists.
    final appDocs = await getApplicationDocumentsDirectory();
    final legacyDir = Directory(p.join(appDocs.path, _legacySubfolder));
    final migrated = <PdfFile>[];
    if (await legacyDir.exists()) {
      try {
        for (final entity in legacyDir.listSync()) {
          if (entity is File &&
              (entity.path.toLowerCase().endsWith('.pdf') ||
                  entity.path.toLowerCase().endsWith('.zip'))) {
            final stat = await entity.stat();
            migrated.add(
              PdfFile(
                name: p.basename(entity.path),
                path: entity.path,
                createdAt: stat.modified,
                size: stat.size,
                isImported: false,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint("Error migrating legacy files: $e");
      }
    }

    await _writeRegistry(migrated);
    return migrated;
  }

  Future<void> _writeRegistry(List<PdfFile> entries) async {
    try {
      final registryFile = await _registryFile;
      if (!(await registryFile.parent.exists())) {
        await registryFile.parent.create(recursive: true);
      }
      final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
      await registryFile.writeAsString(encoded);
    } catch (e) {
      debugPrint("Error writing registry: $e");
    }
  }

  Future<void> _upsertRegistryEntry(PdfFile entry) async {
    final entries = await _readRegistry();
    entries.removeWhere((e) => e.path == entry.path);
    entries.add(entry);
    await _writeRegistry(entries);
  }

  Future<List<PdfFile>> getPdfFiles() async {
    final registered = await _readRegistry();
    final validFiles = <PdfFile>[];
    bool registryChanged = false;

    for (final entry in registered) {
      if (_isContentUri(entry.path)) {
        if (_isAndroid) {
          try {
            final meta = await _storageChannel.invokeMapMethod<String, dynamic>(
              'inspectUri',
              {'uri': entry.path},
            );
            if (meta == null) {
              registryChanged = true;
              continue;
            }
            final updatedName = (meta['name'] as String?) ?? entry.name;
            final updatedSize = (meta['size'] as num?)?.toInt() ?? entry.size;
            final updatedEntry = entry.copyWith(
              name: updatedName,
              size: updatedSize,
            );
            if (updatedEntry.name != entry.name ||
                updatedEntry.size != entry.size) {
              registryChanged = true;
            }
            validFiles.add(updatedEntry);
          } catch (e) {
            debugPrint("Error inspecting content URI ${entry.path}: $e");
            validFiles.add(entry);
          }
        } else {
          validFiles.add(entry);
        }
      } else {
        final file = File(entry.path);
        if (!await file.exists()) {
          registryChanged = true;
          continue;
        }
        final stat = await file.stat();
        final updatedEntry = entry.copyWith(
          name: p.basename(entry.path),
          size: stat.size,
        );
        if (updatedEntry.name != entry.name ||
            updatedEntry.size != entry.size) {
          registryChanged = true;
        }
        validFiles.add(updatedEntry);
      }
    }

    if (registryChanged) {
      await _writeRegistry(validFiles);
    }

    // Sort by newest first
    validFiles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return validFiles;
  }

  Future<String> savePdf(String fileName, List<int> bytes) =>
      saveFile(fileName, 'pdf', bytes);

  Future<String> saveZip(String fileName, List<int> bytes) =>
      saveFile(fileName, 'zip', bytes);

  /// Creates a temporary PDF file for previewing.
  Future<File> createTempPdf(String fileName, List<int> bytes) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${tempDir.path}/${fileName}_preview_$timestamp.pdf');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<String> saveFile(
    String fileName,
    String extension,
    List<int> bytes,
  ) async {
    final cleanExt =
        extension.startsWith('.') ? extension.substring(1) : extension;

    if (_isAndroid) {
      final result = await _storageChannel.invokeMapMethod<String, dynamic>(
        'saveToDocuments',
        {
          'fileName': fileName,
          'extension': cleanExt,
          'bytes': Uint8List.fromList(bytes),
        },
      );
      if (result == null || result['path'] == null) {
        throw Exception('Failed to save file to Documents/$_documentsSubfolder');
      }

      final savedPath = result['path'] as String;
      final savedName = (result['name'] as String?) ?? '$fileName.$cleanExt';
      final savedSize = (result['size'] as num?)?.toInt() ?? bytes.length;
      final createdAtMs =
          (result['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;

      await _upsertRegistryEntry(
        PdfFile(
          name: savedName,
          path: savedPath,
          createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
          size: savedSize,
          isImported: false,
        ),
      );
      return savedPath;
    }

    final path = await _fallbackDocumentsPath;
    String fullPath = p.join(path, '$fileName.$cleanExt');

    // Check if file exists, append number if it does
    int counter = 1;
    while (await File(fullPath).exists()) {
      fullPath = p.join(path, '${fileName}_$counter.$cleanExt');
      counter++;
    }

    final file = File(fullPath);
    await file.writeAsBytes(bytes);
    final stat = await file.stat();

    await _upsertRegistryEntry(
      PdfFile(
        name: p.basename(fullPath),
        path: fullPath,
        createdAt: stat.modified,
        size: stat.size,
        isImported: false,
      ),
    );
    return fullPath;
  }

  /// Opens the platform document picker for a PDF file and registers it in
  /// the private VibeQuickPDF registry.
  Future<ImportPdfResult> importPdfFromFile() async {
    if (!_isAndroid) {
      return const ImportPdfResult.unsupported();
    }

    try {
      final picked = await _storageChannel.invokeMapMethod<String, dynamic>(
        'pickPdfFile',
      );
      if (picked == null) {
        return const ImportPdfResult.cancelled();
      }

      final uriPath = picked['path'] as String?;
      if (uriPath == null || uriPath.isEmpty) {
        return const ImportPdfResult.cancelled();
      }

      final name = (picked['name'] as String?) ?? 'Imported.pdf';
      final size = (picked['size'] as num?)?.toInt() ?? 0;
      final createdAtMs =
          (picked['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;

      final entries = await _readRegistry();
      final existingIdx = entries.indexWhere((e) => e.path == uriPath);
      if (existingIdx != -1) {
        final existing = entries[existingIdx].copyWith(name: name, size: size);
        entries[existingIdx] = existing;
        await _writeRegistry(entries);
        return ImportPdfResult.alreadyRegistered(existing);
      }

      final newEntry = PdfFile(
        name: name,
        path: uriPath,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
        size: size,
        isImported: true,
      );
      entries.add(newEntry);
      await _writeRegistry(entries);
      return ImportPdfResult.imported(newEntry);
    } catch (e) {
      return ImportPdfResult.error(e.toString());
    }
  }

  Future<bool> sharePdf(
    String path, {
    String? shareText,
    String? fileName,
  }) async {
    String pathToShare = path;
    if (_isContentUri(path) && _isAndroid) {
      final tempPath = await _storageChannel.invokeMethod<String>(
        'copyUriToTempFile',
        {'uri': path, 'fileName': fileName ?? 'document.pdf'},
      );
      if (tempPath == null) return false;
      pathToShare = tempPath;
    }

    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(pathToShare)],
        text: shareText ?? 'สร้างด้วย VibeQuickPDF',
      ),
    );
    return result.status == ShareResultStatus.success;
  }

  /// Shares file bytes via the system share sheet using a temporary file.
  Future<bool> shareBytes(
    List<int> bytes,
    String displayName, {
    String extension = 'pdf',
    String? shareText,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cleanExt =
        extension.startsWith('.') ? extension.substring(1) : extension;
    final tempFile = File('${tempDir.path}/${displayName}_$timestamp.$cleanExt');
    await tempFile.writeAsBytes(bytes);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(tempFile.path)],
        text: shareText ?? 'สร้างด้วย VibeQuickPDF',
      ),
    );
    return result.status == ShareResultStatus.success;
  }

  /// Shares PDF bytes via the system share sheet using a temporary file.
  Future<bool> sharePdfBytes(
    List<int> bytes,
    String displayName, {
    String? shareText,
  }) =>
      shareBytes(bytes, displayName, extension: 'pdf', shareText: shareText);

  /// Shares multiple byte lists via the system share sheet using temporary files.
  Future<bool> shareMultipleBytes(
    List<MapEntry<String, List<int>>> files, {
    String extension = 'pdf',
    String? shareText,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cleanExt =
        extension.startsWith('.') ? extension.substring(1) : extension;
    final xFiles = <XFile>[];
    for (var entry in files) {
      final tempFile =
          File('${tempDir.path}/${entry.key}_$timestamp.$cleanExt');
      await tempFile.writeAsBytes(entry.value);
      xFiles.add(XFile(tempFile.path));
    }
    final result = await SharePlus.instance.share(
      ShareParams(
        files: xFiles,
        text: shareText ?? 'สร้างด้วย VibeQuickPDF',
      ),
    );
    return result.status == ShareResultStatus.success;
  }

  /// Shares multiple PDF byte lists via the system share sheet using temporary files.
  Future<bool> shareMultiplePdfBytes(
    List<MapEntry<String, List<int>>> files, {
    String? shareText,
  }) =>
      shareMultipleBytes(files, extension: 'pdf', shareText: shareText);

  Future<void> openPdf(String path, {String? fileName}) async {
    if (_isContentUri(path) && _isAndroid) {
      final effectiveName = fileName ?? path;
      final mimeType = effectiveName.toLowerCase().endsWith('.zip')
          ? 'application/zip'
          : 'application/pdf';
      final opened = await _storageChannel.invokeMethod<bool>(
        'openUri',
        {'uri': path, 'mimeType': mimeType},
      );
      if (opened != true) {
        debugPrint("Error opening content URI: $path");
      }
      return;
    }

    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      debugPrint("Error opening file: ${result.message}");
    }
  }

  /// Removes a file from the private registry without deleting the file on disk.
  Future<void> unregisterPdf(String path) async {
    final entries = await _readRegistry();
    entries.removeWhere((e) => e.path == path);
    await _writeRegistry(entries);
  }

  /// Deletes the file on disk (or MediaStore/SAF) and removes it from the registry.
  /// Returns `true` if the file was deleted (or already absent), `false` otherwise.
  Future<bool> deletePdfAndUnregister(PdfFile file) async {
    try {
      if (_isContentUri(file.path) && _isAndroid) {
        final deleted =
            await _storageChannel.invokeMethod<bool>(
              'deleteUri',
              {'uri': file.path},
            ) ??
            false;
        if (!deleted) {
          final stillExists = await _storageChannel.invokeMapMethod<String, dynamic>(
            'inspectUri',
            {'uri': file.path},
          );
          if (stillExists != null) {
            return false;
          }
        }
      } else {
        final diskFile = File(file.path);
        if (await diskFile.exists()) {
          await diskFile.delete();
        }
      }

      await unregisterPdf(file.path);
      return true;
    } catch (e) {
      debugPrint("Error deleting file: $e");
      return false;
    }
  }
}
