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

  group('ArchiveService', () {
    test('isArchive correctly detects archive extensions', () {
      expect(ArchiveService.isArchive('test.zip'), isTrue);
      expect(ArchiveService.isArchive('test.tar.gz'), isTrue);
      expect(ArchiveService.isArchive('test.tgz'), isTrue);
      expect(ArchiveService.isArchive('test.tar'), isTrue);
      expect(ArchiveService.isArchive('test.jpg'), isFalse);
      expect(ArchiveService.isArchive('test.pdf'), isFalse);
    });

    test('isImage correctly detects image extensions', () {
      expect(ArchiveService.isImage('photo.jpg'), isTrue);
      expect(ArchiveService.isImage('photo.png'), isTrue);
      expect(ArchiveService.isImage('photo.webp'), isTrue);
      expect(ArchiveService.isImage('photo.zip'), isFalse);
      expect(ArchiveService.isImage('document.pdf'), isFalse);
    });

    test('createZipFromImages packages images into a valid zip archive', () async {
      final archiveService = ArchiveService();

      // Create 2 temporary image files
      final img1 = File('test_img_1.png');
      final img2 = File('test_img_2.jpg');
      await img1.writeAsBytes([10, 20, 30, 40]);
      await img2.writeAsBytes([50, 60, 70, 80]);

      try {
        final zipBytes = await archiveService.createZipFromImages(
          [img1.path, img2.path],
          baseFileName: 'Vacation',
        );

        expect(zipBytes, isNotEmpty);

        final decodedArchive = ZipDecoder().decodeBytes(zipBytes);
        expect(decodedArchive.files.length, 2);
        expect(decodedArchive.files[0].name, 'Vacation_1.png');
        expect(decodedArchive.files[0].content as List<int>, [10, 20, 30, 40]);
        expect(decodedArchive.files[1].name, 'Vacation_2.jpg');
        expect(decodedArchive.files[1].content as List<int>, [50, 60, 70, 80]);
      } finally {
        if (await img1.exists()) await img1.delete();
        if (await img2.exists()) await img2.delete();
      }
    });

    test('createZipFromImage packages single image without index suffix', () async {
      final archiveService = ArchiveService();

      final img = File('single_img.png');
      await img.writeAsBytes([1, 2, 3]);

      try {
        final zipBytes = await archiveService.createZipFromImage(
          img.path,
          baseFileName: 'Receipt',
        );

        final decodedArchive = ZipDecoder().decodeBytes(zipBytes);
        expect(decodedArchive.files.length, 1);
        expect(decodedArchive.files[0].name, 'Receipt.png');
        expect(decodedArchive.files[0].content as List<int>, [1, 2, 3]);
      } finally {
        if (await img.exists()) await img.delete();
      }
    });
  });
}
