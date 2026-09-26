// Host-side runner for the on-device benchmark (integration_test/
// benchmark_test.dart). It builds and installs the example app in debug mode
// through `flutter test`, pushes the dataset into the app's private files
// directory with `run-as`, waits for the pipeline to run on every image and
// pulls results.json back. The app is uninstalled at the end.
//
// Usage, from the example directory:
//   dart run tool/benchmark/run_on_device.dart --dataset <dir> --out <file>
//   dart run tool/benchmark/run_on_device.dart --photos <dir> --out <file>
//
// --dataset <dir>    a folder with labels.json (as written by generate.py).
// --photos <dir>     a folder of real card photos (.jpg/.jpeg/.png), each
//                    named <code>.jpg (anything after the first "_" is
//                    ignored, so 12345678901234_2.jpg works), or listed in a
//                    labels.csv with the columns file,code[,serial].
// --out <file>       where to write the results JSON (default
//                    build/benchmark/results.json).
// --config <file>    optional JSON with {"variants": [{"name": ..,
//                    "prepare": {..}, "policy": {..}, "layout": {..}}]} to
//                    compare settings in one run (see README.md).
// --code-lengths     for --photos: accepted code lengths, e.g. 14,15,16
//                    (default: the lengths found in the labels).
// --serial-lengths   for --photos: accepted serial lengths (default: the
//                    lengths of the labelled serials; serial is not read
//                    when no photo has one).
// --device <id>      adb device id (default emulator-5554).
// --keep-app         do not uninstall the example app at the end.
//
// adb is taken from $ADB, else $ANDROID_HOME/platform-tools, else PATH.
// Needs `tar` on the host and a debug build (run-as only works for debug).

import 'dart:convert';
import 'dart:io';

const _appId = 'biz.abdeldjalilchougui.recharge_card_ocr_example';
const _imageExtensions = {'.jpg', '.jpeg', '.png'};

Future<void> main(List<String> argv) async {
  final args = _Args.parse(argv);
  final adb = _adbPath();
  final stage = await Directory.systemTemp.createTemp('rco_bench_');
  try {
    final tar = await _stage(args, stage);
    final ok = await _run(args, adb, tar);
    exitCode = ok ? 0 : 1;
  } finally {
    await stage.delete(recursive: true);
    if (!args.keepApp) await _uninstall(adb, args.device);
  }
}

/// Removes the example app unless `flutter test` already did.
Future<void> _uninstall(String adb, String device) async {
  final list = await Process.run(adb, [
    '-s',
    device,
    'shell',
    'pm list packages $_appId',
  ]);
  if (!'${list.stdout}'.contains('package:$_appId')) {
    stdout.writeln('[bench] $_appId is not installed (already removed)');
    return;
  }
  final r = await Process.run(adb, ['-s', device, 'uninstall', _appId]);
  stdout.writeln('[bench] uninstall $_appId: ${'${r.stdout}'.trim()}');
}

class _Args {
  String? dataset;
  String? photos;
  String out = 'build/benchmark/results.json';
  String? config;
  List<int>? codeLengths;
  List<int>? serialLengths;
  String device = 'emulator-5554';
  bool keepApp = false;

  static _Args parse(List<String> argv) {
    final a = _Args();
    List<int> ints(String s) => [for (final p in s.split(',')) int.parse(p)];
    for (var i = 0; i < argv.length; i++) {
      String next() {
        if (i + 1 >= argv.length) _usage('missing value for ${argv[i]}');
        return argv[++i];
      }

      switch (argv[i]) {
        case '--dataset':
          a.dataset = next();
        case '--photos':
          a.photos = next();
        case '--out':
          a.out = next();
        case '--config':
          a.config = next();
        case '--code-lengths':
          a.codeLengths = ints(next());
        case '--serial-lengths':
          a.serialLengths = ints(next());
        case '--device':
          a.device = next();
        case '--keep-app':
          a.keepApp = true;
        default:
          _usage('unknown argument ${argv[i]}');
      }
    }
    if ((a.dataset == null) == (a.photos == null)) {
      _usage('give exactly one of --dataset or --photos');
    }
    return a;
  }
}

