/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart';
import 'package:dio/dio.dart';
import 'package:mobx/mobx.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/novel_recom_response.dart';
import 'package:pixez/models/novel_viewer_persist.dart';
import 'package:pixez/models/novel_web_response.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/page/novel/viewer/image_text.dart';
import 'package:flutter/widgets.dart';

part 'novel_store.g.dart';

enum NovelTranslationStatus { idle, loading, success, failed }

class NovelTranslationEntry {
  final NovelTranslationStatus status;
  final String sourceText;
  final String? translatedText;
  final String? errorMessage;

  const NovelTranslationEntry({
    required this.status,
    required this.sourceText,
    this.translatedText,
    this.errorMessage,
  });

  const NovelTranslationEntry.idle(String sourceText)
    : this(status: NovelTranslationStatus.idle, sourceText: sourceText);

  NovelTranslationEntry copyWith({
    NovelTranslationStatus? status,
    String? translatedText,
    String? errorMessage,
    bool clearError = false,
  }) => NovelTranslationEntry(
    status: status ?? this.status,
    sourceText: sourceText,
    translatedText: translatedText ?? this.translatedText,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}

class NovelStore = _NovelStoreBase with _$NovelStore;

abstract class _NovelStoreBase with Store {
  final int id;

  _NovelStoreBase(this.id, this.novel);

  @observable
  Novel? novel;
  @observable
  NovelWebResponse? novelTextResponse;
  @observable
  String? errorMessage;
  @observable
  bool positionBooked = false;

  @observable
  double bookedOffset = 0.0;
  @observable
  List<NovelSpansData> spans = [];
  @observable
  List<NovelContentBlock> contentBlocks = [];
  @observable
  String? translationLocale;
  @observable
  bool translationVisible = true;
  @observable
  ObservableMap<String, NovelTranslationEntry> translations = ObservableMap();

  Future<void>? _translationFuture;

  NovelViewerPersistProvider _novelViewerPersistProvider =
      NovelViewerPersistProvider();

  @action
  bookPosition(double offset) async {
    Log.d(() => "bookPosition $offset");
    await _novelViewerPersistProvider.open();
    await _novelViewerPersistProvider.insert(
      NovelViewerPersist(novelId: id, offset: offset),
    );
    positionBooked = true;
  }

  @action
  deleteBookPosition() async {
    Log.d(() => "deleteBookPosition");
    await _novelViewerPersistProvider.open();
    await _novelViewerPersistProvider.delete(id);
    positionBooked = false;
  }

  @action
  Future<void> fetch() async {
    errorMessage = null;
    try {
      bookedOffset = 0.0;
      final response = await apiClient.webviewNovel(id);
      String json = _parseHtml(response.data)!;
      novelTextResponse = NovelWebResponse.fromJson(jsonDecode(json));
      spans = await compute(buildSpans, novelTextResponse!);
      contentBlocks = NovelSpansGenerator().buildContentBlocks(
        novelTextResponse!,
      );
      if (novel == null) {
        Response response = await apiClient.getNovelDetail(id);
        novel = Novel.fromJson(response.data['novel']);
      }
      novelHistoryStore.insert(novel!);
      fetchOffset();
    } catch (e) {
      Log.e('Failed to fetch novel', error: e);
      errorMessage = e.toString();
    }
  }

  String? _parseHtml(String html) {
    var document = parse(html);
    final scriptElement = document.querySelector('script')!;
    String scriptContent = scriptElement.innerHtml;
    final novelRegex = RegExp(r'novel: ({.*?}),\n\s*isOwnWork');
    final match = novelRegex.firstMatch(scriptContent);
    if (match != null) {
      final novelJsonString = match.group(1);
      return novelJsonString;
    }
    return null;
  }

  @action
  fetchOffset() async {
    try {
      await _novelViewerPersistProvider.open();
      final result = await _novelViewerPersistProvider.getNovelPersistById(id);
      if (result != null) {
        Log.d(() => "fetchOffset ${result.offset}");
        positionBooked = true;
        bookedOffset = result.offset;
      }
    } catch (e) {}
  }

  bool get isTranslating => translations.values.any(
    (entry) => entry.status == NovelTranslationStatus.loading,
  );

