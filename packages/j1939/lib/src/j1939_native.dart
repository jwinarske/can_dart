// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// j1939_native.dart — low-level dart:ffi bindings for j1939_ffi.h
//
// Nothing outside j1939.dart should call these directly.
// They have no null checks, no error translation, and no isolate guards.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class J1939Handle extends Opaque {}

// ── Dynamic library resolution ───────────────────────────────────────────────
//
// Resolution order:
//
//   1. System loader via DynamicLibrary.open('libj1939_plugin.so').
//      Works when the user installed the .so system-wide or set
//      LD_LIBRARY_PATH.
//
//   2. `.dart_tool/hooks_runner/shared/j1939/build/**/libj1939_plugin.so`
//      — the artifact produced by hook/build.dart for plain `dart run` /
//      `dart test`. Newest mtime wins.
//
//   3. Bundle-relative paths derived from Platform.script (for
//      Flutter-bundled / AOT-compiled layouts where the .so lives in
//      `lib/` next to the snapshot).
//
//   4. Sibling-of-libapp.so via /proc/self/maps — fallback for embedders
//      like ivi-homescreen where the Flutter bundle's lib dir is not on
//      LD_LIBRARY_PATH.
//
//   5. LD_LIBRARY_PATH directories opened by absolute path.
//
// Patterned after https://github.com/meta-flutter/appstream_dart/blob/main/lib/src/bindings.dart

const String _libName = 'libj1939_plugin.so';

final DynamicLibrary _lib = _openLibrary();

DynamicLibrary _openLibrary() {
  final errors = <String>[];

  // 1. System loader first.
  try {
    return DynamicLibrary.open(_libName);
  } catch (e) {
    errors.add('dlopen($_libName): $e');
  }

  final candidates = <String>[];

  // 2. .dart_tool/hooks_runner artifact for `dart run` / `dart test`.
  final fromHook = _findInHooksRunner(_libName);
  if (fromHook != null) candidates.add(fromHook);

  // 3. Bundle-relative paths derived from Platform.script.
  try {
    final scriptDir = File(Platform.script.toFilePath()).parent.path;
    candidates.addAll([
      '$scriptDir/lib/$_libName',
      '$scriptDir/../lib/$_libName',
      '$scriptDir/../../lib/$_libName',
      '$scriptDir/../../../lib/$_libName',
    ]);
  } catch (_) {}

  // 4. Sibling of a Flutter-bundled .so via /proc/self/maps.
  final fromMaps = _findSiblingOfLoadedLib(_libName);
  if (fromMaps != null) candidates.add(fromMaps);

  // 5. Executable- and CWD-relative paths.
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  candidates.addAll([
    '$exeDir/lib/$_libName',
    '$exeDir/$_libName',
    '${Directory.current.path}/lib/$_libName',
    '${Directory.current.path}/build/$_libName',
  ]);

  // 6. LD_LIBRARY_PATH directories opened by absolute path.
  final ldPath = Platform.environment['LD_LIBRARY_PATH'] ?? '';
  for (final dir in ldPath.split(':')) {
    if (dir.isNotEmpty) candidates.add('$dir/$_libName');
  }

  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      try {
        return DynamicLibrary.open(file.absolute.path);
      } catch (e) {
        errors.add('${file.absolute.path}: $e');
      }
    }
  }

  throw StateError(
    'Failed to load $_libName. Searched:\n'
    '  dlopen($_libName) via system loader\n'
    '${candidates.map((p) => '  $p (${File(p).existsSync() ? "exists" : "not found"})').join('\n')}\n'
    'Errors:\n${errors.join('\n')}\n'
    'Platform.resolvedExecutable=${Platform.resolvedExecutable}\n'
    'Platform.script=${Platform.script}\n'
    'Directory.current=${Directory.current.path}\n'
    'LD_LIBRARY_PATH=${Platform.environment['LD_LIBRARY_PATH'] ?? '(not set)'}',
  );
}