Never _usage(String message) {
  stderr.writeln('error: $message');
  stderr.writeln(
    'usage: dart run tool/benchmark/run_on_device.dart '
    '(--dataset <dir> | --photos <dir>) [--out <file>] [--config <file>] '
    '[--code-lengths 14,15,16] [--serial-lengths 12] [--device <id>] '
    '[--keep-app]',
  );
  exit(64);
}

/// Writes labels.json (+ config.json) and the images into a tar file.
Future<File> _stage(_Args args, Directory stage) async {
  final String root;
  final Map<String, dynamic> labels;
  if (args.dataset != null) {
    root = args.dataset!;
    labels =
        jsonDecode(File('$root/labels.json').readAsStringSync())
            as Map<String, dynamic>;
  } else {
    root = args.photos!;
    labels = _photoLabels(root, args);
  }
  final images = labels['images'] as List<dynamic>;
  if (images.isEmpty) _usage('no images found in $root');
  final list = File('${stage.path}/files.txt');
  list.writeAsStringSync(
    images.map((e) => (e as Map<String, dynamic>)['file']).join('\n'),
  );
  File(
    '${stage.path}/labels.json',
  ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(labels));
  if (args.config != null) {
    File(args.config!).copySync('${stage.path}/config.json');
  }
  final tar = File('${stage.path}/bench.tar');
  var r = await Process.run('tar', [
    '-cf',
    tar.path,
    '-C',
    root,
    '-T',
    list.path,
  ]);
  if (r.exitCode != 0) throw StateError('tar failed: ${r.stderr}');
  final extra = ['labels.json', if (args.config != null) 'config.json'];
  r = await Process.run('tar', ['-rf', tar.path, '-C', stage.path, ...extra]);
  if (r.exitCode != 0) throw StateError('tar failed: ${r.stderr}');
  stdout.writeln(
    '[bench] ${images.length} images staged '
    '(${(tar.lengthSync() / 1e6).toStringAsFixed(1)} MB)',
  );
  return tar;
}

/// Builds labels for a folder of real photos.
Map<String, dynamic> _photoLabels(String root, _Args args) {
  final entries = <Map<String, dynamic>>[];
  final csv = File('$root/labels.csv');
  if (csv.existsSync()) {
    for (final raw in csv.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final cols = [for (final c in line.split(',')) c.trim()];
      if (cols[0].toLowerCase() == 'file') continue; // header
      if (cols.length < 2) _usage('labels.csv line needs file,code: $line');
      if (!File('$root/${cols[0]}').existsSync()) {
        _usage('labels.csv names a missing file: ${cols[0]}');
      }
      entries.add({
        'file': cols[0],
        'code': cols[1].replaceAll(RegExp(r'\D'), ''),
        if (cols.length > 2 && cols[2].isNotEmpty)
          'serial': cols[2].replaceAll(RegExp(r'\D'), ''),
        'conditions': [
          'real',
          if (cols.length > 3 && cols[3].isNotEmpty) ...cols[3].split(';'),
        ],
      });
    }
  } else {
    final files =
        Directory(root)
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  _imageExtensions.contains(_extension(f.path).toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      final stem = name.substring(0, name.lastIndexOf('.')).split('_').first;
      final code = stem.replaceAll(RegExp(r'\D'), '');
      if (code.isEmpty) {
        stderr.writeln('[bench] skipping $name: no digits in the name');
        continue;
      }
      entries.add({
        'file': name,
        'code': code,
        'conditions': ['real'],
      });
    }
  }
  final codeLengths =
      args.codeLengths ??
      ({for (final e in entries) (e['code'] as String).length}.toList()
        ..sort());
  final serials = [
    for (final e in entries)
      if (e['serial'] != null) e['serial'] as String,
  ];
  final serialLengths =
      args.serialLengths ??
      ({for (final s in serials) s.length}.toList()..sort());
  return {
    'version': 1,
    'source': 'real',
    'spec': {
      'code': {'lengths': codeLengths},
      if (serialLengths.isNotEmpty) 'serial': {'lengths': serialLengths},
    },
    'images': entries,
  };
}