  bool get hasTranslation => translations.values.any(
    (entry) => entry.status == NovelTranslationStatus.success,
  );

  NovelTranslationEntry? translationFor(String key) => translations[key];

  @action
  void toggleTranslationVisibility() {
    if (hasTranslation) translationVisible = !translationVisible;
  }

  @action
  Future<void> translateAll(String targetLanguage) async {
    final current = _translationFuture;
    if (current != null) return current;
    _translationFuture = _translateAll(targetLanguage);
    try {
      await _translationFuture;
    } finally {
      _translationFuture = null;
    }
  }

  Future<void> _translateAll(String targetLanguage) async {
    if (translationLocale != targetLanguage) {
      translationLocale = targetLanguage;
      translationVisible = true;
      translations = ObservableMap();
    }
    await aiTranslationService.ensureSceneReady(
      AiPromptScenes.novelTranslation,
    );
    final tasks = <Future<void> Function()>[];
    final currentNovel = novel;
    if (currentNovel != null && currentNovel.title.trim().isNotEmpty) {
      tasks.add(
        () => _translatePart(
          key: 'title',
          sourceText: currentNovel.title,
          contentType: '小说标题',
          targetLanguage: targetLanguage,
        ),
      );
    }
    if (currentNovel != null && currentNovel.caption.trim().isNotEmpty) {
      tasks.add(
        () => _translatePart(
          key: 'caption',
          sourceText: currentNovel.caption,
          contentType: '小说简介',
          targetLanguage: targetLanguage,
          preserveHtml: true,
        ),
      );
    }
    for (final batch in _buildBodyBatches(contentBlocks)) {
      tasks.add(() => _translateBodyBatch(batch, targetLanguage));
    }
    await _runWithConcurrency(tasks, maxConcurrent: 3);
  }

  @action
  Future<void> retryTitle(String targetLanguage) => _translatePart(
    key: 'title',
    sourceText: novel?.title ?? '',
    contentType: '小说标题',
    targetLanguage: targetLanguage,
  );

  @action
  Future<void> retryCaption(String targetLanguage) => _translatePart(
    key: 'caption',
    sourceText: novel?.caption ?? '',
    contentType: '小说简介',
    targetLanguage: targetLanguage,
    preserveHtml: true,
  );

  @action
  Future<void> retryBlock(NovelContentBlock block, String targetLanguage) =>
      _translatePart(
        key: 'body:${block.id}',
        sourceText: block.translationSource,
        contentType: '小说正文',
        targetLanguage: targetLanguage,
      );

  Future<void> _translatePart({
    required String key,
    required String sourceText,
    required String contentType,
    required String targetLanguage,
    bool preserveHtml = false,
  }) async {
    if (sourceText.trim().isEmpty || translationLocale != targetLanguage)
      return;
    final existing = translations[key];
    if (existing?.status == NovelTranslationStatus.loading ||
        existing?.status == NovelTranslationStatus.success) {
      return;
    }
    translations[key] = NovelTranslationEntry(
      status: NovelTranslationStatus.loading,
      sourceText: sourceText,
    );
    try {
      final translated = await aiTranslationService.translateNovelPart(
        novelId: id,
        partKey: key,
        contentType: contentType,
        targetLanguage: targetLanguage,
        sourceText: sourceText,
        preserveHtml: preserveHtml,
      );
      if (translationLocale == targetLanguage) {
        translations[key] = NovelTranslationEntry(
          status: NovelTranslationStatus.success,
          sourceText: sourceText,
          translatedText: translated,
        );
      }
    } catch (error, stackTrace) {
      Log.w('小说翻译失败: $key', error: error, stackTrace: stackTrace);
      if (translationLocale == targetLanguage) {
        translations[key] = NovelTranslationEntry(
          status: NovelTranslationStatus.failed,
          sourceText: sourceText,
          errorMessage: error.toString(),
        );
      }
    }
  }

