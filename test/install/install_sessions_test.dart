import 'dart:io';

import 'package:besideos_site/download/download_controller.dart';
import 'package:besideos_site/download/downloader.dart';
import 'package:besideos_site/install/engine.dart';
import 'package:besideos_site/install/install_controller.dart';
import 'package:besideos_site/install/install_sessions.dart';
import 'package:besideos_site/install/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

class _Runner implements ProcessRunner {
  @override
  Future<RunResult> exec(String exe, List<String> args) async => const RunResult(0, '', '');
  @override
  Future<RunResult> script(File script, List<String> args, {bool elevated = false}) async => const RunResult(0, '', '');
}

void main() {
  test('one controller per distro is kept while leaving its page; distros do not share one', () {
    final tmp = Directory.systemTemp.createTempSync('sessions');
    addTearDown(() => tmp.deleteSync(recursive: true));
    InstallController make(String id) => InstallController(
          ownerId: id,
          runner: _Runner(),
          engine: Engine.linux(File('${tmp.path}/besideos-grub.sh')),
          workDir: Directory('${tmp.path}/work'),
          download: DownloadController(downloader: Downloader(), targetDir: tmp),
        );

    final s = InstallSessions.instance;
    final ubuntu = s.obtain('ubuntu', () => make('ubuntu'))!;
    expect(s.obtain('ubuntu', () => fail('must reuse')), same(ubuntu));
    expect(s.obtain('mint', () => make('mint')), isNot(same(ubuntu)));
  });
}
