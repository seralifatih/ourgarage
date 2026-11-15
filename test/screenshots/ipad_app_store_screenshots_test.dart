// Generates the iPad 13" App Store screenshots (2064x2752, RGB, no alpha)
// into `screenshots/2064x2752/`.
//
// Not part of the normal suite. Run this file on its own — running the whole
// folder would also regenerate the iPhone set:
//
//   flutter test test/screenshots/ipad_app_store_screenshots_test.dart \
//     --dart-define=SCREENSHOTS=true
//
// Same two passes as the iPhone script (app_store_screenshots_test.dart): the
// real app renders full-screen at the iPad Pro 13" logical size (1032x1376
// points at 2x, so the capture is exactly 2064x2752) with the same DemoData,
// then the capture goes into the same green template — same titles, order
// and colours — in an iPad frame.
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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
import 'screenshot_kit.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');

const _pixelWidth = 2064;
const _pixelHeight = 2752;
const _pixelRatio = 2.0;
const _logicalSize = Size(
  _pixelWidth / _pixelRatio,
  _pixelHeight / _pixelRatio,
);
const _outputDir = 'screenshots/2064x2752';

/// iPad (no notch) safe-area insets, in points: status bar and home indicator.
const _safeTop = 24.0;
const _safeBottom = 20.0;

const _crvId = '${DemoData.idPrefix}vehicle-crv';
const _civicId = '${DemoData.idPrefix}vehicle-civic';

void main() {
  late AppDatabase db;

  setUpAll(() async {
    if (_enabled) await loadScreenshotFonts();
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
  }) async {
    tester.view
      ..physicalSize = _logicalSize * _pixelRatio
      ..devicePixelRatio = _pixelRatio
      ..padding = const FakeViewPadding(
        top: _safeTop * _pixelRatio,
        bottom: _safeBottom * _pixelRatio,
      );
    addTearDown(tester.view.reset);

    debugDisableShadows = false;
    try {
      await _shoot(
        tester,
        file: file,
        title: title,
        subtitle: subtitle,
        location: location,
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  // Titles, subtitles, order and demo data match the iPhone set exactly.
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
    await addDemoRule(
      db,
      key: 'crv-rotation',
      vehicleId: _crvId,
      type: ServiceType.tireRotation,
      intervalMonths: 6,
      intervalDistance: 7500,
      lastDoneDaysAgo: 150,
      lastDoneOdometer: 36900,
    );
    await addDemoRule(
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
}) async {
  // Pass 1: the real app, full screen at iPad size.
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
  await settleFrames(tester);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await settleFrames(tester);

  final appImage = await captureBoundary(tester, appKey, _pixelRatio);

  // Pass 2: the marketing template.
  final templateKey = GlobalKey();
  tester.view.resetPadding();
  await tester.pumpWidget(
    RepaintBoundary(
      key: templateKey,
      child: _IpadTemplate(title: title, subtitle: subtitle, screen: appImage),
    ),
  );
  await tester.pump();

  final shot = await captureBoundary(tester, templateKey, _pixelRatio);
  await tester.runAsync(
    () => writeRgbPng(
      shot,
      '$_outputDir/$file',
      expectWidth: _pixelWidth,
      expectHeight: _pixelHeight,
    ),
  );

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
  appImage.dispose();
  shot.dispose();
}

/// The iPhone template's green gradient and type, scaled to the iPad canvas,
/// with an iPad body (uniform bezel, no Dynamic Island) instead of a phone.
class _IpadTemplate extends StatelessWidget {
  const _IpadTemplate({
    required this.title,
    required this.subtitle,
    required this.screen,
  });

  final String title;
  final String subtitle;
  final ui.Image screen;

  // Same colours as the iPhone template.
  static const _top = Color(0xFF0B6B53);
  static const _bottom = Color(0xFF14A37F);

  /// Device screen scale relative to the canvas. The iPhone uses 0.73 of a
  /// 430pt-wide canvas; the iPad keeps a similar caption-to-device balance.
  static const _scale = 0.72;
  static const _bezel = 22.0;
  static const _screenRadius = 18.0;

  /// The iPhone template's type is set for a 430pt-wide canvas; scaled by
  /// width so the caption has the same visual weight on 1032pt.
  static const _type = 1032 / 430 * 0.7;

  @override
  Widget build(BuildContext context) {
    final screenW = _logicalSize.width * _scale;
    final screenH = _logicalSize.height * _scale;

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
                left: 64,
                right: 64,
                top: 88,
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 34 * _type,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5 * _type,
                      ),
                    ),
                    const SizedBox(height: 12 * _type),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 19 * _type,
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 300,
                left: (_logicalSize.width - screenW) / 2 - _bezel,
                child: Container(
                  padding: const EdgeInsets.all(_bezel),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111312),
                    borderRadius: BorderRadius.circular(_screenRadius + _bezel),
                    border: Border.all(
                      color: const Color(0xFF3A3F3D),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_screenRadius),
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
                          const _IpadStatusBar(scale: _scale),
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

/// iPadOS status bar: time and date on the left, Wi-Fi and battery on the
/// right, drawn over the app's top safe-area inset.
class _IpadStatusBar extends StatelessWidget {
  const _IpadStatusBar({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF111111);
    final style = TextStyle(
      fontFamily: 'Roboto',
      fontSize: 13 * scale,
      fontWeight: FontWeight.w600,
      color: ink,
    );
    return SizedBox(
      height: _safeTop * scale,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20 * scale),
        child: Row(
          children: [
            Text('9:41', style: style),
            SizedBox(width: 6 * scale),
            Text(
              'Tue Jun 9',
              style: style.copyWith(fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Icon(Icons.wifi, size: 15 * scale, color: ink),
            SizedBox(width: 6 * scale),
            Text('100%', style: style.copyWith(fontWeight: FontWeight.w500)),
            SizedBox(width: 4 * scale),
            RotatedBox(
              quarterTurns: 1,
              child: Icon(Icons.battery_full, size: 18 * scale, color: ink),
            ),
          ],
        ),
      ),
    );
  }
}
