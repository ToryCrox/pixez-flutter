import 'package:flutter/material.dart';
import 'package:pixez/page/user/user_store.dart';
import 'package:pixez/page/user/users_page.dart';

/// 兼容既有小说入口；实际展示统一个人主页，并默认选中小说作品 Tab。
class NovelUsersPage extends StatelessWidget {
  final int id;
  final UserStore? userStore;
  final String? heroTag;

  const NovelUsersPage({
    super.key,
    required this.id,
    this.userStore,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return UsersPage(
      id: id,
      userStore: userStore,
      heroTag: heroTag,
      initialTab: UserPageInitialTab.novel,
    );
  }
}
