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

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/novel_web_response.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/page/picture/illust_lighting_page.dart';
import 'package:url_launcher/url_launcher_string.dart';

//这一堆都是专门给小说特殊约定写的
//🎵 EGOIST - Lovely Icecream Princess Sweetie
//[uploadedimage:123456]
class UploadedImageSpan extends WidgetSpan {
  final String imageUrl;

  UploadedImageSpan(this.imageUrl)
    : super(
        child: Builder(
          builder: (context) {
            return Container(child: PixivImage(imageUrl));
          },
        ),
      );
}

//[pixivimage:12551-1]
class PixivImageSpan extends WidgetSpan {
  final int id;
  final int targetIndex;
  final String actualText;
  final NovelIllusts? illusts;

  static Future<Illusts?> _getData(int id) async {
    try {
      Response response = await apiClient.getIllustDetail(id);
      final result = Illusts.fromJson(response.data['illust']);
      return result;
    } catch (e) {
      Log.e('Failed to get illust data', error: e);
    }
    return null;
  }

  PixivImageSpan(this.id, this.targetIndex, this.actualText, this.illusts)
    : super(
        child: Builder(
          builder: (context) {
            return Container(
              child:
                  (illusts != null)
                      ? Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: PixivImage(
                          illusts.illust.images.medium ??
                              illusts.illust.images.original ??
                              illusts.illust.images.small!,
                        ),
                      )
                      : FutureBuilder(
                        future: _getData(id),
                        builder: (
                          BuildContext context,
                          AsyncSnapshot<Illusts?> snapshot,
                        ) {
                          if (snapshot.connectionState ==
                                  ConnectionState.done &&
                              snapshot.data != null)
                            return Padding(
                              padding: const EdgeInsets.all(16.0),
                              child:
                                  targetIndex != 0
                                      ? PixivImage(
                                        snapshot
                                            .data!
                                            .metaPages[targetIndex]
                                            .imageUrls!
                                            .medium,
                                      )
                                      : PixivImage(
                                        snapshot.data!.imageUrls.medium,
                                      ),
                            );

                          return Container();
                        },
                      ),
            );
          },
        ),
      );
}

// (newpage)
// [chapter:本章标题]
// [pixlvimage:作品1]
// [jump:链接目标的页面編号]
// [[jumpuri:标题 ＞ 链接目标的URL]]
// [[rb:汉宇＞假名]]
class NovelSpansGenerator {
  static const _translationTargetLength = 400;
  static const _translationMaximumLength = 1200;

  List<NovelSpansData> buildSpans(NovelWebResponse webResponse) {
    final source = webResponse.text;
    try {
      String nowStr = '';
      bool spanCollectStart = false;
      List<NovelSpansData> result = [];
      for (var i = 0; i < source.length; i++) {
        final posStr = source[i];
        if (posStr == '[') {
          if (nowStr.isNotEmpty) {
            if (nowStr == '[') {
              spanCollectStart = true;
              nowStr += posStr;
            } else {
              result.add(NovelSpansData(NovelSpansType.normal, nowStr));
              nowStr = posStr;
              spanCollectStart = true;
            }
          } else {
            nowStr = posStr;
            spanCollectStart = true;
          }
        } else if (posStr == ']') {
          if (nowStr.startsWith("[[")) {
            if (nowStr.endsWith("]")) {
              spanCollectStart = false;
              nowStr += posStr;
              result.add(_parseText(nowStr, webResponse));
              nowStr = '';
            } else {
              nowStr += posStr;
            }
          } else {
            spanCollectStart = false;
            nowStr += posStr;
            result.add(_parseText(nowStr, webResponse));
            nowStr = '';
          }
        } else if (spanCollectStart) {
          nowStr += posStr;
        } else {
          nowStr += posStr;
        }
      }
      if (nowStr.isNotEmpty) {
        result.add(NovelSpansData(NovelSpansType.normal, nowStr));
      }
      Log.d('NovelSpansGenerator.buildSpans: $result');
      return result;
    } catch (e) {
      Log.e('Failed to build novel spans', error: e);
    }
    return [NovelSpansData(NovelSpansType.normal, source)];
  }

  RegExp linkRegex = RegExp(r'https?://\S+');

