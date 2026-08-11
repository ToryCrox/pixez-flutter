import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/utils/download_path.dart';

void main() {
  group('validateDownloadPath', () {
    test('允许访问空目录', () async {
      final directory = await Directory.systemTemp.createTemp(
        'pixez-download-path-',
      );
      addTearDown(() => directory.delete(recursive: true));

      expect(
        await validateDownloadPath(directory.path),
        DownloadPathValidationResult.valid,
      );
    });

    test('不存在的目录校验失败', () async {
      final parent = await Directory.systemTemp.createTemp(
        'pixez-download-path-',
      );
      addTearDown(() => parent.delete(recursive: true));
      final missingPath = '${parent.path}/missing';

      expect(
        await validateDownloadPath(missingPath),
        DownloadPathValidationResult.notFound,
      );
    });
  });
}
