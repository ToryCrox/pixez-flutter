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

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/painter_avatar.dart';
import 'package:pixez/constants.dart';
import 'package:pixez/custom/window_frame.dart';
import 'package:pixez/deep_link_plugin.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/Init/guide_page.dart';
import 'package:pixez/page/downloaded/downloaded_authors_page.dart';
import 'package:pixez/page/downloaded/downloaded_page.dart';
import 'package:pixez/page/hello/new/new_page.dart';
import 'package:pixez/page/hello/ranking/rank_page.dart';
import 'package:pixez/page/hello/recom/recom_spotlight_page.dart';
import 'package:pixez/page/hello/setting/setting_page.dart';
import 'package:pixez/page/preview/preview_page.dart';
import 'package:pixez/page/search/search_page.dart';

/// InheritedWidget 用于传递宽屏状态和右侧 Navigator
class WideScreenNavigator extends InheritedWidget {
  final bool isWideScreen;
  final GlobalKey<NavigatorState>? contentNavigatorKey;

  const WideScreenNavigator({
    Key? key,
    required this.isWideScreen,
    this.contentNavigatorKey,
    required Widget child,
  }) : super(key: key, child: child);

  static WideScreenNavigator? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WideScreenNavigator>();
  }

  @override
  bool updateShouldNotify(WideScreenNavigator oldWidget) {
    return isWideScreen != oldWidget.isWideScreen ||
        contentNavigatorKey != oldWidget.contentNavigatorKey;
  }
}

class HelloPage extends StatefulWidget {
  @override
  _HelloPageState createState() => _HelloPageState();
}