String _extension(String path) {
  final i = path.lastIndexOf('.');
  return i < 0 ? '' : path.substring(i);
}

Future<bool> _run(_Args args, String adb, File tar) async {
  final flutter = await Process.start('flutter', [
    'test',
    'integration_test/benchmark_test.dart',
    '-d',
    args.device,
  ]);
  // Forward with listen (not addStream) so other processes can also write
  // to stderr while flutter runs.
  flutter.stderr.listen(stderr.add);
  final marker = RegExp(r'@@BENCH@@(\w+)@@(.*)$');
  var pulled = false;
  var queue = Future<void>.value();
  await flutter.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
        stdout.writeln(line);
        final m = marker.firstMatch(line);
        if (m == null) return;
        switch (m.group(1)) {
          case 'ready':
            queue = queue.then((_) => _push(adb, args.device, tar));
          case 'done':
            queue = queue.then((_) async {
              pulled = await _pull(adb, args.device, args.out);
            });
        }
      });
  await queue;
  final code = await flutter.exitCode;
  if (!pulled) stderr.writeln('[bench] no results were pulled');
  return code == 0 && pulled;
}

/// Runs `adb -s <device> <args>` and throws when it fails.
Future<void> _adb(String adb, String device, List<String> args) async {
  final r = await Process.run(adb, ['-s', device, ...args]);
  if (r.exitCode != 0) {
    throw StateError('adb ${args.join(' ')} failed: ${r.stdout}${r.stderr}');
  }
}

Future<void> _push(String adb, String device, File tar) async {
  stdout.writeln('[bench] pushing dataset into the app');
  // Streaming a large tar through `adb exec-in` stops early on some adb
  // versions, so push the file first and unpack it on the device.
  const remote = '/data/local/tmp/rco_bench.tar';
  await _adb(adb, device, ['push', tar.path, remote]);
  try {
    await _adb(adb, device, [
      'shell',
      "cat $remote | run-as $_appId sh -c 'rm -rf files/bench && "
          "mkdir -p files/bench && cd files/bench && tar -xf -'",
    ]);
  } finally {
    await _adb(adb, device, ['shell', 'rm -f $remote']);
  }
  await _adb(adb, device, [
    'shell',
    'run-as $_appId ls files/bench/labels.json',
  ]);
  await _adb(adb, device, [
    'shell',
    'run-as $_appId touch files/bench/.pushed',
  ]);
}

Future<bool> _pull(String adb, String device, String out) async {
  final p = await Process.start(adb, [
    '-s',
    device,
    'exec-out',
    'run-as $_appId cat files/bench/results.json',
  ]);
  final bytes = <int>[];
  await p.stdout.forEach(bytes.addAll);
  final code = await p.exitCode;
  var ok = code == 0 && bytes.isNotEmpty;
  if (ok) {
    try {
      jsonDecode(utf8.decode(bytes));
      final file = File(out)..parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      stdout.writeln('[bench] results written to ${file.path}');
    } on FormatException catch (e) {
      stderr.writeln('[bench] results.json is not valid JSON: $e');
      ok = false;
    }
  }
  await _adb(adb, device, [
    'shell',
    'run-as $_appId touch files/bench/.pulled',
  ]);
  return ok;
}

String _adbPath() {
  final env = Platform.environment;
  final explicit = env['ADB'];
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final home = env['ANDROID_HOME'] ?? env['ANDROID_SDK_ROOT'];
  if (home != null) {
    final candidate = '$home/platform-tools/adb';
    if (File(candidate).existsSync()) return candidate;
  }
  return 'adb';
}
