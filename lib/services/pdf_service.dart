import 'dart:io';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

class PdfService {
  /// Converts multiple images into a single PDF document.
  Future<List<int>> createPdfFromImages(List<String> imagePaths) async {
    final pdf = pw.Document();

    for (var path in imagePaths) {
      final imageFile = File(path);
      if (await imageFile.exists()) {
        final image = pw.MemoryImage(await imageFile.readAsBytes());
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(
              image.width!.toDouble(),
              image.height!.toDouble(),
            ),
            margin: pw.EdgeInsets.zero,
            build: (pw.Context context) {
              return pw.Image(image);
            },
          ),
        );
      }
    }

    return await pdf.save();
  }

  /// Converts a single image into a PDF document.
  Future<List<int>> createPdfFromImage(String imagePath) async {
    return createPdfFromImages([imagePath]);
  }
}
