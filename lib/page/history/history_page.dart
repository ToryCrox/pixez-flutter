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

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/constants.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/models/illust_persist.dart';
import 'package:pixez/page/history/history_store.dart';
import 'package:pixez/page/picture/illust_lighting_page.dart';
import 'package:pixez/page/picture/illust_store.dart';

class HistoryPage extends HookConsumerWidget {
  const HistoryPage({super.key});

  Widget buildAppBarUI(context) => Container(
        child: Padding(
          child: Text(
            I18n.of(context).history,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30.0),
          ),
          padding: EdgeInsets.only(left: 20.0, top: 30.0, bottom: 30.0),
        ),
      );

  Widget buildBody(List<IllustPersist> data, WidgetRef ref) {
    final reIllust = data.reversed.toList();
    if (reIllust.isNotEmpty) {
      return GridView.builder(
          itemCount: reIllust.length,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 250, // 每个网格项的最大宽度
            childAspectRatio: 0.65, // 调整宽高比以容纳标题和作者信息
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            return _buildHistoryItem(context, reIllust[index], ref);
          });
    }
    return Center(
      child: Container(),
    );
  }

  Widget _buildHistoryItem(
      BuildContext context, IllustPersist illust, WidgetRef ref) {
    final heroTag = '${illust.illustId}_history';
    return InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (BuildContext context) {
            return IllustLightingPage(
              id: illust.illustId,
              heroString: heroTag,
              store: IllustStore(illust.illustId, null),
            );
          }));
        },
        onLongPress: () async {
          final result = await showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: Text("${I18n.of(context).delete}?"),
                  actions: <Widget>[
                    TextButton(
                      child: Text(I18n.of(context).cancel),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                    TextButton(
                      child: Text(I18n.of(context).ok),
                      onPressed: () {
                        Navigator.of(context).pop("OK");
                      },
                    ),
                  ],
                );
              });
          if (result == "OK") {
            ref.read(historyProvider.notifier).delete(illust.illustId);
          }
        },
        child: Card(
          margin: EdgeInsets.all(8),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 图片部分 - 使用 Hero 包裹
              Expanded(
                child: Hero(
                  tag: heroTag,
                  child: Container(
                    width: double.infinity,
                    child: PixivImage(
                      illust.pictureUrl,
                      fit: BoxFit.cover,
                      // 通过 header 传递 illustId，让 PixivCacheManager 识别封面请求并优先使用本地已下载的封面
                      httpHeaders: {
                        'cover': '${illust.illustId}',
                        'quality': Constants.qualitySquareMedium
                      },
                    ),
                  ),
                ),
              ),
              // 信息部分 - 固定高度避免图片大小不一致
              SizedBox(
                height: 76, // 固定信息区域高度，确保两行标题不被截断
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 标题
                      if (illust.title != null && illust.title!.isNotEmpty)
                        Flexible(
                          child: Text(
                            illust.title!,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      // 作者名
                      if (illust.userName != null &&
                          illust.userName!.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 4.0),
                          child: Text(
                            illust.userName!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withOpacity(0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataFuture = ref.watch(historyProvider);
    final _textEditingController = useTextEditingController();
    useEffect(() {
      Future.delayed(Duration.zero, () async {
        await ref.read(historyProvider.notifier).fetch();
      });
      return null;
    }, []);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
            controller: _textEditingController,
            onChanged: (word) {
              if (word.trim().isNotEmpty) {
                ref.read(historyProvider.notifier).search(word.trim());
              } else {
                ref.read(historyProvider.notifier).fetch();
              }
            },
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: I18n.of(context).search_word_hint,
            )),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.close),
            onPressed: () {
              _textEditingController.clear();
              ref.read(historyProvider.notifier).fetch();
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.delete),
        onPressed: () {
          _cleanAll(context, ref);
        },
      ),
      body: buildBody(dataFuture.data, ref),
    );
  }

  Future<void> _cleanAll(BuildContext context, WidgetRef ref) async {
    final result = await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("${I18n.of(context).delete} ${I18n.of(context).all}?"),
            actions: <Widget>[
              TextButton(
                child: Text(I18n.of(context).cancel),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text(I18n.of(context).ok),
                onPressed: () {
                  Navigator.of(context).pop("OK");
                },
              ),
            ],
          );
        });
    if (result == "OK") {
      ref.read(historyProvider.notifier).deleteAll();
    }
  }
}
