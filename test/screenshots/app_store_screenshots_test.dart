// Generates the App Store screenshots into `screenshots/`.
//
// Not part of the normal suite — it writes files and its dates move with the
// clock. Run it explicitly:
//
//   flutter test test/screenshots --dart-define=SCREENSHOTS=true
//
// or `tool/generate_screenshots.ps1`.
//
// Each shot is made in two passes. First the real app (real router, real
// screens, DemoData in an in-memory Drift database, fake RevenueCat / auth /
// notifications — nothing touches a real service) renders full-screen at the
// iPhone 6.7" logical size and is captured. Then that capture is placed in the
// green marketing template (title, subtitle, iPhone frame) and the template is
// captured at 1290x2796.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/app.dart';
import 'package:ourgarage/app_router.dart';
import 'package:ourgarage/app_routes.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/debug/demo_data.dart';

import '../support/fake_auth_backend.dart';
import '../support/fake_notification_plugin.dart';
import '../support/fake_purchases_api.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');

/// iPhone 6.7" (15 Pro Max): 430x932 points at 3x = 1290x2796 pixels.
const _logicalSize = Size(430, 932);
const _pixelRatio = 3.0;

/// iPhone safe-area insets, in points.
const _safeTop = 59.0;
const _safeBottom = 34.0;

const _outputDir = 'screenshots';

const _crvId = '${DemoData.idPrefix}vehicle-crv';
const _civicId = '${DemoData.idPrefix}vehicle-civic';

void main() {
  late AppDatabase db;

  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    DatabaseHolder.overrideWith(db);
    await DemoData.load(db);
  });

  tearDown(() async {
    DatabaseHolder.overrideWith(null);
    await db.close();
  });

  Future<void> shoot(
    WidgetTester tester, {
    required String file,
    required String title,
    required String subtitle,
    required String location,
    Future<void> Function(WidgetTester tester)? prepare,
  }) async {
    tester.view
      ..physicalSize = _logicalSize * _pixelRatio
      ..devicePixelRatio = _pixelRatio
      ..padding = const FakeViewPadding(
        top: _safeTop * _pixelRatio,
        bottom: _safeBottom * _pixelRatio,
      );
    addTearDown(tester.view.reset);

    // flutter_test draws elevation as a solid outline unless real shadows are
    // switched on. The binding checks the flag is restored before tear-downs
    // run, so it is restored in `finally` — a failure then reports itself
    // rather than a secondary "debugDisableShadows changed" error.
    debugDisableShadows = false;
    try {
      await _shoot(
        tester,
        file: file,
        title: title,
        subtitle: subtitle,
        location: location,
        prepare: prepare,
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  testWidgets('01 garage', skip: !_enabled, (tester) async {
    await shoot(
      tester,
      file: '01_garage.png',
      title: 'Never miss an oil change',
      subtitle: 'Reminders before maintenance is due',
      location: AppRoutes.vehicleList,
    );
  });

  testWidgets('02 reminders', skip: !_enabled, (tester) async {
    // DemoData gives each vehicle one rule. A list of one doesn't show
    // "by mileage or by date", so the CR-V gets two more, date-based and
    // mixed, here in the screenshot script only.
    await _addRule(
      db,
      key: 'crv-rotation',
      vehicleId: _crvId,
      type: ServiceType.tireRotation,
      intervalMonths: 6,
      intervalDistance: 7500,
      lastDoneDaysAgo: 150,
      lastDoneOdometer: 36900,
    );
    await _addRule(
      db,
      key: 'crv-inspection',
      vehicleId: _crvId,
      type: ServiceType.inspection,
      intervalMonths: 12,
      lastDoneDaysAgo: 240,
      lastDoneOdometer: 34800,
    );

    await shoot(
      tester,
      file: '02_reminders.png',
      title: "Know what's due next",
      subtitle: 'By mileage or by date',
      location: AppRoutes.reminders(_crvId),
    );
  });

  testWidgets('03 history', skip: !_enabled, (tester) async {
    await shoot(
      tester,
      file: '03_history.png',
      title: 'Every service, logged',
      subtitle: 'Costs, mileage and notes in one place',
      // Unscrolled: the Civic's whole page is barely taller than the screen,
      // so any scroll leaves the header half-hidden under the app bar.
      location: AppRoutes.vehicleDetail(_civicId),
    );
  });

  testWidgets('04 paywall', skip: !_enabled, (tester) async {
    await shoot(
      tester,
      file: '04_paywall.png',
      title: 'Premium for the whole household',
      subtitle: 'One member unlocks it, everyone gets it',
      location: AppRoutes.paywall,
    );
  });
}

Future<void> _shoot(
  WidgetTester tester, {
  required String file,
  required String title,
  required String subtitle,
  required String location,
  Future<void> Function(WidgetTester tester)? prepare,
}) async {
  {
    // Pass 1: the real app, full screen.
    final appKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: appKey,
        child: ProviderScope(
          overrides: [
            fakeNotificationServiceOverride(),
            fakePurchaseServiceOverride(),
            fakeAuthServiceOverride(),
          ],
          child: const OurGarageApp(),
        ),
      ),
    );
    await tester.pump();

    appRouter.go(location);
    await _settle(tester);
    // FutureProviders (the paywall's offering) resolve outside fake time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await _settle(tester);
    if (prepare != null) await prepare(tester);

    final appImage = await _capture(tester, appKey);

    // Pass 2: the marketing template replaces the app tree.
    final templateKey = GlobalKey();
    tester.view.resetPadding();
    await tester.pumpWidget(
      RepaintBoundary(
        key: templateKey,
        child: _Template(title: title, subtitle: subtitle, screen: appImage),
      ),
    );
    await tester.pump();

    final shot = await _capture(tester, templateKey);
    await tester.runAsync(() => _writePng(shot, '$_outputDir/$file'));

    // Drop the tree holding the images before disposing them.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    appImage.dispose();
    shot.dispose();
  }
}

