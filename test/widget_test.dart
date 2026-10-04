// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vibe_quick_pdf/l10n/app_localizations.dart';
import 'package:vibe_quick_pdf/main.dart';
import 'package:vibe_quick_pdf/screens/conversion_screen.dart';

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
}
