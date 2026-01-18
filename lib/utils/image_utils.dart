import 'dart:io';
import 'dart:ui';

import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart' hide Size;

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
      return null;
    }
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
