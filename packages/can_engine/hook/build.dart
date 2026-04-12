// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0
//
// Compiles libcan_engine.so via CMake (Asio + Glaze) and registers it as a
// CodeAsset. Supports Linux x64 and ARM64.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final os = input.config.code.targetOS;
    if (os != OS.linux) return;

    final arch = input.config.code.targetArchitecture;
    final cmakeArch = switch (arch) {
      Architecture.x64 => 'x86_64',
      Architecture.arm64 => 'aarch64',
      _ =>
        throw UnsupportedError(
          'can_engine does not support architecture: $arch',
        ),
    };

    final srcDir = input.packageRoot;
    final buildDir = Directory.fromUri(
      input.outputDirectory.resolve('can_engine_build_$cmakeArch/'),
    );
    await buildDir.create(recursive: true);

    // Configure
    final configure = await Process.run('cmake', [
      srcDir.toFilePath(),
      '-GNinja',
      '-DCMAKE_BUILD_TYPE=Release',
    ], workingDirectory: buildDir.path);
    if (configure.exitCode != 0) {
      stderr.writeln('can_engine: cmake configure failed\n${configure.stderr}');
      return;
    }

    // Build
    final buildResult = await Process.run('cmake', [
      '--build',
      '.',
      '--parallel',
    ], workingDirectory: buildDir.path);
    if (buildResult.exitCode != 0) {
      stderr.writeln('can_engine: cmake build failed\n${buildResult.stderr}');
      return;
    }

    final so = Uri.file('${buildDir.path}/libcan_engine.so');

    output.assets.code.add(
      CodeAsset(
        package: 'can_engine',
        name: 'src/can_engine.dart',
        file: so,
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}
