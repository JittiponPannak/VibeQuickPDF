import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_quick_pdf/l10n/app_localizations.dart';
import 'package:vibe_quick_pdf/models/pdf_file.dart';
import 'package:vibe_quick_pdf/screens/home_screen.dart';
import 'package:vibe_quick_pdf/services/file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocsDir;

  setUp(() {
    tempDocsDir = Directory.systemTemp.createTempSync('vibe_registry_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return tempDocsDir.path;
          },
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/package_info'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getAll') {
              return <String, dynamic>{
                'appName': 'VibeQuickPDF',
                'packageName': 'com.jittiponpannak.vibe_quick_pdf',
                'version': '1.3.1',
                'buildNumber': '1',
              };
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.jittiponpannak.vibe_quick_pdf/storage'),
          null,
        );
    if (tempDocsDir.existsSync()) {
      tempDocsDir.deleteSync(recursive: true);
    }
  });

  group('FileService private registry', () {
    test('does not discover unregistered files inside VibeQuickPDF folder', () async {
      final folder = Directory('${tempDocsDir.path}/VibeQuickPDF')
        ..createSync(recursive: true);
      final unregistered = File('${folder.path}/Stranger.pdf');
      await unregistered.writeAsBytes([1, 2, 3, 4]);

      final service = FileService(isAndroid: false);
      final files = await service.getPdfFiles();
      expect(files, isEmpty);
    });

    test('savePdf saves inside VibeQuickPDF and registers in private registry', () async {
      final service = FileService(isAndroid: false);
      final savedPath = await service.savePdf('Invoice', [10, 20, 30]);

      expect(savedPath, contains('VibeQuickPDF'));
      expect(File(savedPath).existsSync(), isTrue);

      final registryFile = File('${tempDocsDir.path}/vibe_pdf_registry.json');
      expect(registryFile.existsSync(), isTrue);

      final files = await service.getPdfFiles();
      expect(files.length, 1);
      expect(files.first.name, 'Invoice.pdf');
      expect(files.first.path, savedPath);
      expect(files.first.size, 3);
      expect(files.first.isImported, isFalse);
    });

    test('Android channel saves to Documents/VibeQuickPDF and supports import/inspect/delete', () async {
      const storageChannel =
          MethodChannel('com.jittiponpannak.vibe_quick_pdf/storage');
      final mediaStore = <String, Map<String, dynamic>>{};
      int nextId = 1;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, (MethodCall call) async {
            switch (call.method) {
              case 'saveToDocuments':
                final args = Map<String, dynamic>.from(call.arguments as Map);
                final fileName = args['fileName'] as String;
                final ext = args['extension'] as String;
                final bytes = args['bytes'] as Uint8List;
                final uri = 'content://media/external/file/${nextId++}';
                final meta = {
                  'path': uri,
                  'name': '$fileName.$ext',
                  'size': bytes.length,
                  'createdAt': 1700000000000,
                };
                mediaStore[uri] = meta;
                return meta;
              case 'pickPdfFile':
                const uri = 'content://com.android.externalstorage.documents/document/imported.pdf';
                final meta = {
                  'path': uri,
                  'name': 'ManualImport.pdf',
                  'size': 512,
                  'createdAt': 1700000100000,
                };
                mediaStore[uri] = meta;
                return meta;
              case 'inspectUri':
                final args = Map<String, dynamic>.from(call.arguments as Map);
                final uri = args['uri'] as String;
                final meta = mediaStore[uri];
                if (meta == null) return null;
                return {
                  'name': meta['name'],
                  'size': meta['size'],
                  'createdAt': meta['createdAt'],
                };
              case 'deleteUri':
                final args = Map<String, dynamic>.from(call.arguments as Map);
                final uri = args['uri'] as String;
                return mediaStore.remove(uri) != null;
            }
            return null;
          });

      final service = FileService(isAndroid: true);

      // Save PDF via MediaStore
      final savedUri = await service.savePdf('Report', [1, 2, 3, 4, 5]);
      expect(savedUri, startsWith('content://media/external/file/'));

      // Import PDF manually
      final importRes1 = await service.importPdfFromFile();
      expect(importRes1.status, ImportPdfStatus.imported);
      expect(importRes1.file?.name, 'ManualImport.pdf');
      expect(importRes1.file?.isImported, isTrue);

      // Re-importing same URI reports alreadyRegistered
      final importRes2 = await service.importPdfFromFile();
      expect(importRes2.status, ImportPdfStatus.alreadyRegistered);

      var listed = await service.getPdfFiles();
      expect(listed.length, 2);

      // Unregister imported PDF without deleting from device storage
      final imported = listed.firstWhere((f) => f.isImported);
      await service.unregisterPdf(imported.path);
      expect(mediaStore.containsKey(imported.path), isTrue);

      listed = await service.getPdfFiles();
      expect(listed.length, 1);
      expect(listed.first.name, 'Report.pdf');

      // Delete generated PDF deletes from MediaStore and unregisters
      final deleted = await service.deletePdfAndUnregister(listed.first);
      expect(deleted, isTrue);
      expect(mediaStore.containsKey(listed.first.path), isFalse);
      expect(await service.getPdfFiles(), isEmpty);
    });

    test('prevents importing an exported PDF picked via a different SAF URI', () async {
      const storageChannel =
          MethodChannel('com.jittiponpannak.vibe_quick_pdf/storage');
      const exportedMediaUri = 'content://media/external/file/99';
      const pickedSafUri =
          'content://com.android.externalstorage.documents/document/primary%3ADocuments%2FVibeQuickPDF%2FExported.pdf';
      const unrelatedSafUri =
          'content://com.android.externalstorage.documents/document/primary%3ADownload%2FOther.pdf';

      String nextPickedUri = pickedSafUri;
      String nextPickedName = 'Exported.pdf';
      int nextPickedSize = 100;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, (MethodCall call) async {
            switch (call.method) {
              case 'saveToDocuments':
                final args = Map<String, dynamic>.from(call.arguments as Map);
                final bytes = args['bytes'] as Uint8List;
                return {
                  'path': exportedMediaUri,
                  'name': 'Exported.pdf',
                  'size': bytes.length,
                  'createdAt': 1700000000000,
                };
              case 'pickPdfFile':
                return {
                  'path': nextPickedUri,
                  'name': nextPickedName,
                  'size': nextPickedSize,
                  'createdAt': 1700000200000,
                };
              case 'findMatchingRegisteredPath':
                final args = Map<String, dynamic>.from(call.arguments as Map);
                final picked = args['uri'] as String;
                final registered = List<String>.from(args['registeredPaths'] as List);
                if (picked == pickedSafUri && registered.contains(exportedMediaUri)) {
                  return exportedMediaUri;
                }
                return null;
              case 'inspectUri':
                final args = Map<String, dynamic>.from(call.arguments as Map);
                final uri = args['uri'] as String;
                if (uri == exportedMediaUri) {
                  return {
                    'name': 'Exported.pdf',
                    'size': 100,
                    'createdAt': 1700000000000,
                  };
                }
                if (uri == unrelatedSafUri) {
                  return {
                    'name': 'Other.pdf',
                    'size': 200,
                    'createdAt': 1700000200000,
                  };
                }
                return null;
            }
            return null;
          });

      final service = FileService(isAndroid: true);
      final savedPath = await service.savePdf('Exported', List<int>.filled(100, 7));
      expect(savedPath, exportedMediaUri);

      // Picking the exported file via SAF document URI is blocked as alreadyRegistered
      final duplicateResult = await service.importPdfFromFile();
      expect(duplicateResult.status, ImportPdfStatus.alreadyRegistered);
      expect(duplicateResult.file?.path, exportedMediaUri);
      expect(duplicateResult.file?.isImported, isFalse);

      var listed = await service.getPdfFiles();
      expect(listed.length, 1);
      expect(listed.first.path, exportedMediaUri);
      expect(listed.first.isImported, isFalse);

      // Picking a different PDF is still allowed
      nextPickedUri = unrelatedSafUri;
      nextPickedName = 'Other.pdf';
      nextPickedSize = 200;
      final newResult = await service.importPdfFromFile();
      expect(newResult.status, ImportPdfStatus.imported);
      expect(newResult.file?.path, unrelatedSafUri);
      expect(newResult.file?.isImported, isTrue);

      listed = await service.getPdfFiles();
      expect(listed.length, 2);
    });
  });

  group('HomeScreen registry & import UI', () {
    testWidgets('shows Import PDF From File in menu and handles imported vs generated delete', (
      WidgetTester tester,
    ) async {
      // Seed one generated file and one imported file on disk + registry
      final genFile = File('${tempDocsDir.path}/Generated.pdf')
        ..writeAsBytesSync([1, 2, 3]);
      final impFile = File('${tempDocsDir.path}/External.pdf')
        ..writeAsBytesSync([4, 5, 6, 7]);

      final registryFile = File('${tempDocsDir.path}/vibe_pdf_registry.json');
      registryFile.writeAsStringSync(
        jsonEncode([
          PdfFile(
            name: 'Generated.pdf',
            path: genFile.path,
            createdAt: DateTime(2026, 1, 1, 10, 0),
            size: 3,
            isImported: false,
          ).toJson(),
          PdfFile(
            name: 'External.pdf',
            path: impFile.path,
            createdAt: DateTime(2026, 1, 2, 10, 0),
            size: 4,
            isImported: true,
          ).toJson(),
        ]),
      );

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify both files appear and imported badge is shown
      expect(find.text('External.pdf'), findsOneWidget);
      expect(find.text('Generated.pdf'), findsOneWidget);
      expect(find.textContaining('Imported'), findsOneWidget);

      // Verify menu contains Import PDF From File
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Import PDF From File'), findsOneWidget);

      // Dismiss popup menu
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Tap delete on the first item (External.pdf, imported)
      await tester.tap(find.byIcon(Icons.delete).first);
      await tester.pumpAndSettle();

      expect(find.text('Remove Imported PDF'), findsOneWidget);
      expect(find.text('Remove from List'), findsOneWidget);
      expect(find.text('Delete File'), findsOneWidget);

      // Choose Remove from List: file remains on disk, removed from UI & registry
      await tester.tap(find.text('Remove from List'));
      await tester.pumpAndSettle();

      expect(find.text('External.pdf'), findsNothing);
      expect(impFile.existsSync(), isTrue);

      // Now tap delete on Generated.pdf (non-imported)
      await tester.tap(find.byIcon(Icons.delete).first);
      await tester.pumpAndSettle();

      expect(find.text('Delete PDF'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Generated.pdf'), findsNothing);
      expect(genFile.existsSync(), isFalse);
    });
  });
}

