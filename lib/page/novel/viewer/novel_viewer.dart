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
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pixez/ai/ai_translation_error_handler.dart';
import 'package:pixez/component/painter_avatar.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/component/selectable_html.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/ban_tag.dart';
import 'package:pixez/models/novel_recom_response.dart';
import 'package:pixez/models/novel_web_response.dart';
import 'package:pixez/page/comment/comment_page.dart';
import 'package:pixez/page/novel/component/novel_bookmark_button.dart';
import 'package:pixez/page/novel/search/novel_result_page.dart';
import 'package:pixez/page/novel/series/novel_series_page.dart';
import 'package:pixez/page/novel/user/novel_users_page.dart';
import 'package:pixez/page/novel/viewer/image_text.dart';
import 'package:pixez/page/novel/viewer/novel_store.dart';
import 'package:pixez/saf_plugin.dart';
import 'package:pixez/supportor_plugin.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as Path;

class NovelViewerPage extends StatefulWidget {
  final int id;
  final NovelStore? novelStore;

  const NovelViewerPage({Key? key, required this.id, this.novelStore})
    : super(key: key);

  @override
  _NovelViewerPageState createState() => _NovelViewerPageState();
}

class _NovelViewerPageState extends State<NovelViewerPage> {
  ScrollController? _controller;
  late NovelStore _novelStore;
  ReactionDisposer? _offsetDisposer;
  double _localOffset = 0.0;
  bool supportTranslate = false;
  String _selectedText = "";
  String? _hydratedTranslationLocale;
  NovelSpansGenerator novelSpansGenerator = NovelSpansGenerator();

  Future<void> initMethod() async {
    if (!Platform.isAndroid) return;
    bool results = await SupportorPlugin.processText();
    if (mounted) {
      setState(() {
        supportTranslate = results;
      });
    }
  }

  @override
  void initState() {
    _novelStore = widget.novelStore ?? NovelStore(widget.id, null);
    _offsetDisposer = reaction((_) => _novelStore.bookedOffset, (_) {
      Log.d(() => "jump to ${_novelStore.bookedOffset}");
      _controller?.jumpTo(_novelStore.bookedOffset);
    });
    _novelStore.fetch();
    super.initState();
    initMethod();
  }

  @override
  void dispose() {
    _offsetDisposer?.call();
    _novelStore.cancelTranslations();
    if (_novelStore.positionBooked) {
      _novelStore.bookPosition(_localOffset);
    }
    _controller?.dispose();
    super.dispose();
  }

