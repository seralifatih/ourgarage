// Shared plumbing for the App Store screenshot scripts: RGB PNG output, fonts,
// capture and the extra demo reminder rules. Used by
// ipad_app_store_screenshots_test.dart; the same code also lives privately in
// app_store_screenshots_test.dart (iPhone), which predates this file.
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/debug/demo_data.dart';

/// Finite pumps: loading spinners animate forever, so no pumpAndSettle.
Future<void> settleFrames(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<ui.Image> captureBoundary(
  WidgetTester tester,
  GlobalKey key,
  double pixelRatio,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(
    () => boundary.toImage(pixelRatio: pixelRatio),
  );
  return image!;
}

/// Writes [image] as an 8-bit RGB PNG — no alpha channel, which App Store
/// Connect rejects in screenshots. The engine's PNG encoder always writes
/// RGBA, so this encodes by hand: one IHDR, one zlib IDAT, IEND.
Future<void> writeRgbPng(
  ui.Image image,
  String path, {
  required int expectWidth,
  required int expectHeight,
}) async {
  final width = image.width;
  final height = image.height;
  if (width != expectWidth || height != expectHeight) {
    throw StateError(
      'Rendered ${width}x$height, expected ${expectWidth}x$expectHeight',
    );
  }

  final rgba = (await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!.buffer.asUint8List();

  final raw = Uint8List(height * (1 + width * 3));
  var out = 0;
  for (var y = 0; y < height; y++) {
    raw[out++] = 0; // filter: none
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      // Dropping alpha is only lossless on a fully opaque frame, which the
      // template's full-bleed background guarantees. Fail loudly if not.
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
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);

  final png = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', header.buffer.asUint8List()))
    ..add(_chunk('IDAT', ZLibEncoder(level: 9).convert(raw)))
    ..add(_chunk('IEND', const []));

  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png.takeBytes());
}

List<int> _chunk(String type, List<int> data) {
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

/// The same extra reminder rules the iPhone script adds for shot 02.
Future<void> addDemoRule(
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

/// Real fonts instead of the test runner's Ahem boxes. Roboto and Material
/// Icons ship with the Flutter SDK.
Future<void> loadScreenshotFonts() async {
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
