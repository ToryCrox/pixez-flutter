import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

enum DownloadPathValidationResult { valid, empty, notFound, inaccessible }

Future<String> getDefaultDownloadPath() async {
  final documentDirectory = await getApplicationDocumentsDirectory();
  return path.join(documentDirectory.path, 'pixez', 'downloads');
}

Future<DownloadPathValidationResult> validateDownloadPath(
  String value, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final downloadPath = value.trim();
  if (downloadPath.isEmpty) return DownloadPathValidationResult.empty;

  final directory = Directory(downloadPath);
  if (!await directory.exists()) {
    return DownloadPathValidationResult.notFound;
  }

  try {
    // 读取至多一个条目即可验证访问权限；空目录会返回空列表而不是抛出异常。
    await directory.list(followLinks: false).take(1).toList().timeout(timeout);
    return DownloadPathValidationResult.valid;
  } catch (_) {
    return DownloadPathValidationResult.inaccessible;
  }
}
