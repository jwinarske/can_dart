// Native assets build hook for j1939.
//
// Drives the project's CMake build to compile libj1939_plugin.so, then
// declares the resulting shared library as a CodeAsset under the asset id
// `package:j1939/src/j1939_native.dart`.
//
// Patterned after https://github.com/meta-flutter/appstream_dart/blob/main/hook/build.dart
//
// Note: j1939's CMakeLists.txt gates the j1939_plugin target on a DART_SDK
// option (it needs dart_api_dl.h / dart_native_api.h for Dart_PostCObject_DL).
// This hook derives the SDK root from Platform.resolvedExecutable and passes
// it through as -DDART_SDK=<root>.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    if (input.config.code.targetOS != OS.linux) {
      stderr.writeln('j1939: only Linux is supported — skipping native build.');
      return;
    }

    if (Platform.environment.containsKey('SKIP_NATIVE_BUILD')) {
      stderr.writeln('SKIP_NATIVE_BUILD set — skipping j1939 native build.');
      return;
    }

    final pkgRoot = input.packageRoot.toFilePath();
    final buildDir = input.outputDirectory.resolve('cmake/').toFilePath();

    await Directory(buildDir).create(recursive: true);

    final dartSdkRoot = _findDartSdkRoot();
    if (dartSdkRoot == null) {
      throw StateError(
        'j1939: could not locate a Dart SDK with include/dart_api_dl.h.\n'
        'Tried Platform.resolvedExecutable=${Platform.resolvedExecutable}.\n'
        'Set DART_SDK in the environment to override.',
      );
    }

    final hasNinja = await _which('ninja');

    if (!File('${buildDir}CMakeCache.txt').existsSync()) {
      await _run('cmake', [
        '-S',
        pkgRoot,
        '-B',
        buildDir,
        '-DCMAKE_BUILD_TYPE=Release',
        '-DDART_SDK=$dartSdkRoot',
        if (hasNinja) ...['-G', 'Ninja'],
      ]);
    }

    await _run('cmake', [
      '--build',
      buildDir,
      '--target',
      'j1939_plugin',
      '--parallel',
    ]);

    final libFile = File('${buildDir}libj1939_plugin.so');
    if (!libFile.existsSync()) {
      throw StateError('libj1939_plugin.so not found at ${libFile.path}');
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/j1939_native.dart',
        linkMode: DynamicLoadingBundled(),
        file: libFile.uri,
      ),
    );

    // Re-run the hook whenever any C/C++ source or CMake file changes.
    for (final dir in ['src', 'ffi']) {
      final d = Directory('$pkgRoot/$dir');
      if (!d.existsSync()) continue;
      for (final entity in d.listSync(recursive: true)) {
        if (entity is! File) continue;
        final p = entity.path;
        if (p.endsWith('.cpp') ||
            p.endsWith('.cc') ||
            p.endsWith('.c') ||
            p.endsWith('.hpp') ||
            p.endsWith('.h')) {
          output.dependencies.add(entity.uri);
        }
      }
    }
    output.dependencies.add(Uri.file('$pkgRoot/CMakeLists.txt'));

    stderr.writeln('j1939_plugin built: ${libFile.path}');
  });
}

/// Derive the Dart SDK root that contains `include/dart_api_dl.h`.
///
/// 1. `DART_SDK` env var, if set and valid.
/// 2. `parent.parent` of `Platform.resolvedExecutable` — the canonical
///    layout `<sdk>/bin/dart`. For Flutter this resolves to
///    `<flutter>/bin/cache/dart-sdk/bin/dart`, whose `parent.parent` is
///    the correct dart-sdk root.
String? _findDartSdkRoot() {
  bool looksLikeSdk(String root) =>
      File('$root/include/dart_api_dl.h').existsSync() &&
      File('$root/include/dart_native_api.h').existsSync();

  final envSdk = Platform.environment['DART_SDK'];
  if (envSdk != null && envSdk.isNotEmpty && looksLikeSdk(envSdk)) {
    return envSdk;
  }

  final exe = File(Platform.resolvedExecutable);
  final candidate = exe.parent.parent.path;
  if (looksLikeSdk(candidate)) return candidate;

  return null;
}

Future<void> _run(String exe, List<String> args) async {
  final p = await Process.start(exe, args, mode: ProcessStartMode.inheritStdio);
  final code = await p.exitCode;
  if (code != 0) {
    throw ProcessException(exe, args, 'exit code $code', code);
  }
}

Future<bool> _which(String exe) async {
  final r = await Process.run('which', [exe]);
  return r.exitCode == 0;
}