/// Walk up from CWD looking for the most recent shared library produced
/// by the `package:hooks` build runner. Lets plain `dart run` / `dart test`
/// invocations pick up the artifact built by `hook/build.dart` automatically.
String? _findInHooksRunner(String libName) {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final root = Directory(
      '${dir.path}/.dart_tool/hooks_runner/shared/j1939/build',
    );
    if (root.existsSync()) {
      File? newest;
      var newestTime = DateTime.fromMillisecondsSinceEpoch(0);
      for (final entity in root.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('/$libName')) {
          final mtime = entity.statSync().modified;
          if (mtime.isAfter(newestTime)) {
            newest = entity;
            newestTime = mtime;
          }
        }
      }
      if (newest != null) return newest.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

/// Walk /proc/self/maps to find a directory that already has a
/// Flutter-bundled .so loaded (libapp.so, libflutter_*.so, or any other
/// library mapped from a path ending in `/lib/`), and return
/// `<that dir>/<libName>` if it exists on disk.
String? _findSiblingOfLoadedLib(String libName) {
  try {
    final maps = File('/proc/self/maps');
    if (!maps.existsSync()) return null;

    final seen = <String>{};
    final preferred = <String>[];
    final fallback = <String>[];

    for (final line in maps.readAsLinesSync()) {
      final lastSpace = line.lastIndexOf(' ');
      if (lastSpace < 0) continue;
      final path = line.substring(lastSpace + 1);
      if (!path.startsWith('/')) continue;

      final slash = path.lastIndexOf('/');
      if (slash <= 0) continue;
      final dir = path.substring(0, slash);
      if (!seen.add(dir)) continue;

      final base = path.substring(slash + 1);
      if (dir.endsWith('/lib') ||
          base == 'libapp.so' ||
          base.startsWith('libflutter_')) {
        preferred.add(dir);
      } else {
        fallback.add(dir);
      }
    }

    for (final dir in [...preferred, ...fallback]) {
      final candidate = '$dir/$libName';
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  } catch (_) {
    return null;
  }
}

// ── Bindings ──────────────────────────────────────────────────────────────────

// Pass NativeApi.postCObject.cast<Void>() once before j1939Create().
final void Function(Pointer<Void>) j1939SetPostCObject = _lib.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)>('j1939_set_post_cobject');

final Pointer<J1939Handle> Function(Pointer<Utf8>, int, int, int, int, int)
    j1939Create = _lib.lookupFunction<
        Pointer<J1939Handle> Function(
            Pointer<Utf8>, Uint8, Uint32, Uint16, Uint8, Int64),
        Pointer<J1939Handle> Function(
            Pointer<Utf8>, int, int, int, int, int)>('j1939_create');

final int Function() j1939LastError =
    _lib.lookupFunction<Int32 Function(), int Function()>('j1939_last_error');

final void Function(Pointer<J1939Handle>) j1939Destroy = _lib.lookupFunction<
    Void Function(Pointer<J1939Handle>),
    void Function(Pointer<J1939Handle>)>('j1939_destroy');

// Synchronous send — blocks for BAM (> 8 bytes).
// Prefer j1939SendAsync for large payloads.
final int Function(Pointer<J1939Handle>, int, int, int, Pointer<Uint8>, int)
    j1939Send = _lib.lookupFunction<
        Int32 Function(
            Pointer<J1939Handle>, Uint32, Uint8, Uint8, Pointer<Uint8>, Uint16),
        int Function(Pointer<J1939Handle>, int, int, int, Pointer<Uint8>,
            int)>('j1939_send');

final int Function(Pointer<J1939Handle>, int, int) j1939SendRequest =
    _lib.lookupFunction<Int32 Function(Pointer<J1939Handle>, Uint8, Uint32),
        int Function(Pointer<J1939Handle>, int, int)>('j1939_send_request');

// Asynchronous send — returns immediately.
// Completion posted as type-5 event: [Int32:5, Int32:send_id, Int32:errno]
final void Function(
        Pointer<J1939Handle>, int, int, int, int, Pointer<Uint8>, int)
    j1939SendAsync = _lib.lookupFunction<
        Void Function(Pointer<J1939Handle>, Int32, Uint32, Uint8, Uint8,
            Pointer<Uint8>, Uint16),
        void Function(Pointer<J1939Handle>, int, int, int, int, Pointer<Uint8>,
            int)>('j1939_send_async');

final void Function(Pointer<J1939Handle>, int, int, int) j1939AddDm1Fault =
    _lib.lookupFunction<
        Void Function(Pointer<J1939Handle>, Uint32, Uint8, Uint8),
        void Function(
            Pointer<J1939Handle>, int, int, int)>('j1939_add_dm1_fault');

final void Function(Pointer<J1939Handle>) j1939ClearDm1Faults =
    _lib.lookupFunction<Void Function(Pointer<J1939Handle>),
        void Function(Pointer<J1939Handle>)>('j1939_clear_dm1_faults');

final int Function(Pointer<J1939Handle>) j1939Address = _lib.lookupFunction<
    Uint8 Function(Pointer<J1939Handle>),
    int Function(Pointer<J1939Handle>)>('j1939_address');

final bool Function(Pointer<J1939Handle>) j1939AddressClaimed =
    _lib.lookupFunction<Bool Function(Pointer<J1939Handle>),
        bool Function(Pointer<J1939Handle>)>('j1939_address_claimed');

// ── NMEA 2000 extensions ────────────────────────────────────────────────────

// Full NAME create — exposes all J1939 NAME fields for NMEA 2000.
final Pointer<J1939Handle> Function(
        Pointer<Utf8>, int, int, int, int, int, int, int, int, int)
    j1939CreateFull = _lib.lookupFunction<
        Pointer<J1939Handle> Function(Pointer<Utf8>, Uint8, Uint32, Uint16,
            Uint8, Uint8, Uint8, Uint8, Uint8, Int64),
        Pointer<J1939Handle> Function(Pointer<Utf8>, int, int, int, int, int,
            int, int, int, int)>('j1939_create_full');

// Register a PGN transport type at runtime (0=single, 1=fast_packet, 2=iso_tp).
final void Function(int, int) nmea2000SetPgnTransport = _lib.lookupFunction<
    Void Function(Uint32, Uint8),
    void Function(int, int)>('nmea2000_set_pgn_transport');
