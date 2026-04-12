// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Optional test: validates DbcParser against two public DBC corpora.
//
// Skipped by default. Opt in with an environment variable:
//
//   CAN_DBC_NETWORK_TESTS=1 dart test
//   CAN_DBC_NETWORK_TESTS=1 dart test test/external_dbc_test.dart
//
// The test shallow-clones each source repository once into
// `.dart_tool/external_dbc_cache/<owner_repo>/` and reuses that clone on
// subsequent runs. Delete the cache directory to force a refresh.
//
// Requires `git` in PATH and network access to github.com. Tests mark
// themselves skipped (not failed) when either is unavailable, so enabling
// the env var in an offline CI environment is still safe.

import 'dart:io';

import 'package:can_dbc/can_dbc.dart';
import 'package:test/test.dart';

class _Source {
  final String name; // owner/repo — used for the cache subdir
  final String gitUrl; // https URL for shallow clone
  final String dbcSubdir; // path within the repo that contains .dbc files
  final bool recursive; // walk subdirs or use only the top level
  const _Source(
    this.name,
    this.gitUrl,
    this.dbcSubdir, {
    this.recursive = true,
  });
}

const _sources = <_Source>[
  _Source(
    'Konik-ai/j1939_dbc',
    'https://github.com/Konik-ai/j1939_dbc.git',
    'dbc',
  ),

  // commaai/opendbc:
  //   opendbc/dbc/*.dbc         — 58 consumer-facing vehicle DBCs (what we
  //                               want to validate)
  //   opendbc/dbc/generator/**  — 57 build-system fragments / templates
  //                               that are included into the real DBCs by a
  //                               preprocessing step. They are NOT valid as
  //                               standalone DBC files (e.g. some contain
  //                               malformed `CM_ SG_` comments that only
  //                               resolve after generation). Excluded here.
  _Source(
    'commaai/opendbc',
    'https://github.com/commaai/opendbc.git',
    'opendbc/dbc',
    recursive: false,
  ),

  // canboat/canboat: NMEA 2000 / marine PGN database exported as DBC.
  // Single file at dbc-exporter/pgns.dbc (~2K lines, ~170 messages).
  _Source(
    'canboat/canboat',
    'https://github.com/canboat/canboat.git',
    'dbc-exporter',
  ),
];

String get _cacheRoot =>
    '${Directory.current.path}/.dart_tool/external_dbc_cache';

String _cacheDirFor(_Source s) => '$_cacheRoot/${s.name.replaceAll('/', '_')}';

Future<bool> _hasGit() async {
  try {
    final r = await Process.run('git', ['--version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<void> _ensureCloned(_Source s) async {
  final dir = Directory(_cacheDirFor(s));
  if (Directory('${dir.path}/.git').existsSync()) return;

  if (dir.existsSync()) dir.deleteSync(recursive: true);
  await Directory(_cacheRoot).create(recursive: true);

  final r = await Process.run('git', [
    'clone',
    '--depth',
    '1',
    '--quiet',
    s.gitUrl,
    dir.path,
  ]);
  if (r.exitCode != 0) {
    throw StateError(
      'git clone ${s.gitUrl} failed (exit ${r.exitCode}): ${r.stderr}',
    );
  }
}

List<File> _listDbcs(String root, {required bool recursive}) {
  final d = Directory(root);
  if (!d.existsSync()) {
    throw StateError('DBC directory not found: $root');
  }
  return d
      .listSync(recursive: recursive)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.dbc'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

const _optInEnvVar = 'CAN_DBC_NETWORK_TESTS';

void main() {
  late bool gitAvailable;

  setUpAll(() async {
    gitAvailable = await _hasGit();
  });

  for (final source in _sources) {
    group('external DBC coverage - ${source.name}', () {
      test(
        'every .dbc parses via DbcParser',
        () async {
          if (Platform.environment[_optInEnvVar] != '1') {
            markTestSkipped(
              'set $_optInEnvVar=1 to enable external-corpus tests',
            );
            return;
          }
          if (!gitAvailable) {
            markTestSkipped('git not available in PATH');
            return;
          }

          try {
            await _ensureCloned(source);
          } on StateError catch (e) {
            markTestSkipped('clone skipped: ${e.message}');
            return;
          }

          final dbcDir = '${_cacheDirFor(source)}/${source.dbcSubdir}';
          final files = _listDbcs(dbcDir, recursive: source.recursive);
          expect(
            files,
            isNotEmpty,
            reason: 'expected at least one .dbc under $dbcDir',
          );

          final failures = <String>[];
          var totalMessages = 0;
          var totalSignals = 0;

          for (final f in files) {
            final rel = f.path.substring(_cacheDirFor(source).length + 1);
            try {
              final db = await DbcParser().parseFile(f.path);
              totalMessages += db.messages.length;
              totalSignals += db.signalCount;
            } on DbcParseException catch (e) {
              failures.add('$rel: ${e.message} @${e.line}:${e.column}');
            } catch (e) {
              failures.add('$rel: $e');
            }
          }

          final summary =
              '${files.length} files parsed, '
              '$totalMessages messages, '
              '$totalSignals signals, '
              '${failures.length} failed';
          printOnFailure(summary);

          if (failures.isNotEmpty) {
            fail(
              '$summary\n\n'
              'Parse failures (${failures.length}):\n'
              '  ${failures.join('\n  ')}',
            );
          }

          // On success, also log the aggregate for visibility when running
          // with `dart test -r expanded`.
          // ignore: avoid_print
          print('[${source.name}] $summary');
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    });
  }
}
