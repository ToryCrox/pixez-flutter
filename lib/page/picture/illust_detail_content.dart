import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/selectable_html.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/ban_tag.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/comment/comment_page.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/user_follow_button.dart';
import 'package:pixez/page/search/result_page.dart';
import 'package:pixez/page/series/illust_series_page.dart';
import 'package:pixez/page/user/user_store.dart';
import 'package:pixez/page/user/users_page.dart';
import 'package:pixez/supportor_plugin.dart';
import 'package:pixez/component/painter_avatar.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pixez/page/downloaded/downloaded_page.dart';
import 'package:pixez/page/downloaded/tag_manager/tag_edit_dialog.dart';
import 'package:pixez/models/download_record.dart';

class IllustDetailContent extends StatefulWidget {
  final Illusts illusts;
  final UserStore? userStore;
  final IllustStore illustStore;
  final VoidCallback loadAbout;
  const IllustDetailContent({
    super.key,
    required this.illusts,
    this.userStore,
    required this.illustStore,
    required this.loadAbout,
  });

  @override
  State<IllustDetailContent> createState() => _IllustDetailContentState();
}

class _IllustDetailContentState extends State<IllustDetailContent> {
  late Illusts _illusts;

  late UserStore? userStore;
  late FocusNode _focusNode;
  late IllustStore? _illustStore;
  String _selectedText = "";
  
  // 自定义tag功能状态
  bool _isDownloaded = false;  // 插画是否已下载
  List<String> _customTagNames = [];  // 自定义标签名称列表

  @override
  void initState() {
    _focusNode = FocusNode();
    _illusts = widget.illusts;
    _illustStore = widget.illustStore;
    userStore = widget.userStore;
    super.initState();
    supportTranslateCheck();
    widget.loadAbout();
    _checkDownloadStatus();  // 检查下载状态
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IllustDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检查是否需要更新 _illusts
    if (widget.illusts.id != oldWidget.illusts.id ||
        widget.illusts.caption != oldWidget.illusts.caption) {
      setState(() {
        _illusts = widget.illusts;
      });
      _checkDownloadStatus();  // 重新检查下载状态
    }
  }
  
  // 检查下载状态并加载自定义标签
  Future<void> _checkDownloadStatus() async {
    final downloaded = await downloadStore.isIllustDownloaded(_illusts.id);
    if (downloaded && mounted) {
      final customTags = await _loadCustomTags();
      setState(() {
        _isDownloaded = true;
        _customTagNames = customTags;
      });
    } else if (mounted) {
      setState(() {
        _isDownloaded = false;
        _customTagNames = [];
      });
    }
  }
  