  NovelSpansData _parseText(String spanStr, NovelWebResponse webResponse) {
    if (spanStr.startsWith('[newpage]')) {
      return NovelSpansData(NovelSpansType.newPage, "");
    } else if (spanStr.startsWith('[chapter:')) {
      final title = spanStr.replaceAll('[chapter:', '').replaceAll(']', '');
      return NovelSpansData(NovelSpansType.chapter, title);
    } else if (spanStr.startsWith('[pixivimage:')) {
      final String key = spanStr;
      final flag = '[pixivimage:';
      String now = key.substring(flag.length, key.indexOf("]"));
      int trueId = 0;
      int targetIndex = 0;
      if (now.contains('-')) {
        trueId = int.tryParse(now.split('-').first)!;
        targetIndex = int.tryParse(now.split('-').last)!;
      }
      final illust = webResponse.illusts?[now];
      return PixivImageSpanData(trueId, targetIndex, key, illust!);
    } else if (spanStr.startsWith("[uploadedimage:")) {
      final String key = spanStr.toString();
      final flag = '[uploadedimage:';
      Log.d(() => key);
      String now = key.substring(flag.length, key.indexOf("]"));
      final image = webResponse.images?[now];
      final url =
          image?.urls.the128X128 ??
          image?.urls.the1200X1200 ??
          image?.urls.original;
      if (url != null) {
        return NovelSpansData(NovelSpansType.uploadedImage, url);
      } else {
        return NovelSpansData(NovelSpansType.normal, now);
      }
    } else if (spanStr.startsWith('[[jumpuri:')) {
      final String key = spanStr.toString();
      final flag = '[[jumpuri:';
      Log.d(() => key);
      String now = key.substring(flag.length, key.indexOf("]"));
      Iterable<RegExpMatch> matches = linkRegex.allMatches(now);
      final matchLink = matches.firstOrNull;
      if (matchLink != null) {
        final link = matchLink.group(0);
        if (link != null) {
          final uri = Uri.tryParse(link);
          if (uri != null && uri.host.contains("pixiv.net")) {
            return NovelSpansData(NovelSpansType.jumpUri, link);
          }
        }
        return NovelSpansData(NovelSpansType.normal, now);
      } else {
        return NovelSpansData(NovelSpansType.normal, now);
      }
    } else if (spanStr.startsWith('[[rb:')) {
      final String key = spanStr.toString();
      final flag = '[[rb:';
      final contentText = key
          .replaceAll(flag, '')
          .replaceAll(']', '')
          .split('>');
      final resultText = '${contentText.first}(${contentText.last})';
      return NovelSpansData(NovelSpansType.normal, resultText);
    } else {
      return NovelSpansData(NovelSpansType.normal, spanStr);
    }
  }

