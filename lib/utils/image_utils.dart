import 'dart:io';
import 'dart:ui';

import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart' hide Size;
import 'package:pixez/custom/log.dart';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImageUtils {
  static Future<Size?> parseImageSize(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final size = await ImageSizeGetter.getSizeResultAsync(
        AsyncFileInput(file),
      );
      return Size(size.size.width.toDouble(), size.size.height.toDouble());
    } catch (e) {
      if (e is UnsupportedError || e.toString().contains('Invalid jpeg file')) {
        // Log.w('图片文件可能损坏或下载不完整 (Invalid jpeg file): $filePath');
        // 尝试使用 image 库作为 fallback
        try {
          final bytes = await File(filePath).readAsBytes();
          final image = await compute(_decodeImage, bytes);
          if (image != null) {
            return Size(image.width.toDouble(), image.height.toDouble());
          }
        } catch (e2) {
          Log.w('图片文件可能损坏或下载不完整 (Invalid jpeg file): $filePath');
        }
      } else {
        Log.e('解析图片宽高失败: $filePath, $e');
      }
      return null;
    }
  }

  static img.Image? _decodeImage(Uint8List bytes) {
    return img.decodeImage(bytes);
  }
}

class AsyncFileInput extends AsyncImageInput {
  final File file;
  const AsyncFileInput(this.file);

  @override
  Future<bool> exists() => file.exists();

  @override
  Future<int> get length => file.length();

  @override
  Future<List<int>> getRange(int start, int end) async {
    final raf = await file.open();
    try {
      await raf.setPosition(start);
      final bytes = await raf.read(end - start);
      return bytes.toList();
    } finally {
      await raf.close();
    }
  }

  @override
  Future<bool> supportRangeLoad() async => true;

  @override
  Future<HaveResourceImageInput> delegateInput() async {
    return HaveResourceImageInput(innerInput: FileInput(file));
  }
}
