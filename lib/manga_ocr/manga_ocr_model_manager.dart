import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pixez/custom/log.dart';

class MangaOcrModelFile {
  final String name;
  final Uri downloadUri;
  final int size;
  final String sha256;

  const MangaOcrModelFile({
    required this.name,
    required this.downloadUri,
    required this.size,
    required this.sha256,
  });

  factory MangaOcrModelFile.fromJson(Map<String, dynamic> json) =>
      MangaOcrModelFile(
        name: json['name'] as String,
        downloadUri: Uri.parse(json['downloadUrl'] as String),
        size: json['size'] as int,
        sha256: json['sha256'] as String,
      );
}

class MangaOcrModelPackage {
  final String engineId;
  final String version;
  final String architecture;
  final String license;
  final Uri upstream;
  final List<MangaOcrModelFile> files;

  const MangaOcrModelPackage({
    required this.engineId,
    required this.version,
    required this.architecture,
    required this.license,
    required this.upstream,
    required this.files,
  });

  int get totalSize => files.fold(0, (total, file) => total + file.size);

  factory MangaOcrModelPackage.fromJson(Map<String, dynamic> json) =>
      MangaOcrModelPackage(
        engineId: json['engineId'] as String,
        version: json['version'] as String,
        architecture: json['architecture'] as String? ?? 'onnx',
        license: json['license'] as String? ?? 'unknown',
        upstream: Uri.parse(json['upstream'] as String),
        files:
            (json['files'] as List<dynamic>)
                .map(
                  (item) => MangaOcrModelFile.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ),
                )
                .toList(),
      );
}

class MangaOcrModelProgress {
  final String engineId;
  final String fileName;
  final int received;
  final int total;

  const MangaOcrModelProgress({
    required this.engineId,
    required this.fileName,
    required this.received,
    required this.total,
  });
}

class MangaOcrModelManager {
  final Dio dio;
  final String? baseDirectory;
  List<MangaOcrModelPackage>? _manifest;

  MangaOcrModelManager({Dio? dio, this.baseDirectory}) : dio = dio ?? Dio();

  Future<List<MangaOcrModelPackage>> loadManifest() async {
    final current = _manifest;
    if (current != null) return current;
    final raw = await rootBundle.loadString(
      'assets/manga_ocr/model_manifest.json',
    );
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final packages =
        (json['packages'] as List<dynamic>)
            .map(
              (item) => MangaOcrModelPackage.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    _manifest = packages;
    return packages;
  }

  Future<String> modelDirectory() async {
    if (baseDirectory != null) return baseDirectory!;
    final support = await getApplicationSupportDirectory();
    return path.join(support.path, 'manga_ocr', 'models');
  }

  Future<MangaOcrModelPackage> package(String engineId) async =>
      (await loadManifest()).firstWhere(
        (item) => item.engineId == engineId,
        orElse: () => throw StateError('模型 manifest 中不存在：$engineId'),
      );

  Future<bool> isInstalled(String engineId) async {
    final modelPackage = await package(engineId);
    final root = await modelDirectory();
    for (final modelFile in modelPackage.files) {
      final file = File(path.join(root, engineId, modelFile.name));
      if (!await file.exists() || await file.length() != modelFile.size) {
        return false;
      }
    }
    return true;
  }

  Future<bool> verify(
    String engineId, {
    void Function(MangaOcrModelProgress progress)? onProgress,
  }) async {
    final modelPackage = await package(engineId);
    final root = await modelDirectory();
    for (final modelFile in modelPackage.files) {
      final file = File(path.join(root, engineId, modelFile.name));
      if (!await file.exists() || await file.length() != modelFile.size) {
        return false;
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != modelFile.sha256.toLowerCase()) {
        return false;
      }
      onProgress?.call(
        MangaOcrModelProgress(
          engineId: engineId,
          fileName: modelFile.name,
          received: modelFile.size,
          total: modelFile.size,
        ),
      );
    }
    return true;
  }

  Future<void> install(
    String engineId, {
    void Function(MangaOcrModelProgress progress)? onProgress,
  }) async {
    final modelPackage = await package(engineId);
    final root = await modelDirectory();
    final packageDirectory = Directory(path.join(root, engineId));
    await packageDirectory.create(recursive: true);
    for (final modelFile in modelPackage.files) {
      final destination = File(
        path.join(packageDirectory.path, modelFile.name),
      );
      if (await _matches(destination, modelFile)) continue;
      final partial = File('${destination.path}.part');
      var existing = await partial.exists() ? await partial.length() : 0;
      if (existing >= modelFile.size) {
        if (await _matches(partial, modelFile)) {
          if (await destination.exists()) await destination.delete();
          await partial.rename(destination.path);
          continue;
        }
        await partial.delete();
        existing = 0;
      }
      var response = await _download(
        engineId: engineId,
        modelFile: modelFile,
        partial: partial,
        offset: existing,
        onProgress: onProgress,
      );
      if (existing > 0 && response.statusCode != HttpStatus.partialContent) {
        await partial.delete();
        response = await _download(
          engineId: engineId,
          modelFile: modelFile,
          partial: partial,
          offset: 0,
          onProgress: onProgress,
        );
      }
      if (!await _matches(partial, modelFile)) {
        if (await partial.exists()) await partial.delete();
        throw StateError('模型校验失败：${modelFile.name}');
      }
      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
    }
  }

  Future<Response<dynamic>> _download({
    required String engineId,
    required MangaOcrModelFile modelFile,
    required File partial,
    required int offset,
    required void Function(MangaOcrModelProgress progress)? onProgress,
  }) {
    return dio.download(
      modelFile.downloadUri.toString(),
      partial.path,
      options: Options(
        headers: offset > 0 ? {'Range': 'bytes=$offset-'} : null,
      ),
      deleteOnError: false,
      fileAccessMode: offset > 0 ? FileAccessMode.append : FileAccessMode.write,
      onReceiveProgress: (received, total) {
        onProgress?.call(
          MangaOcrModelProgress(
            engineId: engineId,
            fileName: modelFile.name,
            received: offset + received,
            total: modelFile.size,
          ),
        );
      },
    );
  }

  Future<void> remove(String engineId) async {
    final root = await modelDirectory();
    final directory = Directory(path.join(root, engineId));
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<int> installedSize(String engineId) async {
    final root = await modelDirectory();
    final directory = Directory(path.join(root, engineId));
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<bool> _matches(File file, MangaOcrModelFile modelFile) async {
    if (!await file.exists() || await file.length() != modelFile.size) {
      return false;
    }
    try {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString().toLowerCase() == modelFile.sha256.toLowerCase();
    } catch (error, stackTrace) {
      Log.w('校验 OCR 模型失败', error: error, stackTrace: stackTrace);
      return false;
    }
  }
}
