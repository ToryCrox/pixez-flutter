import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:pixez/component/keep_alive_wrapper.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/page/novel/new/novel_new_page.dart';
import 'package:pixez/page/novel/rank/novel_rank_page.dart';
import 'package:pixez/page/novel/recom/novel_recom_page.dart';
import 'package:pixez/page/novel/search/novel_search_page.dart';

/// 桌面端小说入口。
///
/// 小说在桌面端是主框架右侧内容区的一个页面，而不是替换整个应用。
/// 顶部标签通过 SafeArea 避开 Windows 自绘标题栏。
class NovelDesktopPage extends StatefulWidget {
  const NovelDesktopPage({super.key});

  @override
  State<NovelDesktopPage> createState() => _NovelDesktopPageState();
}

class _NovelDesktopPageState extends State<NovelDesktopPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabController;
  bool _showPrimaryTabs = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          ClipRect(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              heightFactor: _showPrimaryTabs ? 1 : 0,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: I18n.of(context).recommend),
                    Tab(text: I18n.of(context).rank),
                    Tab(text: I18n.of(context).news),
                    Tab(text: I18n.of(context).search),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              onNotification: _handleScrollNotification,
              child: TabBarView(
                controller: _tabController,
                children: [
                  KeepAliveWrapper(child: NovelRecomPage()),
                  KeepAliveWrapper(child: NovelRankPage()),
                  KeepAliveWrapper(child: NovelNewPage()),
                  KeepAliveWrapper(child: NovelSearchPage()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _handleScrollNotification(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    final showTabs = switch (notification.direction) {
      ScrollDirection.forward => true,
      ScrollDirection.reverse => false,
      ScrollDirection.idle => _showPrimaryTabs,
    };
    if (showTabs != _showPrimaryTabs) {
      setState(() => _showPrimaryTabs = showTabs);
    }
    return false;
  }

  @override
  bool get wantKeepAlive => true;
}
