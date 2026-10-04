import 'dart:io';
import 'package:archive/archive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ArchiveService {
  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
    '.gif',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
  };

  static const Set<String> _archiveExtensions = {
    '.zip',
    '.tar',
    '.gz',
    '.tgz',
    '.bz2',
    '.tbz2',
    '.xz',
  };

  static bool isImage(String path) {
    final ext = p.extension(path).toLowerCase();
    return _imageExtensions.contains(ext);
  }

  static bool isArchive(String path) {
    final lower = path.toLowerCase();
    return _archiveExtensions.any((ext) => lower.endsWith(ext));
  }

  /// Extracts all image files from an archive file at [archivePath].
  /// Returns a list of [XFile] pointing to the extracted images in a temporary folder.
  Future<List<XFile>> extractImagesFromArchive(String archivePath) async {
    final file = File(archivePath);
    if (!await file.exists()) return [];

    final bytes = await file.readAsBytes();
    Archive? archive;

    final lowerPath = archivePath.toLowerCase();
    if (lowerPath.endsWith('.zip')) {
      archive = ZipDecoder().decodeBytes(bytes);
    } else if (lowerPath.endsWith('.tar.gz') || lowerPath.endsWith('.tgz')) {
      final decompressed = GZipDecoder().decodeBytes(bytes);
      archive = TarDecoder().decodeBytes(decompressed);
    } else if (lowerPath.endsWith('.tar')) {
      archive = TarDecoder().decodeBytes(bytes);
    } else if (lowerPath.endsWith('.gz')) {
      try {
        final decompressed = GZipDecoder().decodeBytes(bytes);
        archive = TarDecoder().decodeBytes(decompressed);
      } catch (_) {
        archive = ZipDecoder().decodeBytes(bytes);
      }
    } else {
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (_) {
        try {
          archive = TarDecoder().decodeBytes(bytes);
        } catch (_) {}
      }
    }

    if (archive == null || archive.isEmpty) return [];

    final tempDir = await getTemporaryDirectory();
    final extractionSubdir = Directory(
      p.join(
        tempDir.path,
        'extracted_archives',
        '${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    await extractionSubdir.create(recursive: true);

    // Filter image entries and ignore OS metadata
    final imageEntries = archive.files.where((entry) {
      if (!entry.isFile) return false;
      final name = entry.name.toLowerCase();
      if (name.contains('__macosx') || p.basename(name).startsWith('.')) {
        return false;
      }
      return isImage(name);
    }).toList();

    // Natural alphabetical sort by filename to preserve intended order
    imageEntries.sort((a, b) => a.name.compareTo(b.name));

    final List<XFile> extractedFiles = [];

    for (final entry in imageEntries) {
      final content = entry.content as List<int>;
      final sanitizedBasename = p.basename(entry.name);
      final destPath = p.join(extractionSubdir.path, sanitizedBasename);
      final destFile = File(destPath);
      await destFile.writeAsBytes(content);
      extractedFiles.add(XFile(destPath));
    }

    return extractedFiles;
  }

  /// Processes a list of file paths (which may contain images or archives)
  /// and returns all resolved [XFile] images.
  Future<List<XFile>> resolveImagesFromSharedPaths(List<String> paths) async {
    final List<XFile> result = [];

    for (final path in paths) {
      if (isArchive(path)) {
        try {
          final extracted = await extractImagesFromArchive(path);
          result.addAll(extracted);
        } catch (_) {
          // If archive extraction failed, skip or continue
        }
      } else if (isImage(path)) {
        result.add(XFile(path));
      } else {
        // Fallback check: try decoding as archive, otherwise if valid file treat as image
        try {
          final extracted = await extractImagesFromArchive(path);
          if (extracted.isNotEmpty) {
            result.addAll(extracted);
          } else {
            result.add(XFile(path));
          }
        } catch (_) {
          result.add(XFile(path));
        }
      }
    }

    return result;
  }

  /// Creates a ZIP archive containing images from [imagePaths].
  /// [baseFileName] is used to name files within the archive.
  Future<List<int>> createZipFromImages(
    List<String> imagePaths, {
    String baseFileName = 'Document',
  }) async {
    final archive = Archive();
    final padLength = imagePaths.length >= 100
        ? 3
        : (imagePaths.length >= 10 ? 2 : 1);

    for (int i = 0; i < imagePaths.length; i++) {
      final path = imagePaths[i];
      final file = File(path);
      if (!await file.exists()) continue;

      final bytes = await file.readAsBytes();
      var ext = p.extension(path);
      if (ext.isEmpty) ext = '.jpg';

      final String entryName;
      if (imagePaths.length == 1) {
        entryName = '$baseFileName$ext';
      } else {
        final numStr = (i + 1).toString().padLeft(padLength, '0');
        entryName = '${baseFileName}_$numStr$ext';
      }

      archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
    }

    final encoder = ZipEncoder();
    return encoder.encode(archive);
  }

  /// Creates a ZIP archive for a single image file at [imagePath].
  Future<List<int>> createZipFromImage(
    String imagePath, {
    String baseFileName = 'Document',
  }) async {
    return createZipFromImages([imagePath], baseFileName: baseFileName);
  }
}