  // 加载自定义标签
  Future<List<String>> _loadCustomTags() async {
    final allTags = await tagManagerStore.getTagsForIllust(_illusts.id);
    final originalTagNames = _illusts.tags.map((t) => t.name).toSet();
    return allTags.where((tag) => !originalTagNames.contains(tag)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoArea(context, _illusts),
            _buildNameAvatar(context, _illusts),
            _buildTagArea(context, _illusts),
            _buildCaptionArea(_illusts),
            _buildCommentTextArea(context, _illusts),
            Padding(
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                bottom: 4.0,
              ),
              child: Text(I18n.of(context).about_picture),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoArea(BuildContext context, Illusts data) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 8.0),
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: SelectionArea(
              child: Text(
                data.title,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium!.copyWith(fontSize: 18),
              ),
            ),
          ),
          if (data.series != null)
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => IllustSeriesPage(id: data.series!.id),
                  ),
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: EdgeInsets.only(left: 0, bottom: 0),
                alignment: Alignment.centerLeft,
                child: Text(
                  '${data.series?.title ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          SizedBox(height: 8.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.remove_red_eye,
                color: Theme.of(context).colorScheme.onSurface,
                size: 12,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2.0),
                child: Text(
                  data.totalView.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Container(width: 4.0),
              Icon(
                Icons.favorite,
                color: Theme.of(context).colorScheme.onSurface,
                size: 12.0,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2.0),
                child: Text(
                  "${data.totalBookmarks}",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Container(width: 4.0),
              Icon(
                Icons.timelapse_rounded,
                color: Theme.of(context).colorScheme.onSurface,
                size: 12.0,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2.0),
                child: Text(
                  data.createDate.toShortTime(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Container(
                child: Text(
                  I18n.of(context).illust_id,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Container(width: 4.0),
              colorText(data.id.toString(), context),
              Container(width: 10.0),
              Container(
                child: Text(
                  I18n.of(context).pixel,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Container(width: 4.0),
              colorText("${data.width}x${data.height}", context),
            ],
          ),
          SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget colorText(String text, BuildContext context) {
    return SelectionArea(
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.secondary,
          fontSize: 12,
        ),
      ),
    );
  }

  Padding _buildTagArea(BuildContext context, Illusts data) {
    final tagNames = data.tags.map((e) => e.name).toSet();
    final List<Tags> displayTags = List.from(data.tags);
    
    // 如果某个标签关联了主标签，且主标签不在列表中，则将其加入显示
    for (final tag in data.tags) {
      final mainTag = tagManagerStore.getMainTag(tag.name);
      if (mainTag != null && !tagNames.contains(mainTag.name)) {
        displayTags.add(Tags(name: mainTag.name, translatedName: mainTag.translatedName));
        tagNames.add(mainTag.name);
      }
    }
    
    // 添加自定义标签
    for (final tagName in _customTagNames) {
      if (!tagNames.contains(tagName)) {
        final localTag = tagManagerStore.getTagDisplayData(tagName);
        displayTags.add(Tags(
          name: tagName, 
          translatedName: localTag?.tag.translatedName ?? '',
        ));
        tagNames.add(tagName);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 8.0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          if (data.illustAIType == 2)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
              ),
              child: RichText(
                textAlign: TextAlign.start,
                text: TextSpan(
                  text: "${I18n.of(context).ai_generated}",
                  children: [
                    TextSpan(
                      text: " ",
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall!.copyWith(fontSize: 12),
                    ),
                  ],
                  style: Theme.of(context).textTheme.titleSmall!.copyWith(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          for (var f in displayTags) buildRow(context, f),
          // 添加标签按钮（仅已下载插画显示）
          if (_isDownloaded) _buildAddTagButton(context),
        ],
      ),
    );
  }

  Widget _buildCaptionArea(Illusts data) {
    final caption =
        data.caption.isEmpty
            ? _illustStore?.illusts?.caption ?? ""
            : data.caption;
    if (caption.isEmpty && _illustStore?.captionFetchError == true) {
      return Container(
        margin: EdgeInsets.only(top: 4),
        child: Container(
          child: Center(
            child: InkWell(
              onTap: () {
                _illustStore?.fetch();
              },
              child: Icon(Icons.refresh),
            ),
          ),
        ),
      );
    }
    if (caption.isEmpty && _illustStore?.captionFetching == true) {
      return Container(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    if (caption.isEmpty) {
      return Container(height: 1);
    }
    return Container(
      margin: EdgeInsets.only(top: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onInverseSurface,
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Container(
              width: double.infinity,
              child: SelectionArea(
                focusNode: _focusNode,
                onSelectionChanged: (value) {
                  _selectedText = value?.plainText ?? "";
                },
                contextMenuBuilder: (context, selectableRegionState) {
                  return _buildSelectionMenu(selectableRegionState, context);
                },
                child: SelectableHtml(data: caption.isEmpty ? "~" : caption),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool supportTranslate = false;

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
              Share.share(selectionText, sharePositionOrigin: pos);
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

  Widget _buildCommentTextArea(BuildContext context, Illusts data) {
    return Center(
      child: Padding(
        padding: EdgeInsets.only(left: 16.0, right: 16.0),
        child: InkWell(
          onTap: () {
            Leader.push(context, CommentPage(id: data.id));
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.comment,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  SizedBox(width: 4),
                  Text(
                    '${I18n.of(context).view_comment}${data.commentCountText}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future _longPressTag(BuildContext context, Tags f) async {
    switch (await showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: "${f.name}",
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (f.translatedName != null)
                  TextSpan(
                    text: "\n${"${f.translatedName}"}",
                    style: Theme.of(context).textTheme.bodyLarge!,
                  ),
              ],
            ),
          ),
          children: <Widget>[
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 0);
              },
              child: Text(I18n.of(context).ban),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 1);
              },
              child: Text(I18n.of(context).bookmark),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 2);
              },
              child: Text(I18n.of(context).copy),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 3);
              },
              child: const Text("查看本地下载"),
            ),
            if (tagManagerStore.getTagDisplayData(f.name) != null)
              SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, 4);
                },
                child: const Text("编辑标签"),
              ),
          ],
        );
      },
    )) {
      case 0:
        {
          muteStore.insertBanTag(
            BanTagPersist(name: f.name, translateName: f.translatedName ?? ""),
          );
        }
        break;
      case 1:
        {
          await tagManagerStore.bookTag(f.name);
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
        break;
      case 3:
        {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DownloadedPage(initialTagName: f.name),
            ),
          );
        }
        break;
      case 4:
        _showEditTagDialog(context, f);
        break;
    }
  }

  Future _showTagContextMenu(
    BuildContext context,
    Tags f,
    Offset position,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final result = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              Icon(Icons.copy, size: 20),
              SizedBox(width: 12),
              Text(I18n.of(context).copy),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              Icon(Icons.bookmark_outline, size: 20),
              SizedBox(width: 12),
              Text(I18n.of(context).bookmark),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 2,
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 20),
              SizedBox(width: 12),
              Text('查看本地下载'),
            ],
          ),
        ),
        if (tagManagerStore.getTagDisplayData(f.name) != null)
           const PopupMenuItem<int>(
            value: 4,
            child: Row(
              children: [
                Icon(Icons.edit, size: 20),
                SizedBox(width: 12),
                Text('编辑标签'),
              ],
            ),
          ),
        // 自定义标签删除选项
        if (_customTagNames.contains(f.name))
          PopupMenuItem<int>(
            value: 5,
            child: Row(
              children: [
                Icon(Icons.delete, size: 20, color: Colors.red),
                SizedBox(width: 12),
                Text('删除自定义标签', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
      ],
    );

    if (result != null) {
      switch (result) {
        case 0:
          await Clipboard.setData(ClipboardData(text: f.name));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: Duration(seconds: 1),
              content: Text(I18n.of(context).copied_to_clipboard),
            ),
          );
          break;
        case 1:
          await tagManagerStore.bookTag(f.name);
          break;
        case 2:
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DownloadedPage(initialTagName: f.name),
            ),
          );
          break;
        case 3:
          _showEditTagDialog(context, f);
          break;
        case 4:
          _showEditTagDialog(context, f);
          break;
        case 5:
          // 删除自定义标签
          await tagManagerStore.removeCustomTagFromIllust(_illusts.id, f.name);
          await _checkDownloadStatus(); // 刷新状态
          break;
      }
      }
    }



  Widget buildRow(BuildContext context, Tags f) {
    final theme = Theme.of(context);
    // Attempt to match custom translation or bookmark status
    final localTag = tagManagerStore.getTagDisplayData(f.name);
    final isBookmarked = localTag?.tag.isBookmarked ?? false;
    final isClassified = localTag != null && localTag.tag.category != 0;

    final customTranslation = localTag?.tag.customTranslatedName;
    final isCustom = customTranslation?.isNotEmpty == true;
    final displayTranslation = isCustom ? customTranslation : f.translatedName;

    // 获取父标签的翻译名称
    String? parentName;
    if (localTag != null && localTag.tag.parentId != 0) {
        final parentData = tagManagerStore.getTagDisplayDataByID(localTag.tag.parentId);
        if (parentData != null) {
            parentName = parentData.tag.displayName;
        }
    }

    return InkWell(
      onLongPress: () async {
        await _longPressTag(context, f);
      },
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) {
              return ResultPage(
                word: f.name,
                translatedName: f.translatedName ?? "",
              );
            },
          ),
        );
      },
      onSecondaryTapDown: (details) async {
        await _showTagContextMenu(context, f, details.globalPosition);
      },
      mouseCursor: SystemMouseCursors.click,
      borderRadius: const BorderRadius.all(Radius.circular(12.5)),
      child: Tooltip(
        message: () {
          final parts = <String>[f.name];
          if (displayTranslation != null) {
            parts.add(' ($displayTranslation)');
          }
          if (parentName != null && parentName.isNotEmpty) {
            parts.add('($parentName)');
          }
          return parts.join('');
        }(),
        child: Container(
          height: 25,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: const BorderRadius.all(Radius.circular(12.5)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RichText(
                textAlign: TextAlign.start,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: isClassified ? "● " : "#",
                      style: TextStyle(
                        color: isClassified
                            ? (localTag.tag.categoryEnum.color ??
                                theme.colorScheme.primary)
                            : theme.colorScheme.primary,
                        fontSize: isClassified ? 10 : 12,
                      ),
                    ),
                    TextSpan(text: f.name),
                    if (displayTranslation != null) ...[
                      const TextSpan(text: " "),
                      TextSpan(
                        text: displayTranslation,
                        style: TextStyle(
                          color: isCustom ? Colors.purple : null,
                        ),
                      ),
                    ],
                    if (parentName != null && parentName.isNotEmpty)
                        TextSpan(
                            text: "($parentName)",
                             style: theme.textTheme.titleSmall!.copyWith(
                                color: theme.colorScheme.primary.withOpacity(0.7),
                                fontSize: 11,
                             ),
                        ),
                  ],
                  style: theme.textTheme.titleSmall!.copyWith(
                    color:
                        isBookmarked
                            ? Colors.deepOrange
                            : theme.colorScheme.primary,
                    fontSize: 12,
                    fontWeight: isBookmarked ? FontWeight.bold : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _push2UserPage(BuildContext context, Illusts illust) async {
    await Leader.push(
      context,
      UsersPage(
        id: illust.user.id,
        userStore: userStore,
        heroTag: this.hashCode.toString(),
      ),
    );
    widget.illustStore.illusts!.user.isFollowed = userStore!.isFollow;
  }
  
  // 添加标签按钮
  Widget _buildAddTagButton(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _showTagSelectionDialog(context),
      child: Container(
        height: 25,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12.5),
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: theme.colorScheme.primary),
            SizedBox(width: 4),
            Text(
              '添加标签',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 显示标签选择对话框
  Future<void> _showTagSelectionDialog(BuildContext context) async {
    // 获取所有可用标签（排除已有的原始标签和自定义标签）
    await tagManagerStore.loadTags();
    final allTags = tagManagerStore.tags;
    
    final existingTagNames = [
      ..._illusts.tags.map((t) => t.name),
      ..._customTagNames,
    ].toSet();
    
    final availableTags = allTags
        .where((tagData) =>
            !existingTagNames.contains(tagData.tag.name) &&
            tagData.tag.referencedTagId == 0) // 仅显示主标签（排除等效别名标签）
        .toList();
    
    if (!context.mounted) return;
    
    // 创建简化的标签选择对话框
    final selectedTag = await _showTagPickerDialog(context, availableTags);
    
    if (selectedTag != null) {
      await tagManagerStore.addCustomTagToIllust(_illusts.id, selectedTag.tag.name);
      await _checkDownloadStatus(); // 刷新状态
    }
  }
  
  // 简化的标签选择对话框
  Future<TagDisplayData?> _showTagPickerDialog(
    BuildContext context,
    List<TagDisplayData> availableTags,
  ) async {
    final searchController = TextEditingController();
    List<TagDisplayData> filteredTags = List.from(availableTags);
    
    return await showDialog<TagDisplayData>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('选择标签'),
            content: SizedBox(
              width: 400,
              height: 600,
              child: Column(
                children: [
                  // 搜索框
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: '搜索标签',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (query) {
                      setState(() {
                        if (query.isEmpty) {
                          filteredTags = List.from(availableTags);
                        } else {
                          filteredTags = availableTags.where((tagData) {
                            final name = tagData.tag.name.toLowerCase();
                            final translatedName = tagData.tag.displayTranslatedName.toLowerCase();
                            final q = query.toLowerCase();
                            return name.contains(q) || translatedName.contains(q);
                          }).toList();
                        }
                      });
                    },
                  ),
                  SizedBox(height: 12),
                  
                  // 标签列表
                  Expanded(
                    child: filteredTags.isEmpty
                        ? Center(child: Text('没有可用的标签'))
                        : ListView.builder(
                            itemCount: filteredTags.length,
                            itemBuilder: (context, index) {
                              final tagData = filteredTags[index];
                              return ListTile(
                                leading: Icon(
                                  Icons.local_offer,
                                  color: tagData.tag.categoryEnum.color,
                                ),
                                title: Text(tagData.tag.name),
                                subtitle: tagData.tag.displayTranslatedName.isNotEmpty
                                    ? Text(tagData.tag.displayTranslatedName)
                                    : null,
                                trailing: Text(
                                  '${tagData.tag.count}',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                onTap: () {
                                  searchController.dispose();
                                  Navigator.pop(context, tagData);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  searchController.dispose();
                  Navigator.pop(context);
                },
                child: Text('取消'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditTagDialog(BuildContext context, Tags f) {
    final localTag = tagManagerStore.getTagDisplayData(f.name);
    if (localTag != null && context.mounted) {
      final comicTagDatas = _illusts.tags
          .map((t) => tagManagerStore.getTagDisplayData(t.name))
          .whereType<TagDisplayData>()
          .toList();
      showDialog(
        context: context,
        builder: (context) => TagEditDialog(
          tag: localTag.tag,
          comicTags: comicTagDatas,
        ),
      );
    }
  }

  Widget _buildNameAvatar(BuildContext context, Illusts illust) {
    if (userStore == null)
      userStore = UserStore(illust.user.id, null, illust.user);
    return Observer(
      builder: (_) {
        return InkWell(
          onTap: () async {
            await _push2UserPage(context, illust);
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Padding(
                child: Hero(
                  tag:
                      illust.user.profileImageUrls.medium +
                      this.hashCode.toString(),
                  child: PainterAvatar(
                    url: illust.user.profileImageUrls.medium,
                    id: illust.user.id,
                    size: Size(32, 32),
                    onTap: () async {
                      await Leader.push(
                        context,
                        UsersPage(
                          id: illust.user.id,
                          userStore: userStore,
                          heroTag: this.hashCode.toString(),
                        ),
                      );
                      widget.illustStore.illusts!.user.isFollowed =
                          userStore!.isFollow;
                    },
                  ),
                ),
                padding: EdgeInsets.only(left: 16.0),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      Hero(
                        tag: illust.user.name + this.hashCode.toString(),
                        child: SelectionArea(
                          child: GestureDetector(
                            onTap: () {
                              _push2UserPage(context, illust);
                            },
                            child: Text(
                              illust.user.name,
                              style: TextStyle(
                                fontSize: 14,
                                color:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodySmall!.color,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              UserFollowButton(
                id: illust.user.id,
                followed:
                    userStore?.isFollow ?? illust.user.isFollowed ?? false,
                onPressed: () async {
                  await userStore?.follow();
                  if (userStore?.isFollow != null) {
                    widget.illustStore.illusts?.user.isFollowed =
                        userStore?.isFollow;
                  }
                },
                onConfirm: (follow, restrict) {
                  userStore?.followWithRestrict(follow, restrict);
                  if (userStore?.isFollow != null) {
                    widget.illustStore.illusts?.user.isFollowed =
                        userStore?.isFollow;
                  }
                },
              ),
              SizedBox(width: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> supportTranslateCheck() async {
    if (!Platform.isAndroid) return;
    bool results = await SupportorPlugin.processText();
    if (mounted) {
      setState(() {
        supportTranslate = results;
      });
    }
  }
}
