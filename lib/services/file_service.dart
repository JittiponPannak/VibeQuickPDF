import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import '../models/pdf_file.dart';
import 'package:path/path.dart' as p;

class FileService {
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    final pdfDirectory = Directory('${directory.path}/VibePDFs');
    if (!(await pdfDirectory.exists())) {
      await pdfDirectory.create(recursive: true);
    }
    return pdfDirectory.path;
  }

  Future<List<PdfFile>> getPdfFiles() async {
    final path = await _localPath;
    final directory = Directory(path);
    List<PdfFile> files = [];

    try {
      final List<FileSystemEntity> entities = directory.listSync();
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.pdf')) {
          final stat = await entity.stat();
          files.add(
            PdfFile(
              name: p.basename(entity.path),
              path: entity.path,
              createdAt: stat.modified,
              size: stat.size,
            ),
          );
        }
      }

      // Sort by newest first
      files.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      print("Error reading directory: $e");
    }

    return files;
  }

  Future<String> savePdf(String fileName, List<int> bytes) async {
    final path = await _localPath;
    String fullPath = '$path/$fileName.pdf';

    // Check if file exists, append number if it does
    int counter = 1;
    while (await File(fullPath).exists()) {
      fullPath = '$path/${fileName}_$counter.pdf';
      counter++;
    }

    final file = File(fullPath);
    await file.writeAsBytes(bytes);
    return fullPath;
  }

  Future<void> sharePdf(String path) async {
    await Share.shareXFiles([XFile(path)], text: 'สร้างด้วย VibeQuickPDF');
  }

  /// Shares PDF bytes via the system share sheet using a temporary file.
  /// No permanent file is saved on the device.
  Future<void> sharePdfBytes(List<int> bytes, String displayName) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/${displayName}_$timestamp.pdf');
    await tempFile.writeAsBytes(bytes);
    await Share.shareXFiles([
      XFile(tempFile.path),
    ], text: 'สร้างด้วย VibeQuickPDF');
  }

  Future<void> openPdf(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      print("Error opening file: ${result.message}");
    }
  }

  Future<void> deletePdf(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print("Error deleting file: $e");
    }
  }
}
