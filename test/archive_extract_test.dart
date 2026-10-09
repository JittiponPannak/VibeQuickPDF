import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_quick_pdf/services/archive_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return '.';
          },
        );
  });

  test('extractImagesFromArchive extracts and filters images from zip', () async {
    final archiveService = ArchiveService();

    // Create a test archive with 2 images and 1 text file
    final archive = Archive();
    archive.addFile(
      ArchiveFile('page_02.png', 4, [1, 2, 3, 4]),
    );
    archive.addFile(
      ArchiveFile('page_01.jpg', 4, [5, 6, 7, 8]),
    );
    archive.addFile(
      ArchiveFile('notes.txt', 4, [9, 10, 11, 12]),
    );
    archive.addFile(
      ArchiveFile('__MACOSX/._page_01.jpg', 4, [13, 14, 15, 16]),
    );

    final zipData = ZipEncoder().encode(archive);
    final tempZipFile = File('test_archive.zip');
    await tempZipFile.writeAsBytes(zipData);

    try {
      final extracted = await archiveService.extractImagesFromArchive(tempZipFile.path);

      // Should extract exactly 2 images (page_01.jpg, page_02.png)
      expect(extracted.length, 2);
      // Should be sorted alphabetically (page_01.jpg first, then page_02.png)
      expect(extracted[0].path.endsWith('page_01.jpg'), isTrue);
      expect(extracted[1].path.endsWith('page_02.png'), isTrue);
    } finally {
      if (await tempZipFile.exists()) {
        await tempZipFile.delete();
      }
    }
  });
}