class _HelloPageState extends State<HelloPage> {
  late StreamSubscription _sub;
  late int index;
  late PageController _pageController;
  double? bottomNavigatorHeight = null;
  late List<Widget> _lists;
  late List<Widget> _wideLists;
  final GlobalKey<NavigatorState> _contentNavigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void dispose() {
    _sub.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    _lists = <Widget>[
      Observer(builder: (context) {
        if (accountStore.now != null)
          return RecomSpolightPage();
        else
          return PreviewPage();
      }),
      Observer(builder: (context) {
        if (accountStore.now != null)
          return RankPage();
        else
          return Column(children: [
            AppBar(
              title: Text('rank(day)'),
            ),
            Expanded(child: PreviewPage())
          ]);
      }),
      NewPage(),
      SearchPage(),
      SettingPage()
    ];
    _wideLists = <Widget>[
      ..._lists,
      DownloadedPage(),
      DownloadedAuthorsPage(),
    ];
    Constants.type = 0;
    fetcher.context = context;
    index = userSetting.welcomePageNum;
    _pageController = PageController(initialPage: userSetting.welcomePageNum);
    super.initState();
    saveStore.ctx = this.context;
    saveStore.saveStream.listen((stream) {
      saveStore.listenBehavior(stream);
    });
    initLinksStream();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    if (Prefer.getInt('language_num') == null) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => GuidePage()));
    }
  }

  Future<void> initLinksStream() async {
    try {
      Uri? initialLink = await DeepLinkPlugin.getInitialUri();
      if (initialLink != null) Leader.pushWithUri(context, initialLink);
      _sub = DeepLinkPlugin.uriLinkStream
          .listen((Uri? link) => Leader.pushWithUri(context, link!));
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (bottomNavigatorHeight == null) {
      bottomNavigatorHeight = MediaQuery.of(context).padding.bottom + 80;
    }
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > constraints.maxHeight;
      final list = wide ? _wideLists : _lists;
      index = index.clamp(0, list.length - 1);

      // 更新 windowFrameController 的宽屏状态
      if (Platform.isWindows || Platform.isLinux) {
        windowFrameController.isWideScreen = wide;
        windowFrameController.wideScreenNavigatorKey =
            wide ? _contentNavigatorKey : null;
      }

      return WideScreenNavigator(
        isWideScreen: wide,
        contentNavigatorKey: wide ? _contentNavigatorKey : null,
        child: Scaffold(
          body: Row(
            children: <Widget>[
              if (wide) ..._buildRail(context),
              Expanded(
                child: _buildPageView(context, wide),
              ),
            ],
          ),
          extendBody: true,
          bottomNavigationBar: wide
              ? null
              : Observer(builder: (context) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    transform: Matrix4.translationValues(
                        0,
                        fullScreenStore.fullscreen ? bottomNavigatorHeight! : 0,
                        0),
                    child: _buildNavigationBar(context),
                  );
                }),
        ),
      );
    });
  }

  List<Widget> _buildRail(BuildContext context) {
    return [
      Stack(
        children: [
          NavigationRail(
            selectedIndex: index,
            minWidth: 48,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (int index) {
              // 如果右侧 Navigator 有子页面，先清除栈回到主页面
              if (_contentNavigatorKey.currentState != null) {
                _contentNavigatorKey.currentState!
                    .popUntil((route) => route.isFirst);
              }
              _pageController.jumpToPage(index);

              setState(() {
                this.index = index;
              });
            },
            destinations: <NavigationRailDestination>[
              NavigationRailDestination(
                  icon: Icon(Icons.home), label: Text(I18n.of(context).home)),
              NavigationRailDestination(
                  icon: Icon(Icons.leaderboard),
                  label: Text(I18n.of(context).rank)),
              NavigationRailDestination(
                  icon: Icon(Icons.favorite),
                  label: Text(I18n.of(context).quick_view)),
              NavigationRailDestination(
                  icon: Icon(Icons.search),
                  label: Text(I18n.of(context).search)),
              NavigationRailDestination(
                  icon: Icon(Icons.more_horiz),
                  label: Text(I18n.of(context).more)),
              NavigationRailDestination(
                  icon: Icon(Icons.download), label: Text('下载')),
              NavigationRailDestination(
                icon: Icon(Icons.person),
                label: Text('作者'),
              )
            ],
          ),
          Positioned(
            left: 0.0,
            right: 0.0,
            bottom: 0.0,
            child: Padding(
              padding: EdgeInsets.only(
                  left: MediaQuery.of(context).padding.left,
                  bottom: MediaQuery.of(context).padding.bottom + 4.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 已下载按钮
                  IconButton(
                    icon: Icon(Icons.download_done),
                    tooltip: I18n.of(context).history,
                    onPressed: () {
                      Leader.push(context, DownloadedPage());
                    },
                  ),
                  SizedBox(height: 8),
                  // 用户头像
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: accountStore.now != null
                          ? PainterAvatar(
                              url: accountStore.now!.userImage,
                              id: int.tryParse(accountStore.now!.userId) ?? 0)
                          : Container(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      const VerticalDivider(thickness: 1, width: 1),
    ];
  }

  Widget _buildNavigationBar(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: NavigationBar(
          height: 68,
          backgroundColor:
              Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
          destinations: [
            NavigationDestination(
                icon: Icon(Icons.home), label: I18n.of(context).home),
            NavigationDestination(
                icon: Icon(
                  Icons.leaderboard,
                ),
                label: I18n.of(context).rank),
            NavigationDestination(
                icon: Icon(Icons.favorite), label: I18n.of(context).quick_view),
            NavigationDestination(
                icon: Icon(Icons.search), label: I18n.of(context).search),
            NavigationDestination(
                icon: Icon(Icons.more_horiz), label: I18n.of(context).more)
          ],
          selectedIndex: index,
          onDestinationSelected: (value) {
            if (this.index == value) {
              topStore.setTop("${value + 1}00");
            }
            setState(() {
              this.index = value;
            });
            if (_pageController.hasClients) _pageController.jumpToPage(value);
          },
        ),
      ),
    );
  }

  Widget _buildPageView(BuildContext context, bool isWideScreen) {
    final list = isWideScreen ? _wideLists : _lists;
    final pageView = PageView.builder(
        itemCount: list.length,
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            this.index = index;
          });
        },
        itemBuilder: (context, index) {
          return list[index];
        });

    // 在宽屏状态下，将 PageView 包裹在 Navigator 中
    if (isWideScreen) {
      return Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.escape):
              const _GoBackIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _GoBackIntent: CallbackAction<_GoBackIntent>(
              onInvoke: (intent) =>
                  Navigator.of(_contentNavigatorKey.currentContext!).maybePop(),
            ),
          },
          child: Navigator(
            key: _contentNavigatorKey,
            observers: [HeroController()],
            onGenerateRoute: (settings) {
              // 默认路由显示 PageView
              if (settings.name == '/') {
                return MaterialPageRoute(
                  builder: (context) => pageView,
                  settings: settings,
                );
              }
              // 其他路由由 push 方法创建
              return null;
            },
            initialRoute: '/',
          ),
        ),
      );
    } else {
      return pageView;
    }
  }
}

class _GoBackIntent extends Intent {
  const _GoBackIntent();
}
