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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/page/user/users_page.dart';

class PainterAvatar extends StatefulWidget {
  final String url;
  final int id;
  final GestureTapCallback? onTap;
  final Size? size;

  const PainterAvatar(
      {Key? key, required this.url, required this.id, this.onTap, this.size})
      : super(key: key);

  @override
  _PainterAvatarState createState() => _PainterAvatarState();
}

class _PainterAvatarState extends State<PainterAvatar> {
  void pushToUserPage() {
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) {
      return UsersPage(id: widget.id);
    }));
  }

  void _handleTap() {
    if (widget.onTap == null) {
      pushToUserPage();
    } else {
      widget.onTap!();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 统一尺寸处理，默认 60x60
    final size = widget.size ?? const Size(60.0, 60.0);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: _handleTap,
      child: CachedNetworkImage(
        imageUrl: widget.url,
        cacheManager: pixivCacheManager,
        httpHeaders: Hoster.header(url: widget.url),
        imageBuilder: (context, imageProvider) => Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(
              image: imageProvider,
              fit: BoxFit.cover,
            ),
          ),
        ),
        placeholder: (context, url) => Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.cardColor,
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.cardColor,
          ),
        ),
      ),
    );
  }
}
