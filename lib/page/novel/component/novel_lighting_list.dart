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

import 'package:easy_refresh/easy_refresh.dart';
import 'package:pixez/component/pixez_easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/lighting/lighting_store.dart';
import 'package:pixez/models/novel_recom_response.dart';
import 'package:pixez/page/novel/component/novel_bookmark_button.dart';
import 'package:pixez/page/novel/component/novel_lighting_store.dart';
import 'package:pixez/page/novel/viewer/novel_viewer.dart';
import 'package:pixez/exts.dart';

class NovelLightingList extends StatefulWidget {
  final FutureGet futureGet;
  final bool? isNested;
  final String? cacheKey;

  const NovelLightingList({
    Key? key,
    required this.futureGet,
    this.isNested,
    this.cacheKey,
  }) : super(key: key);

  @override
  _NovelLightingListState createState() => _NovelLightingListState();
}

class _NovelLightingListState extends State<NovelLightingList> {
  late EasyRefreshController _easyRefreshController;
  late NovelLightingStore _store;
  late bool _isNested;

  @override
  void initState() {
    _isNested = widget.isNested ?? false;
    _easyRefreshController = EasyRefreshController(
      controlFinishLoad: true,
      controlFinishRefresh: true,
    );
    _store = NovelLightingStore(
      widget.futureGet,
      _easyRefreshController,
      cacheKey: widget.cacheKey,
    );
    super.initState();
    if (_isNested) _store.fetch();
  }

  @override
  void didUpdateWidget(NovelLightingList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.futureGet != widget.futureGet) {
      _store.source = widget.futureGet;
      _store.cacheKey = widget.cacheKey;
      _store.fetch(loadCache: true);
    }
  }

  @override
  void dispose() {
    _easyRefreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PixezEasyRefresh.builder(
      onLoad: () => _store.next(),
      onRefresh: () => _store.fetch(),
      refreshOnStart: _isNested ? false : true,
      controller: _easyRefreshController,
      header: PixezDefault.header(context),
      childBuilder: (context, physics, scrollController) {
        return Observer(
          builder: (context) {
            final novels = _store.novels
                .where((element) => element.novel?.hateByUser() != true)
                .toList(growable: false);
            return ListView.builder(
              padding: EdgeInsets.all(0),
              physics: physics,
              controller: scrollController,
              itemBuilder: (context, index) {
                Novel novel = novels[index].novel!;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (BuildContext context) => NovelViewerPage(
                                id: novel.id,
                                novelStore: novels[index],
                              ),
                        ),
                      );
                    },
                    child: Card(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                  ),
                                  child: PixivImage(
                                    novel.imageUrls.medium,
                                    width: 80,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8.0,
                                          left: 8.0,
                                        ),
                                        child: Text(
                                          novel.title,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodyLarge,
                                          maxLines: 3,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8.0,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              novel.user.name,
                                              maxLines: 1,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall!.copyWith(
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.secondary,
                                              ),
                                            ),
                                            Padding(
                                              padding: EdgeInsets.only(left: 8),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.article,
                                                    size: 12,
                                                    color:
                                                        Theme.of(context)
                                                            .textTheme
                                                            .labelSmall!
                                                            .color,
                                                  ),
                                                  SizedBox(width: 2),
                                                  Text(
                                                    '${novel.textLength}',
                                                    style:
                                                        Theme.of(
                                                          context,
                                                        ).textTheme.labelSmall,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8.0,
                                        ),
                                        child: Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          spacing: 2,
                                          runSpacing: 0,
                                          children: [
                                            for (var f in novel.tags)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 1,
                                                    ),
                                                child: Text(
                                                  f.name,
                                                  style:
                                                      Theme.of(
                                                        context,
                                                      ).textTheme.bodySmall,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Container(height: 8.0),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                NovelBookmarkButton(novel: novel),
                                Text(
                                  '${novel.totalBookmarks}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              itemCount: novels.length,
            );
          },
        );
      },
    );
  }
}