  InlineSpan novelSpansDatatoInlineSpan(
    BuildContext context,
    NovelSpansData data,
  ) {
    if (data.type == NovelSpansType.newPage) {
      return WidgetSpan(child: Container(child: Center(child: Text(''))));
    } else if (data.type == NovelSpansType.jumpUri) {
      return TextSpan(
        text: data.text,
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
        recognizer:
            TapGestureRecognizer()
              ..onTap = () async {
                final open = await showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: Text("External link"),
                      content: SelectionArea(child: Text(data.text)),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop("open");
                          },
                          child: Text("Open"),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text(I18n.of(context).cancel),
                        ),
                      ],
                    );
                  },
                );
                if (open == "open") {
                  launchUrlString(data.text);
                }
              },
      );
    } else if (data is PixivImageSpanData) {
      final trueId = data.illustId;
      final targetIndex = data.targetIndex;
      final illust = data.illust;
      final key = data.text;

      return TextSpan(
        children: [PixivImageSpan(trueId, targetIndex, key, illust)],
        recognizer:
            TapGestureRecognizer()
              ..onTap = () {
                Leader.push(context, IllustLightingPage(id: trueId));
              },
      );
    } else if (data.type == NovelSpansType.uploadedImage) {
      return UploadedImageSpan(data.text);
    }
    return TextSpan(text: data.text);
  }

  /// 将正文拆成可独立渲染和翻译的块。图片、分页和章节是硬边界；
  /// 相邻短段落会合并，避免仅有几个字符的段落产生一次 AI 请求。
  List<NovelContentBlock> buildContentBlocks(NovelWebResponse webResponse) {
    final spans = buildSpans(webResponse);
    final blocks = <NovelContentBlock>[];
    final textSpans = <NovelSpansData>[];

    void flushTextSpans() {
      if (textSpans.isEmpty) return;
      blocks.addAll(_buildTextBlocks(textSpans));
      textSpans.clear();
    }

    for (final span in spans) {
      if (_isHardBoundary(span)) {
        flushTextSpans();
        blocks.add(
          NovelContentBlock(id: 'block-${blocks.length}', spans: [span]),
        );
      } else {
        textSpans.add(span);
      }
    }
    flushTextSpans();
    return blocks
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(id: 'block-${entry.key}'))
        .toList(growable: false);
  }

  bool _isHardBoundary(NovelSpansData span) =>
      span.type == NovelSpansType.newPage ||
      span.type == NovelSpansType.pixivImage ||
      span.type == NovelSpansType.uploadedImage ||
      span.type == NovelSpansType.chapter;

  List<NovelContentBlock> _buildTextBlocks(List<NovelSpansData> spans) {
    final paragraphs = <NovelSpansData>[];
    for (final span in spans) {
      if (span.type != NovelSpansType.normal) {
        paragraphs.add(span);
        continue;
      }
      paragraphs.addAll(_splitParagraphs(span));
    }

    final blocks = <NovelContentBlock>[];
    var pending = <NovelSpansData>[];
    var pendingLength = 0;

    void flush() {
      if (pending.isEmpty) return;
      blocks.add(NovelContentBlock(id: '', spans: pending));
      pending = <NovelSpansData>[];
      pendingLength = 0;
    }

    for (final paragraph in paragraphs) {
      final pieces = _splitLongSpan(paragraph);
      for (final piece in pieces) {
        final length = piece.text.length;
        if (pending.isNotEmpty &&
            pendingLength + length > _translationMaximumLength) {
          flush();
        } else if (pendingLength >= _translationTargetLength) {
          flush();
        }
        pending.add(piece);
        pendingLength += length;
      }
    }
    flush();

    // 将最后不足目标长度的块尽量并回前一块，避免尾部短段单独请求。
    if (blocks.length > 1 &&
        blocks.last.translationSource.length < _translationTargetLength) {
      final previous = blocks[blocks.length - 2];
      final last = blocks.last;
      if (previous.translationSource.length + last.translationSource.length <=
          _translationMaximumLength) {
        blocks[blocks.length - 2] = NovelContentBlock(
          id: '',
          spans: [...previous.spans, ...last.spans],
        );
        blocks.removeLast();
      }
    }
    return blocks;
  }

  List<NovelSpansData> _splitParagraphs(NovelSpansData span) {
    final result = <NovelSpansData>[];
    final separator = RegExp(r'\r?\n[ \t]*\r?\n+');
    var start = 0;
    for (final match in separator.allMatches(span.text)) {
      result.add(
        NovelSpansData(span.type, span.text.substring(start, match.end)),
      );
      start = match.end;
    }
    if (start < span.text.length) {
      result.add(NovelSpansData(span.type, span.text.substring(start)));
    }
    return result.isEmpty ? [span] : result;
  }

  List<NovelSpansData> _splitLongSpan(NovelSpansData span) {
    if (span.text.length <= _translationMaximumLength ||
        span.type != NovelSpansType.normal) {
      return [span];
    }
    final result = <NovelSpansData>[];
    var start = 0;
    while (span.text.length - start > _translationMaximumLength) {
      final upper = start + _translationMaximumLength;
      final lower = start + _translationTargetLength;
      var splitAt = -1;
      for (var index = upper - 1; index >= lower; index--) {
        final char = span.text[index];
        if (char == '\n' || '。！？.!?'.contains(char)) {
          splitAt = index + 1;
          break;
        }
      }
      splitAt = splitAt == -1 ? upper : splitAt;
      result.add(
        NovelSpansData(span.type, span.text.substring(start, splitAt)),
      );
      start = splitAt;
    }
    result.add(NovelSpansData(span.type, span.text.substring(start)));
    return result;
  }
}

enum NovelSpansType {
  normal,
  newPage,
  chapter,
  pixivImage,
  uploadedImage,
  jumpUri,
  rb,
}

class NovelSpansData {
  final NovelSpansType type;
  final String text;

  NovelSpansData(this.type, this.text);
}

class PixivImageSpanData extends NovelSpansData {
  final int illustId;
  final int targetIndex;
  final NovelIllusts illust;

  PixivImageSpanData(this.illustId, this.targetIndex, String text, this.illust)
    : super(NovelSpansType.pixivImage, text);
}

class NovelContentBlock {
  final String id;
  final List<NovelSpansData> spans;

  const NovelContentBlock({required this.id, required this.spans});

  String get translationSource =>
      spans
          .where(
            (span) =>
                span.type == NovelSpansType.normal ||
                span.type == NovelSpansType.chapter ||
                span.type == NovelSpansType.jumpUri,
          )
          .map((span) => span.text)
          .join();

  bool get isTranslatable => translationSource.trim().isNotEmpty;

  NovelContentBlock copyWith({String? id, List<NovelSpansData>? spans}) =>
      NovelContentBlock(id: id ?? this.id, spans: spans ?? this.spans);
}
