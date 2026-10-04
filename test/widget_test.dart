// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vibe_quick_pdf/l10n/app_localizations.dart';
import 'package:vibe_quick_pdf/main.dart';
import 'package:vibe_quick_pdf/screens/conversion_screen.dart';
import 'package:vibe_quick_pdf/widgets/shared_media_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/package_info'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getAll') {
              return <String, dynamic>{
                'appName': 'VibeQuickPDF',
                'packageName': 'com.vibe.quickpdf',
                'version': '1.3.0',
                'buildNumber': '1',
              };
            }
            return null;
          },
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return '.';
          },
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('open_filex'),
          (MethodCall methodCall) async {
            return {
              'type': 0,
              'message': 'done',
            };
          },
        );
  });

  testWidgets('HomeScreen displays in Thai by default and in English when locale is set', (
    WidgetTester tester,
  ) async {
    // Reset notifier to null (system default / Thai)
    appLocaleNotifier.value = const Locale('th');

    await tester.pumpWidget(const VibeQuickPdfApp());
    await tester.pump();

    // Verify main create PDF button in Thai
    expect(find.text('สร้าง PDF'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsNothing);
    expect(find.byIcon(Icons.bolt), findsNothing);

    // Switch to English
    appLocaleNotifier.value = const Locale('en');
    await tester.pump();
    await tester.pump();

    // Verify main create PDF button in English
    expect(find.text('Create PDF'), findsOneWidget);
  });

  testWidgets('ConversionScreen shows localized Save to Disk and Share buttons', (
    WidgetTester tester,
  ) async {
    final testImages = [XFile('test_image.png')];

    // Thai test
    appLocaleNotifier.value = const Locale('th');
    await tester.pumpWidget(
      const VibeQuickPdfApp(),
    );
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('th'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ConversionScreen(initialImages: testImages),
      ),
    );
    await tester.pump();

    expect(find.text('ดูตัวอย่าง'), findsOneWidget);
    expect(find.text('บันทึกในเครื่อง'), findsOneWidget);
    expect(find.text('แชร์'), findsOneWidget);

    // English test
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ConversionScreen(initialImages: testImages),
      ),
    );
    await tester.pump();

    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Save to Device'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('ConversionScreen empty state displays localized creation hub options', (
    WidgetTester tester,
  ) async {
    // English test
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
        home: ConversionScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('Add images to start creating PDF'), findsOneWidget);
    // Verifies no duplicate buttons on empty screen
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    // Verifies Quick PDF setting switch exists
    expect(find.text('Quick PDF'), findsOneWidget);

    // Thai test
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('th'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ConversionScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('เพิ่มรูปภาพเพื่อเริ่มต้นสร้าง PDF'), findsOneWidget);
    // Verifies no duplicate buttons on empty screen in Thai
    expect(find.text('ถ่ายรูป'), findsOneWidget);
    expect(find.text('เลือกจากคลัง'), findsOneWidget);
    expect(find.text('Quick PDF'), findsOneWidget);
  });

  testWidgets('ConversionScreen supports image reordering and shows reorder hint and page badges', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final testImages = [
      XFile('image_1.png'),
      XFile('image_2.png'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ConversionScreen(initialImages: testImages),
      ),
    );
    await tester.pump();

    // Verify reorder hint and page number badges
    expect(find.text('Press & drag to reorder pages'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    // Verify Draggable items exist
    expect(find.byType(LongPressDraggable<int>), findsNWidgets(2));
    expect(find.byType(DragTarget<int>), findsNWidgets(3));

    // Tap on first image to open reorder modal
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    // Verify reorder modal options appear
    expect(find.text('Move Next'), findsOneWidget);
    expect(find.text('Move to Last'), findsOneWidget);

    // Tap Move Next
    await tester.tap(find.text('Move Next'));
    await tester.pumpAndSettle();

    // Verify modal dismissed and images still present
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('showSharedMediaApplicationDialog displays application dialog with append and create-new options', (
    WidgetTester tester,
  ) async {
    SharedMediaAction? chosenAction;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                chosenAction = await showSharedMediaApplicationDialog(
                  context: context,
                  count: 3,
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify application dialog contents
    expect(find.text('Shared Images Received'), findsOneWidget);
    expect(find.text('Append to current list'), findsOneWidget);
    expect(
      find.text('Create new list (insert as first element)'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);

    // Tap Append to current list
    await tester.tap(find.text('Append to current list'));
    await tester.pumpAndSettle();

    expect(chosenAction, SharedMediaAction.append);
  });

  testWidgets('ConversionScreen displays Export Format dropdown above merge option and switches between PDF and ZIP', (
    WidgetTester tester,
  ) async {
    final testImages = [XFile('test_image.png')];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ConversionScreen(initialImages: testImages),
      ),
    );
    await tester.pump();

    // Verify initial state: PDF is selected by default
    expect(find.text('Export Format'), findsOneWidget);
    expect(find.text('PDF'), findsWidgets);
    expect(find.text('Merge into single PDF'), findsOneWidget);

    // Open dropdown
    await tester.tap(find.text('PDF').first);
    await tester.pumpAndSettle();

    // Verify dropdown items
    expect(find.text('ZIP').last, findsOneWidget);

    // Select ZIP
    await tester.tap(find.text('ZIP').last);
    await tester.pumpAndSettle();

    // Verify UI dynamically updated for ZIP export
    expect(find.text('Merge into single ZIP'), findsOneWidget);
    expect(find.text('ZIP File Name'), findsOneWidget);
  });

  testWidgets('ConversionScreen creates and shows temp preview and deletes it when closed', (
    WidgetTester tester,
  ) async {
    final img = File('preview_test_image.png');
    // Minimal valid 1x1 PNG bytes
    await img.writeAsBytes([
      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
      0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196,
      137, 0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0,
      5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174,
      66, 96, 130
    ]);

    try {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ConversionScreen(initialImages: [XFile(img.path)]),
        ),
      );
      await tester.pump();

      // Tap Preview button
      await tester.tap(find.text('Preview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Verify bottom sheet modal is open
      expect(find.text('PDF Preview'), findsOneWidget);
      expect(
        find.text('Temporary preview active. File will be deleted when closed.'),
        findsOneWidget,
      );
      expect(find.text('Close Preview'), findsOneWidget);

      // Tap Close Preview
      await tester.tap(find.text('Close Preview'));
      await tester.pumpAndSettle();

      // Verify sheet is closed and deletion snackbar appears
      expect(find.text('PDF Preview'), findsNothing);
      expect(
        find.text('Preview closed and temporary file deleted'),
        findsOneWidget,
      );
    } finally {
      if (await img.exists()) await img.delete();
    }
  });

  testWidgets('HomeScreen has ThemeToggleButton and toggles between light and dark mode', (
    WidgetTester tester,
  ) async {
    appThemeModeNotifier.value = ThemeMode.light;

    await tester.pumpWidget(const VibeQuickPdfApp());
    await tester.pumpAndSettle();

    // In light mode, icon is dark_mode (indicating tap to switch to dark)
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);

    // Tap theme toggle button
    await tester.tap(find.byIcon(Icons.dark_mode));
    await tester.pumpAndSettle();

    // Now theme mode is dark
    expect(appThemeModeNotifier.value, ThemeMode.dark);
    expect(find.byIcon(Icons.light_mode), findsOneWidget);

    // Tap again to switch back
    await tester.tap(find.byIcon(Icons.light_mode));
    await tester.pumpAndSettle();

    expect(appThemeModeNotifier.value, ThemeMode.light);
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);
  });

  testWidgets('ConversionScreen has ThemeToggleButton and toggles theme mode', (
    WidgetTester tester,
  ) async {
    appThemeModeNotifier.value = ThemeMode.light;

    await tester.pumpWidget(
      ListenableBuilder(
        listenable: appThemeModeNotifier,
        builder: (context, _) => MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: appThemeModeNotifier.value,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const ConversionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Button exists on empty ConversionScreen
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);

    // Tap toggle button
    await tester.tap(find.byIcon(Icons.dark_mode));
    await tester.pumpAndSettle();

    expect(appThemeModeNotifier.value, ThemeMode.dark);
    expect(find.byIcon(Icons.light_mode), findsOneWidget);
  });
}