/// Finite pumps: loading spinners animate forever, so no pumpAndSettle.
Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<ui.Image> _capture(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(
    () => boundary.toImage(pixelRatio: _pixelRatio),
  );
  return image!;
}

Future<void> _writePng(ui.Image image, String path) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
}

Future<void> _addRule(
  AppDatabase db, {
  required String key,
  required String vehicleId,
  required ServiceType type,
  int? intervalMonths,
  int? intervalDistance,
  required int lastDoneDaysAgo,
  required int lastDoneOdometer,
}) async {
  final now = DateTime.now();
  final lastDone = DateTime(now.year, now.month, now.day - lastDoneDaysAgo);
  await db
      .into(db.reminderRules)
      .insert(
        ReminderRulesCompanion.insert(
          id: '${DemoData.idPrefix}rule-$key',
          vehicleId: vehicleId,
          type: type.name,
          intervalMonths: Value(intervalMonths),
          intervalDistance: Value(intervalDistance),
          lastDoneAt: Value(lastDone),
          lastDoneOdometer: Value(lastDoneOdometer),
          createdAt: lastDone,
          updatedAt: now,
        ),
      );
}

/// The test runner renders text in the Ahem box font unless real fonts are
/// registered. Roboto and Material Icons ship with the Flutter SDK.
Future<void> _loadFonts() async {
  final fontsDir = _flutterRoot().uri
      .resolve('bin/cache/artifacts/material_fonts/')
      .toFilePath();

  Future<ByteData> read(String name) async {
    final bytes = await File('$fontsDir$name').readAsBytes();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final roboto = FontLoader('Roboto');
  for (final weight in [
    'roboto-light.ttf',
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]) {
    roboto.addFont(read(weight));
  }
  await roboto.load();

  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('materialicons-regular.otf'))).load();
}

/// The Flutter SDK root, from `FLUTTER_ROOT` or from the tester binary's
/// location (`<root>/bin/cache/artifacts/engine/<platform>/flutter_tester`).
Directory _flutterRoot() {
  final fromEnv = Platform.environment['FLUTTER_ROOT'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return Directory(
      fromEnv.endsWith('/') || fromEnv.endsWith(r'\')
          ? fromEnv
          : '$fromEnv${Platform.pathSeparator}',
    );
  }
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    if (Directory(
      dir.uri.resolve('bin/cache/artifacts/material_fonts/').toFilePath(),
    ).existsSync()) {
      return Directory('${dir.path}${Platform.pathSeparator}');
    }
    dir = dir.parent;
  }
  throw StateError('Could not locate the Flutter SDK for fonts.');
}

/// Green marketing frame: title, subtitle and the capture in an iPhone body.
class _Template extends StatelessWidget {
  const _Template({
    required this.title,
    required this.subtitle,
    required this.screen,
  });

  final String title;
  final String subtitle;
  final ui.Image screen;

  static const _top = Color(0xFF0B6B53);
  static const _bottom = Color(0xFF14A37F);

  /// Phone screen scale relative to the full canvas.
  static const _scale = 0.73;
  static const _bezel = 11.0;

  @override
  Widget build(BuildContext context) {
    final screenW = _logicalSize.width * _scale;
    final screenH = _logicalSize.height * _scale;
    final screenRadius = 55.0 * _scale;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_top, _bottom],
          ),
        ),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: 28,
                right: 28,
                top: 64,
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 34,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 19,
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
              // Fixed position across all shots, fully inside the canvas.
              Positioned(
                top: 206,
                left: (_logicalSize.width - screenW) / 2 - _bezel,
                child: Container(
                  padding: const EdgeInsets.all(_bezel),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111312),
                    borderRadius: BorderRadius.circular(screenRadius + _bezel),
                    border: Border.all(
                      color: const Color(0xFF3A3F3D),
                      width: 1.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(screenRadius),
                    child: SizedBox(
                      width: screenW,
                      height: screenH,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: RawImage(
                              image: screen,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          _StatusBar(scale: _scale),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS status bar with Dynamic Island, drawn over the app's safe-area inset.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF111111);
    return SizedBox(
      height: _safeTop * scale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 34 * scale,
            top: 18 * scale,
            child: Text(
              '9:41',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 17 * scale,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
          Positioned(
            top: 11 * scale,
            child: Container(
              width: 125 * scale,
              height: 37 * scale,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20 * scale),
              ),
            ),
          ),
          Positioned(
            right: 30 * scale,
            top: 19 * scale,
            child: Row(
              children: [
                Icon(Icons.signal_cellular_alt, size: 17 * scale, color: ink),
                SizedBox(width: 4 * scale),
                Icon(Icons.wifi, size: 17 * scale, color: ink),
                SizedBox(width: 4 * scale),
                RotatedBox(
                  quarterTurns: 1,
                  child: Icon(Icons.battery_full, size: 20 * scale, color: ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
