import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// probe/linux/besideos-grub.sh against a scratch GRUB directory and a tiny fake ISO (no root needed).
void main() {
  final script = File('probe/linux/besideos-grub.sh').absolute.path;
  final haveTools = Platform.isLinux &&
      Process.runSync('sh', ['-c', 'command -v xorriso && command -v findmnt']).exitCode == 0;

  late Directory work;
  late File iso;
  late Map<String, String> env;

  Future<ProcessResult> run(List<String> args) =>
      Process.run('bash', [script, ...args], environment: env);

  setUp(() {
    // Under the project (not /tmp): GRUB cannot read tmpfs, so the script refuses ISOs there.
    work = Directory('.dart_tool/grub_script_test').absolute..createSync(recursive: true);
    final tree = Directory('${work.path}/tree/boot/grub')..createSync(recursive: true);
    File('${tree.path}/loopback.cfg').writeAsStringSync('menuentry x {}\n');
    iso = File('${work.path}/test.iso');
    Process.runSync('xorriso', ['-as', 'mkisofs', '-V', 'TESTISO', '-o', iso.path, '${work.path}/tree']);
    final grub = Directory('${work.path}/grub')..createSync();
    File('${grub.path}/grub.cfg').writeAsStringSync('# 41_custom custom.cfg\n');
    File('${grub.path}/custom.cfg').writeAsStringSync('set x=1\n');
    env = {
      'BESIDEOS_TEST': '1',
      'BESIDEOS_GRUBDIR': grub.path,
      'BESIDEOS_STATE_DIR': '${work.path}/state',
    };
  });

  tearDown(() => work.deleteSync(recursive: true));

  final skip = haveTools ? null : 'needs Linux with xorriso and findmnt';

  test('dry run changes nothing', () async {
    final r = await run(['prepare', '--iso', iso.path]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains('DRY RUN'));
    expect(File('${work.path}/grub/custom.cfg').readAsStringSync(), 'set x=1\n');
  }, skip: skip);

  test('--label is the whole menu title, in any language, with the risky characters removed', () async {
    final p = await run(['prepare', '--iso', iso.path, '--execute', '--label', 'Установка Debian "x" \$y']);
    expect(p.exitCode, 0, reason: '${p.stdout}${p.stderr}');
    final cfg = File('${work.path}/grub/custom.cfg').readAsStringSync();
    expect(cfg, contains('menuentry "Установка Debian x y" --id besideos-default'));
    expect(cfg, isNot(contains('kurulumu')));
  }, skip: skip);

  test('prepare adds one marked block and undo restores custom.cfg exactly', () async {
    final p = await run(['prepare', '--iso', iso.path, '--execute']);
    expect(p.exitCode, 0, reason: '${p.stdout}${p.stderr}');
    final cfg = File('${work.path}/grub/custom.cfg').readAsStringSync();
    expect(cfg, startsWith('set x=1\n'));
    expect(cfg, contains('menuentry "test kurulumu" --id besideos-default'));
    expect(cfg, contains('configfile /boot/grub/loopback.cfg'));
    // the next start shows the menu for 5 seconds with this entry selected
    expect(cfg, contains('set default="besideos-default"'));
    expect(cfg, contains('set timeout=5'));
    expect(cfg, contains('save_env besideos_next'));
    expect(cfg, contains('# END BESIDEOS'));

    // A second prepare replaces the first entry; undo still restores the original file.
    final again = await run(['prepare', '--iso', iso.path, '--execute']);
    expect(again.exitCode, 0, reason: '${again.stdout}${again.stderr}');
    expect('BEGIN BESIDEOS default'.allMatches(File('${work.path}/grub/custom.cfg').readAsStringSync()), hasLength(1));

    final u = await run(['undo', '--execute']);
    expect(u.exitCode, 0, reason: '${u.stdout}${u.stderr}');
    expect(File('${work.path}/grub/custom.cfg').readAsStringSync(), 'set x=1\n');
    expect(File('${work.path}/state/default.state').existsSync(), isFalse);
  }, skip: skip);

  test('several systems at once: undo one keeps the other, undo --all restores the file', () async {
    for (final n in ['ubuntu', 'mint']) {
      final r = await run(['prepare', '--iso', iso.path, '--name', n, '--title', 'T $n', '--execute']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    }
    var cfg = File('${work.path}/grub/custom.cfg').readAsStringSync();
    expect(cfg, contains('--id besideos-ubuntu'));
    expect(cfg, contains('--id besideos-mint'));

    expect((await run(['undo', '--name', 'ubuntu', '--execute'])).exitCode, 0);
    cfg = File('${work.path}/grub/custom.cfg').readAsStringSync();
    expect(cfg, isNot(contains('besideos-ubuntu')));
    expect(cfg, contains('--id besideos-mint'));

    expect((await run(['undo', '--all', '--execute'])).exitCode, 0);
    expect(File('${work.path}/grub/custom.cfg').readAsStringSync(), 'set x=1\n');
    expect(Directory('${work.path}/state').listSync(), isEmpty);
  }, skip: skip);

  test('an entry written by the first single-entry version can still be undone by name', () async {
    File('${work.path}/grub/custom.cfg').writeAsStringSync(
        'set x=1\n# BEGIN BESIDEOS\nmenuentry "old" --id besideos {\n}\n# END BESIDEOS\n');
    Directory('${work.path}/state').createSync();
    File('${work.path}/state/state')
        .writeAsStringSync('GRUBDIR=${work.path}/grub\nCFG_EXISTED=1\nISO=/x.iso\nMETHOD=loopbackcfg\nGRUB_REBOOT=true\nGRUB_EDITENV=true\n');
    final r = await run(['undo', '--name', 'ubuntu', '--execute']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(File('${work.path}/grub/custom.cfg').readAsStringSync(), 'set x=1\n');
    expect(File('${work.path}/state/state').existsSync(), isFalse);
  }, skip: skip);

  test('an ISO without a known recipe is refused', () async {
    Directory('${work.path}/tree/boot/grub').deleteSync(recursive: true);
    File('${work.path}/tree/readme').writeAsStringSync('x');
    Process.runSync('xorriso', ['-as', 'mkisofs', '-V', 'X', '-o', iso.path, '${work.path}/tree']);
    final r = await run(['check', '--iso', iso.path]);
    expect(r.exitCode, 2);
    expect(r.stdout, contains('no known loopback boot recipe'));
  }, skip: skip);

  test('an unsafe path is refused', () async {
    final bad = File('${work.path}/a"b.iso')..writeAsBytesSync(iso.readAsBytesSync());
    final r = await run(['check', '--iso', bad.path]);
    expect(r.exitCode, 2);
  }, skip: skip);
}
