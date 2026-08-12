import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/manga_ocr/manga_ocr_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Rust helper 支持 capabilities 与 shutdown 契约', () async {
    final helper = File('assets/executables/manga-ocr-helper-macos-arm64');
    if (!helper.existsSync()) return;
    final runtime = MangaOcrProcessRuntime(
      helperPath: helper.absolute.path,
      requestTimeout: const Duration(seconds: 5),
    );
    final capabilities = await runtime.capabilities();
    expect(capabilities['protocolVersion'], 1);
    expect(capabilities['detectors'], contains('ctd_onnx'));
    expect(capabilities['recognizers'], contains('baberu_ocr_int4'));
    expect(capabilities['methods'], contains('analyzePage'));
    await runtime.shutdown();
  });

  test('helper 崩溃时终止请求并返回明确错误', () async {
    if (Platform.isWindows) return;
    final helper = await _fakeHelper('read line\nexit 23');
    final runtime = MangaOcrProcessRuntime(
      helperPath: helper.path,
      requestTimeout: const Duration(seconds: 2),
    );

    await expectLater(
      runtime.capabilities(),
      throwsA(isA<MangaOcrRuntimeException>()),
    );
  });

  test('helper 异常输出时重建进程并结束挂起请求', () async {
    if (Platform.isWindows) return;
    final helper = await _fakeHelper("read line\nprintf 'not-json\\n'");
    final runtime = MangaOcrProcessRuntime(
      helperPath: helper.path,
      requestTimeout: const Duration(seconds: 2),
    );

    await expectLater(
      runtime.capabilities(),
      throwsA(isA<MangaOcrRuntimeException>()),
    );
  });

  test('helper 超时后进程被终止', () async {
    if (Platform.isWindows) return;
    final helper = await _fakeHelper('read line\nread second_line');
    final runtime = MangaOcrProcessRuntime(
      helperPath: helper.path,
      requestTimeout: const Duration(milliseconds: 100),
    );

    await expectLater(runtime.capabilities(), throwsA(isA<TimeoutException>()));
  });
}

Future<File> _fakeHelper(String body) async {
  final directory = await Directory.systemTemp.createTemp(
    'pixez-manga-ocr-helper-test-',
  );
  addTearDown(() => directory.delete(recursive: true));
  final helper = File('${directory.path}/fake-helper.sh');
  await helper.writeAsString('#!/bin/sh\n$body\n');
  final chmod = await Process.run('chmod', ['755', helper.path]);
  if (chmod.exitCode != 0) {
    throw StateError('无法创建测试 helper：${chmod.stderr}');
  }
  return helper;
}
