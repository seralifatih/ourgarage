// Generates the App Store screenshots into `screenshots/`.
//
// Not part of the normal suite — it writes files and its dates move with the
// clock. Run it explicitly:
//
//   flutter test test/screenshots --dart-define=SCREENSHOTS=true
//
// or `tool/generate_screenshots.ps1`. Add
// `--dart-define=SCREENSHOT_SIZE=1206x2622` for the 6.3" set, written to
// `screenshots/1206x2622/`. Every file is an RGB PNG with no alpha channel.
//
// Each shot is made in two passes. First the real app (real router, real
// screens, DemoData in an in-memory Drift database, fake RevenueCat / auth /
// notifications — nothing touches a real service) renders full-screen at the
// configured iPhone logical size and is captured. Then that capture is placed
// in the green marketing template (title, subtitle, iPhone frame) and the
// template is captured at the configured pixel size (1290x2796 by default).
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;
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

/// Output size in pixels, `WIDTHxHEIGHT`, at 3x. The default is iPhone 6.7"
/// (430x932 points); `--dart-define=SCREENSHOT_SIZE=1206x2622` gives iPhone
/// 6.3" (402x874 points).
const _sizeSpec = String.fromEnvironment(
  'SCREENSHOT_SIZE',
  defaultValue: '1290x2796',
);
const _pixelRatio = 3.0;

final _pixelSize = () {
  final parts = _sizeSpec.split('x').map(int.parse).toList();
  return (width: parts[0], height: parts[1]);
}();

final _logicalSize = Size(
  _pixelSize.width / _pixelRatio,
  _pixelSize.height / _pixelRatio,
);

/// The default size keeps its original location; other sizes get their own
/// folder.
const _outputDir = _sizeSpec == '1290x2796'
    ? 'screenshots'
    : 'screenshots/$_sizeSpec';

/// iPhone safe-area insets, in points.
const _safeTop = 59.0;
const _safeBottom = 34.0;

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

/// Writes [image] as an 8-bit RGB PNG — no alpha channel, which App Store
/// Connect rejects in screenshots. The engine's own PNG encoder always
/// writes RGBA, so this encodes by hand: one IHDR, one zlib IDAT, IEND.
Future<void> _writePng(ui.Image image, String path) async {
  final width = image.width;
  final height = image.height;
  if (width != _pixelSize.width || height != _pixelSize.height) {
    throw StateError(
      'Rendered ${width}x$height, expected '
      '${_pixelSize.width}x${_pixelSize.height}',
    );
  }

  final rgba = (await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!.buffer.asUint8List();

  // Each scanline: filter byte 0 (none), then R,G,B per pixel.
  final raw = Uint8List(height * (1 + width * 3));
  var out = 0;
  for (var y = 0; y < height; y++) {
    raw[out++] = 0;
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      // Dropping alpha is only lossless if the frame is fully opaque, which
      // the template's full-bleed background guarantees. Fail loudly if not.
      if (rgba[i + 3] != 255) {
        throw StateError('Transparent pixel at ($x, $y)');
      }
      raw[out++] = rgba[i];
      raw[out++] = rgba[i + 1];
      raw[out++] = rgba[i + 2];
    }
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // colour type 2: truecolour RGB
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter
    ..setUint8(12, 0); // interlace

  final png = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_pngChunk('IHDR', header.buffer.asUint8List()))
    ..add(_pngChunk('IDAT', ZLibEncoder(level: 9).convert(raw)))
    ..add(_pngChunk('IEND', const []));

  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png.takeBytes());
}

List<int> _pngChunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
  return [
    ...length.buffer.asUint8List(),
    ...typeBytes,
    ...data,
    ...crc.buffer.asUint8List(),
  ];
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
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
              // Same position across all shots, fully inside the canvas.
              // Tuned at 932pt tall and scaled for other heights.
              Positioned(
                top: 206 * _logicalSize.height / 932,
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
