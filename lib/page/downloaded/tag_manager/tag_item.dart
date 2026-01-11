import 'package:flutter/material.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/tag_manager/tag_edit_dialog.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/page/downloaded/downloaded_page.dart';

class TagItem extends StatelessWidget {
  final TagDisplayData data;

  const TagItem({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    // 动态计算宽高比，避免瀑布流布局跳动
    // 根据封面数量决定
    // 0: 仅文字 -> 较小高度
    // 1: 1张大图 -> 16:9 或 4:3
    // 2-3: 组合图 -> 1:1 或 4:3
    // 这里简单预设一个比例，实际由内容撑开
    
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _navigateToSearchResults(context),
        onLongPress: () => _showEditDialog(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildCoverArea(context),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // First line: Name + Count
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data.tag.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (data.tag.isBookmarked) 
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Icon(
                            Icons.bookmark, 
                            size: 16, 
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      const SizedBox(width: 4),
                      Text(
                        '${data.tag.illustCount}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Second line: Translation
                  Builder(builder: (context) {
                    final translation = (data.tag.customTranslatedName?.isNotEmpty == true)
                        ? data.tag.customTranslatedName!
                        : data.tag.translatedName;
                    return Text(
                      translation,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToSearchResults(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DownloadedPage(
          initialSearchKeyword: data.tag.name,
        ),
      ),
    );
  }

  Widget _buildCoverArea(BuildContext context) {
    if (data.previewIllusts.isEmpty) {
        return Container(color: Colors.grey.withOpacity(0.1));
    }
    
    if (data.previewIllusts.length == 1) {
      return _buildImage(data.previewIllusts.first);
    }
    
    if (data.previewIllusts.length == 2) {
      return Row(
        children: [
          Expanded(flex: 2, child: _buildImage(data.previewIllusts[0])),
          const SizedBox(width: 2),
          Expanded(flex: 1, child: _buildImage(data.previewIllusts[1])),
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 2, child: _buildImage(data.previewIllusts[0])),
        const SizedBox(width: 2),
        Expanded(
          flex: 1,
          child: Column(
            children: [
              Expanded(child: _buildImage(data.previewIllusts[1])),
              const SizedBox(height: 2),
              Expanded(child: _buildImage(data.previewIllusts[2])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImage(DownloadedIllust illust) {
    // 逻辑参考 DownloadedAuthorCard
    final imageUrls = illust.getImageUrls();
    String coverUrl = imageUrls.squareMedium;
    if (coverUrl.isEmpty) {
      final illusts = illust.toIllusts();
      coverUrl = illusts.imageUrls.squareMedium;
    }
    
    return PixivImage(
      coverUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // 通过 header 传递 illustId，让 PixivCacheManager 识别封面请求
      httpHeaders: {'cover': '${illust.illustId}'},
    );
  }

  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => TagEditDialog(tag: data.tag),
    );
  }
}