  List<List<NovelContentBlock>> _buildBodyBatches(
    List<NovelContentBlock> blocks,
  ) {
    const targetLength = 400;
    const maximumLength = 1200;
    final batches = <List<NovelContentBlock>>[];
    var segment = <NovelContentBlock>[];

    void flushSegment() {
      if (segment.isEmpty) return;
      final grouped = <List<NovelContentBlock>>[];
      var pending = <NovelContentBlock>[];
      var pendingLength = 0;
      for (final block in segment) {
        final length = block.translationSource.length;
        if (pending.isNotEmpty && pendingLength + length > maximumLength) {
          grouped.add(pending);
          pending = <NovelContentBlock>[];
          pendingLength = 0;
        }
        pending.add(block);
        pendingLength += length;
        if (pendingLength >= targetLength) {
          grouped.add(pending);
          pending = <NovelContentBlock>[];
          pendingLength = 0;
        }
      }
      if (pending.isNotEmpty) {
        if (grouped.isNotEmpty &&
            grouped.last.fold<int>(
                      0,
                      (sum, block) => sum + block.translationSource.length,
                    ) +
                    pendingLength <=
                maximumLength) {
          grouped.last.addAll(pending);
        } else {
          grouped.add(pending);
        }
      }
      batches.addAll(grouped);
      segment = <NovelContentBlock>[];
    }

    for (final block in blocks) {
      if (block.isTranslatable) {
        segment.add(block);
      } else {
        flushSegment();
      }
    }
    flushSegment();
    return batches;
  }

  Future<void> _translateBodyBatch(
    List<NovelContentBlock> blocks,
    String targetLanguage,
  ) async {
    if (translationLocale != targetLanguage || blocks.isEmpty) return;
    final pendingBlocks =
        blocks.where((block) {
          final existing = translations['body:${block.id}'];
          return existing?.status != NovelTranslationStatus.loading &&
              existing?.status != NovelTranslationStatus.success;
        }).toList();
    if (pendingBlocks.isEmpty) return;

    for (final block in pendingBlocks) {
      translations['body:${block.id}'] = NovelTranslationEntry(
        status: NovelTranslationStatus.loading,
        sourceText: block.translationSource,
      );
    }
    try {
      final translated = await aiTranslationService.translateNovelBodyBatch(
        novelId: id,
        batchKey: '${pendingBlocks.first.id}-${pendingBlocks.last.id}',
        targetLanguage: targetLanguage,
        sourceTexts: pendingBlocks
            .map((block) => block.translationSource)
            .toList(growable: false),
      );
      if (translated.length != pendingBlocks.length) {
        throw StateError('小说正文翻译分段数量不匹配');
      }
      if (translationLocale == targetLanguage) {
        for (var index = 0; index < pendingBlocks.length; index++) {
          final block = pendingBlocks[index];
          translations['body:${block.id}'] = NovelTranslationEntry(
            status: NovelTranslationStatus.success,
            sourceText: block.translationSource,
            translatedText: translated[index],
          );
        }
      }
    } catch (error, stackTrace) {
      Log.w('小说正文翻译失败', error: error, stackTrace: stackTrace);
      if (translationLocale == targetLanguage) {
        for (final block in pendingBlocks) {
          translations['body:${block.id}'] = NovelTranslationEntry(
            status: NovelTranslationStatus.failed,
            sourceText: block.translationSource,
            errorMessage: error.toString(),
          );
        }
      }
    }
  }

  Future<void> _runWithConcurrency(
    List<Future<void> Function()> tasks, {
    required int maxConcurrent,
  }) async {
    var index = 0;
    Future<void> worker() async {
      while (index < tasks.length) {
        final task = tasks[index++];
        await task();
      }
    }

    await Future.wait(
      List.generate(
        tasks.length < maxConcurrent ? tasks.length : maxConcurrent,
        (_) => worker(),
      ),
    );
  }
}

class ComputeSpan {
  final BuildContext context;
  final NovelWebResponse webResponse;

  ComputeSpan(this.context, this.webResponse);
}

Future<List<NovelSpansData>> buildSpans(NovelWebResponse webResponse) {
  return Future.delayed(Duration(milliseconds: 100), () {
    NovelSpansGenerator novelSpansGenerator = NovelSpansGenerator();
    return novelSpansGenerator.buildSpans(webResponse);
  });
}