  final double leading = 0.9;
  final double textLineHeight = 2;
  final double fontSize = 16;
  TextStyle? _textStyle;

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        _textStyle = Theme.of(
          context,
        ).textTheme.bodyLarge!.copyWith(fontSize: userSetting.novelFontsize);
        if (_novelStore.errorMessage != null) {
          return Scaffold(
            appBar: AppBar(elevation: 0.0),
            extendBody: true,
            extendBodyBehindAppBar: true,
            body: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          ':(',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _novelStore.fetch();
                    },
                    child: Text(I18n.of(context).retry),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('${_novelStore.errorMessage}'),
                  ),
                ],
              ),
            ),
          );
        }
        if (_novelStore.novelTextResponse != null &&
            _novelStore.novel != null) {
          final targetLanguage = _targetLanguage(context);
          if (_hydratedTranslationLocale != targetLanguage) {
            _hydratedTranslationLocale = targetLanguage;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _novelStore.hydrateCachedTranslations(targetLanguage);
              }
            });
          }
          _textStyle =
              _textStyle ?? Theme.of(context).textTheme.bodyLarge!.copyWith();
          if (_controller == null) {
            Log.d(() => "init Controller ${_novelStore.bookedOffset}");
            _controller = ScrollController(
              initialScrollOffset: _novelStore.bookedOffset,
            );
            _controller?.addListener(() {
              if (_controller!.hasClients) _localOffset = _controller!.offset;
            });
          }
          return Container(
            child: Scaffold(
              appBar: AppBar(
                elevation: 0.0,
                leading: IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: Theme.of(context).textTheme.bodyLarge!.color,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                title: Text(
                  _novelStore.novelTextResponse!.text.length.toString(),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                backgroundColor: Colors.transparent,
                actions: <Widget>[
                  NovelBookmarkButton(novel: _novelStore.novel!),
                  IconButton(
                    onPressed: () {
                      if (_novelStore.positionBooked)
                        _novelStore.deleteBookPosition();
                      else
                        _novelStore.bookPosition(_controller!.offset);
                    },
                    icon: Icon(Icons.history),
                    color: Theme.of(context).textTheme.bodyLarge!.color!
                        .withAlpha(_novelStore.positionBooked ? 225 : 120),
                  ),
                  _buildTranslationButton(context),
                  Builder(
                    builder: (context) {
                      return IconButton(
                        icon: Icon(
                          Icons.more_vert,
                          color: Theme.of(context).textTheme.bodyLarge!.color,
                        ),
                        onPressed: () {
                          _showMessage(context);
                        },
                      );
                    },
                  ),
                ],
              ),
              body: ListView.builder(
                padding: EdgeInsets.all(0),
                controller: _controller,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildHeader(context);
                  } else if (index == _novelStore.contentBlocks.length + 1) {
                    return Container(
                      height: 10 + MediaQuery.of(context).padding.bottom,
                    );
                  } else {
                    return _buildSpanText(
                      context,
                      index - 1,
                      _novelStore.contentBlocks,
                    );
                  }
                },
                itemCount: 2 + _novelStore.contentBlocks.length,
              ),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(elevation: 0.0, backgroundColor: Colors.transparent),
          body: Container(child: Center(child: CircularProgressIndicator())),
        );
      },
    );
  }

  Widget _buildSpanText(
    BuildContext context,
    int index,
    List<NovelContentBlock> blocks,
  ) {
    final block = blocks[index];
    if (block.isEmptyLine) {
      return SizedBox(height: (_textStyle?.fontSize ?? fontSize) * 0.8);
    }
    final translation = _translationForCurrentLocale(
      context,
      'body:${block.id}',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionArea(
            onSelectionChanged: (value) {
              _selectedText = value?.plainText ?? "";
            },
            contextMenuBuilder: (context, editableTextState) {
              return _buildSelectionMenu(editableTextState, context);
            },
            child: Text.rich(
              TextSpan(
                children: [
                  ...block.spans.map(
                    (span) => novelSpansGenerator.novelSpansDatatoInlineSpan(
                      context,
                      span,
                    ),
                  ),
                ],
              ),
              style: _textStyle,
              textHeightBehavior: TextHeightBehavior(
                applyHeightToLastDescent: true,
              ),
            ),
          ),
          if (block.isTranslatable)
            _buildTranslationContent(
              context,
              translation,
              onRetry:
                  () => _novelStore.retryBlock(block, _targetLanguage(context)),
            ),
        ],
      ),
    );
  }

  TextStyle _translationTextStyle(BuildContext context) {
    final baseStyle = _textStyle ?? Theme.of(context).textTheme.bodyLarge!;
    return baseStyle.copyWith(
      color: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
      fontSize: (baseStyle.fontSize ?? fontSize) * 0.92,
    );
  }

  String _targetLanguage(BuildContext context) =>
      Localizations.localeOf(context).toLanguageTag();

  NovelTranslationEntry? _translationForCurrentLocale(
    BuildContext context,
    String key,
  ) {
    if (_novelStore.translationLocale != _targetLanguage(context) ||
        !_novelStore.translationVisible) {
      return null;
    }
    return _novelStore.translationFor(key);
  }

  Widget _buildTranslationButton(BuildContext context) {
    final currentLocale = _targetLanguage(context);
    final hasCurrentTranslation =
        _novelStore.translationLocale == currentLocale &&
        _novelStore.hasTranslation;
    if (_novelStore.isTranslating) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (hasCurrentTranslation) {
      final hasUnfinishedTranslation = _novelStore.needsTranslationContinuation(
        currentLocale,
      );
      return IconButton(
        tooltip:
            hasUnfinishedTranslation
                ? I18n.of(context).translate
                : _novelStore.translationVisible
                ? I18n.of(context).hide_novel_translation
                : I18n.of(context).show_novel_translation,
        icon: Icon(
          hasUnfinishedTranslation
              ? Icons.translate
              : _novelStore.translationVisible
              ? Icons.translate_outlined
              : Icons.translate,
          color: Theme.of(context).textTheme.bodyLarge!.color,
        ),
        onPressed:
            hasUnfinishedTranslation
                ? () => _startTranslation(context)
                : _novelStore.toggleTranslationVisibility,
      );
    }
    return IconButton(
      tooltip: I18n.of(context).translate,
      icon: Icon(
        Icons.translate,
        color: Theme.of(context).textTheme.bodyLarge!.color,
      ),
      onPressed: () => _startTranslation(context),
    );
  }

  Future<void> _startTranslation(BuildContext context) async {
    try {
      await _novelStore.translateAll(_targetLanguage(context));
    } catch (error) {
      if (mounted) await showAiTranslationError(context, error);
    }
  }

  Widget _buildTranslationContent(
    BuildContext context,
    NovelTranslationEntry? entry, {
    required VoidCallback onRetry,
    bool html = false,
  }) {
    if (entry == null) return const SizedBox.shrink();
    if (entry.status == NovelTranslationStatus.loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(I18n.of(context).novel_translation_loading),
          ],
        ),
      );
    }
    if (entry.status == NovelTranslationStatus.failed) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(
            '${I18n.of(context).novel_translation_failed} · '
            '${I18n.of(context).retry_novel_translation}',
          ),
        ),
      );
    }
    if (entry.status != NovelTranslationStatus.success ||
        entry.translatedText == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Opacity(
        opacity: 0.72,
        child:
            html
                ? DefaultTextStyle.merge(
                  style: _translationTextStyle(context),
                  child: SelectableHtml(data: entry.translatedText!),
                )
                : SelectionArea(
                  child: Text(
                    _translationTextAlignedWithSource(entry),
                    style: _translationTextStyle(context),
                  ),
                ),
      ),
    );
  }

  /// 翻译缓存会忽略段首缩进；以原文的前导空白为准，保持逐行对齐。
  String _translationTextAlignedWithSource(NovelTranslationEntry entry) {
    final sourceIndent =
        RegExp(r'^[\s\u3000]*').firstMatch(entry.sourceText)?.group(0) ?? '';
    return '$sourceIndent${entry.translatedText!.trimLeft()}';
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      // AppBar 已由 Scaffold 自动处理安全区和工具栏高度，正文仅保留视觉间距。
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 104,
                    height: 140,
                    child: PixivImage(_novelStore.novel!.imageUrls.medium),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _novelStore.novel!.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      _buildTranslationContent(
                        context,
                        _translationForCurrentLocale(context, 'title'),
                        onRetry:
                            () => _novelStore.retryTitle(
                              _targetLanguage(context),
                            ),
                      ),
                      if (_novelStore.novel?.series.id != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: InkWell(
                            onTap: () {
                              Leader.push(
                                context,
                                NovelSeriesPage(_novelStore.novel!.series.id!),
                              );
                            },
                            child: Text(
                              'Series: ${_novelStore.novel!.series.title}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _buildNumContent(_novelStore.novel!),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${_novelStore.novel!.createDate}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 2,
              runSpacing: 0,
              children: [
                if (_novelStore.novel!.NovelAIType == 2)
                  Text(
                    '${I18n.of(context).ai_generated}',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                for (var f in _novelStore.novel!.tags) buildRow(context, f),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectionArea(
                  onSelectionChanged: (value) {
                    _selectedText = value?.plainText ?? "";
                  },
                  contextMenuBuilder: (context, editableTextState) {
                    return _buildSelectionMenu(editableTextState, context);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableHtml(
                          data: _novelStore.novel?.caption ?? "",
                        ),
                      ),
                      _buildTranslationContent(
                        context,
                        _translationForCurrentLocale(context, 'caption'),
                        onRetry:
                            () => _novelStore.retryCaption(
                              _targetLanguage(context),
                            ),
                        html: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Leader.push(
                context,
                CommentPage(id: _novelStore.id, type: CommentArtWorkType.NOVEL),
              );
            },
            child: Text(I18n.of(context).view_comment),
          ),
        ],
      ),
    );
  }

  AdaptiveTextSelectionToolbar _buildSelectionMenu(
    SelectableRegionState editableTextState,
    BuildContext context,
  ) {
    final List<ContextMenuButtonItem> buttonItems =
        editableTextState.contextMenuButtonItems;
    if (supportTranslate) {
      buttonItems.insert(
        buttonItems.length,
        ContextMenuButtonItem(
          label: I18n.of(context).translate,
          onPressed: () async {
            final selectionText = _selectedText;
            if (Platform.isIOS) {
              final box = context.findRenderObject() as RenderBox?;
              final pos =
                  box != null
                      ? box.localToGlobal(Offset.zero) & box.size
                      : null;
              SharePlus.instance.share(
                ShareParams(text: selectionText, sharePositionOrigin: pos),
              );
              return;
            }
            await SupportorPlugin.start(selectionText);
            ContextMenuController.removeAny();
          },
        ),
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  Future<void> _showSettings(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setB) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Container(
                        child: Icon(Icons.text_fields),
                        margin: EdgeInsets.only(left: 16),
                      ),
                      Container(
                        child: Text(_textStyle!.fontSize!.toInt().toString()),
                        margin: EdgeInsets.only(left: 16),
                      ),
                      Expanded(
                        child: Slider(
                          value: _textStyle!.fontSize! / 32,
                          onChanged: (v) {
                            setB(() {
                              _textStyle = _textStyle!.copyWith(
                                fontSize: v * 32,
                              );
                            });
                            userSetting.setNovelFontsizeWithoutSave(v * 32);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    userSetting.setNovelFontsize(_textStyle!.fontSize!);
  }

  Future _longPressTag(BuildContext context, Tag f) async {
    switch (await showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: Text(f.name),
          children: <Widget>[
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 0);
              },
              child: Text(I18n.of(context).ban),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 2);
              },
              child: Text(I18n.of(context).copy),
            ),
          ],
        );
      },
    )) {
      case 0:
        {
          await muteStore.insertBanTag(
            BanTagPersist(name: f.name, translateName: f.translatedName ?? ""),
          );
          Navigator.of(context).pop();
        }
        break;
      case 2:
        {
          await Clipboard.setData(ClipboardData(text: f.name));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: Duration(seconds: 1),
              content: Text(I18n.of(context).copied_to_clipboard),
            ),
          );
        }
    }
  }

  Widget buildRow(BuildContext context, Tag f) {
    return GestureDetector(
      onLongPress: () async {
        _longPressTag(context, f);
      },
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) {
              return NovelResultPage(
                word: f.name,
                translatedName: f.translatedName ?? "",
              );
            },
          ),
        );
      },
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          text: "#${f.name}",
          children: [
            TextSpan(text: " ", style: Theme.of(context).textTheme.bodySmall),
            TextSpan(
              text: "${f.translatedName ?? "~"}",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ),
    );
  }

  Widget _buildNumContent(Novel novel) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 0,
      children: [
        Text(I18n.of(context).total_bookmark),
        Text(
          "${novel.totalBookmarks}",
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Text(I18n.of(context).total_view),
        ),
        Text(
          "${novel.totalView}",
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      ],
    );
  }

  Future _showMessage(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ListTile(
                subtitle: Text(_novelStore.novel!.user.name, maxLines: 2),
                title: Text(_novelStore.novel!.title, maxLines: 2),
                leading: Container(
                  child: PainterAvatar(
                    url: _novelStore.novel!.user.profileImageUrls.medium,
                    id: _novelStore.novel!.user.id,
                    size: Size(40, 40),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) {
                            return NovelUsersPage(
                              id: _novelStore.novel!.user.id,
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(I18n.of(context).pre),
              ),
              buildListTile(
                _novelStore.novelTextResponse!.seriesNavigation?.prevNovel,
              ),
              Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(I18n.of(context).next),
              ),
              buildListTile(
                _novelStore.novelTextResponse!.seriesNavigation?.nextNovel,
              ),
              if (Platform.isAndroid)
                ListTile(
                  title: Text(I18n.of(context).export),
                  leading: Icon(Icons.folder_zip),
                  onTap: () {
                    _export();
                  },
                ),
              ListTile(
                title: Text(I18n.of(context).setting),
                leading: Icon(Icons.settings),
                onTap: () {
                  Navigator.of(context).pop();
                  _showSettings(context);
                },
              ),
              ListTile(
                title: Text(I18n.of(context).share),
                leading: Icon(Icons.share),
                onTap: () {
                  Navigator.of(context).pop();
                  SharePlus.instance.share(
                    ShareParams(
                      text:
                          "https://www.pixiv.net/novel/show.php?id=${widget.id}",
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildListTile(PrevNovel? series) {
    if (series == null) return ListTile(title: Text("no more"));
    return ListTile(
      title: Text(series.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (BuildContext context) => NovelViewerPage(
                  id: series.id,
                  novelStore: NovelStore(series.id, null),
                ),
          ),
        );
      },
    );
  }

  void _export() async {
    if (_novelStore.novelTextResponse == null) return;
    if (Platform.isAndroid) {
      // final path = await getExternalStorageDirectory();
      // if (path == null) return;
      // final dirPath = Path.join(path.path, "novel_export");
      // final dir = Directory(dirPath);
      // if (!dir.existsSync()) {
      //   dir.createSync(recursive: true);
      // }
      // final allPath = Path.join(dirPath, "All");
      // final allDir = Directory(allPath);
      // if (!allDir.existsSync()) {
      //   allDir.createSync(recursive: true);
      // }
      // final novelDirPath =
      //     Path.join(dirPath, _novelStore.novel!.title.trim().toLegal());
      // final novelDir = Directory(novelDirPath);
      // if (!novelDir.existsSync()) {
      //   novelDir.createSync(recursive: true);
      // }
      // final fileInAllPath = Path.join(
      //     allPath, "${_novelStore.novel!.title.trim().toLegal()}.txt");
      // final filePath = Path.join(novelDirPath, "${_novelStore.novel!.id}.txt");
      // final resultFile = File(filePath);
      // final data = _novelStore.novelTextResponse!.text;
      // resultFile.writeAsStringSync(data);
      // File(fileInAllPath).writeAsStringSync(data);
      // BotToast.showText(text: "export ${filePath}");
      final data = _novelStore.novelTextResponse!.text;
      final uri = await SAFPlugin.createFile(
        "${_novelStore.novel!.title.trim().toLegal()}.txt",
        "application/txt",
      );
      await SAFPlugin.writeUri(uri!, utf8.encode(data));
      BotToast.showText(text: "export success");
    } else if (Platform.isIOS) {
      final path = await getApplicationDocumentsDirectory();
      final dirPath = Path.join(path.path, "novel_export");
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final allPath = Path.join(dirPath, "All");
      final allDir = Directory(allPath);
      if (!allDir.existsSync()) {
        allDir.createSync(recursive: true);
      }
      final novelDirPath = Path.join(
        dirPath,
        _novelStore.novel!.title.trim().toLegal(),
      );
      final novelDir = Directory(novelDirPath);
      if (!novelDir.existsSync()) {
        novelDir.createSync(recursive: true);
      }
      final fileInAllPath = Path.join(
        allPath,
        "${_novelStore.novel!.title.trim().toLegal()}.txt",
      );
      final filePath = Path.join(novelDirPath, "${_novelStore.novel!.id}.txt");
      final resultFile = File(filePath);
      final data = _novelStore.novelTextResponse!.text;
      resultFile.writeAsStringSync(data);
      File(fileInAllPath).writeAsStringSync(data);
      Log.d(() => "path: $filePath");
      BotToast.showText(text: "export ${filePath}");
    }
  }
}
