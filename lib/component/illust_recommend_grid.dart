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
import 'package:pixez/component/local_or_cached_image.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/picture_list_page.dart';

class IllustRecommendGrid extends StatelessWidget {
  final List<Illusts> illusts;
  final IllustStore? currentIllustStore;
  final bool showLongPressConfirm;
  final int? memCacheWidth;

  const IllustRecommendGrid({
    Key? key,
    required this.illusts,
    this.currentIllustStore,
    this.showLongPressConfirm = true,
    this.memCacheWidth,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          final illust = illusts[index];
          return _buildRecommendItem(context, illust, index);
        },
        childCount: illusts.length,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
      ),
    );
  }

  Widget _buildRecommendItem(BuildContext context, Illusts illust, int index) {
    return InkWell(
      onTap: () {
        final list = illusts
            .map((element) => IllustStore(element.id, element))
            .toList();
        Leader.push(
          context,
          PictureListPage(
            iStores: list,
            lightingStore: null,
            store: list[index],
          ),
        );
      },
      onLongPress: () => _handleLongPress(context, illust),
      child: Stack(
        children: [
          PixivImage(
            illust.imageUrls.squareMedium,
            enableMemoryCache: false,
            fit: BoxFit.cover,
            httpHeaders: {
              'cover': '${illust.id}',
            },
            memCacheWidth: memCacheWidth,
          ),
          Positioned(
            top: 4,
            right: 4,
            child: DownloadStatusIndicator(
              illustId: illust.id,
              pageCount: illust.pageCount,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLongPress(BuildContext context, Illusts illust) async {
    if (showLongPressConfirm) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(I18n.of(context).save),
            content: Text(illust.title),
            actions: <Widget>[
              TextButton(
                child: Text(I18n.of(context).cancel),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: Text(I18n.of(context).ok),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      );
      if (result != true) {
        return;
      }
    }

    if (userSetting.starAfterSave &&
        currentIllustStore != null &&
        currentIllustStore!.state == 0) {
      currentIllustStore!.star(
        restrict: userSetting.defaultPrivateLike ? "private" : "public",
      );
    }

    downloadStore.downloadIllust(illust);
  }
}