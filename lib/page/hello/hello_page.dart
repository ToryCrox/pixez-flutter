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
import 'package:pixez/component/keep_alive_wrapper.dart';
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
import 'package:pixez/page/history/history_page.dart';
import 'package:pixez/page/theme/theme_page.dart';
import 'package:pixez/page/preview/preview_page.dart';
import 'package:pixez/page/search/search_page.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/page/downloaded/tag_manager/tag_manager_page.dart';
import 'package:pixez/page/hello/component/side_rail.dart';

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
  bool? _isWideScreen;
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
      Observer(
        builder: (context) {
          if (accountStore.now != null)
            return RecomSpolightPage();
          else
            return PreviewPage();
        },
      ),
      Observer(
        builder: (context) {
          if (accountStore.now != null)
            return RankPage();
          else
            return Column(
              children: [
                AppBar(title: Text('rank(day)')),
                Expanded(child: PreviewPage()),
              ],
            );
        },
      ),
      NewPage(),
      SearchPage(),
      SettingPage(),
    ];
    _wideLists = <Widget>[
      ..._lists,
      KeepAliveWrapper(child: DownloadedPage()),
      KeepAliveWrapper(child: DownloadedAuthorsPage()),
      KeepAliveWrapper(child: TagManagerPage()),
    ];
    Constants.type = 0;

    index = userSetting.welcomePageNum;
    _pageController = PageController(initialPage: userSetting.welcomePageNum);
    super.initState();
    initLinksStream();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    if (Prefer.getInt('language_num') == null) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (context) => GuidePage()));
    }
  }

  Future<void> initLinksStream() async {
    try {
      Uri? initialLink = await DeepLinkPlugin.getInitialUri();
      if (initialLink != null) Leader.pushWithUri(context, initialLink);
      _sub = DeepLinkPlugin.uriLinkStream.listen(
        (Uri? link) => Leader.pushWithUri(context, link!),
      );
    } catch (e) {
      Log.e('Failed to initialize links stream', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (bottomNavigatorHeight == null) {
      bottomNavigatorHeight = MediaQuery.of(context).padding.bottom + 80;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_isWideScreen == null) {
          _isWideScreen = constraints.maxWidth > constraints.maxHeight;
        }
        final wide = _isWideScreen!;
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
            body: Builder(
              builder:
                  (context) => Row(
                    children: <Widget>[
                      if (wide) ...[
                        Observer(
                          builder: (context) {
                            final bool isFullscreen =
                                fullScreenStore.fullscreen;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              width:
                                  isFullscreen
                                      ? 0
                                      : 37, // 36 (SideRail) + 1 (Divider)
                              child: ClipRect(
                                child: OverflowBox(
                                  minWidth: 37,
                                  maxWidth: 37,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SideRail(
                                        width: 36,
                                        selectedIndex: index,
                                        onDestinationSelected: (int index) {
                                          // 如果右侧 Navigator 有子页面，先清除栈回到主页面
                                          if (_contentNavigatorKey
                                                  .currentState !=
                                              null) {
                                            _contentNavigatorKey.currentState!
                                                .popUntil(
                                                  (route) => route.isFirst,
                                                );
                                          }
                                          _pageController.jumpToPage(index);

                                          setState(() {
                                            this.index = index;
                                          });
                                        },
                                        destinations: <
                                          NavigationRailDestination
                                        >[
                                          NavigationRailDestination(
                                            icon: Icon(Icons.home),
                                            label: Text(I18n.of(context).home),
                                          ),
                                          NavigationRailDestination(
                                            icon: Icon(Icons.leaderboard),
                                            label: Text(I18n.of(context).rank),
                                          ),
                                          NavigationRailDestination(
                                            icon: Icon(Icons.favorite),
                                            label: Text(
                                              I18n.of(context).quick_view,
                                            ),
                                          ),
                                          NavigationRailDestination(
                                            icon: Icon(Icons.search),
                                            label: Text(
                                              I18n.of(context).search,
                                            ),
                                          ),
                                          NavigationRailDestination(
                                            icon: Icon(Icons.more_horiz),
                                            label: Text(I18n.of(context).more),
                                          ),
                                          NavigationRailDestination(
                                            icon: Icon(Icons.download),
                                            label: Text('下载'),
                                          ),
                                          NavigationRailDestination(
                                            icon: Icon(Icons.person),
                                            label: Text('作者'),
                                          ),
                                          NavigationRailDestination(
                                            icon: Icon(Icons.label),
                                            label: Text('标签管理'),
                                          ),
                                        ],
                                        trailing: _buildTrailing(context),
                                      ),
                                      const VerticalDivider(
                                        thickness: 1,
                                        width: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      Expanded(child: _buildPageView(context, wide)),
                    ],
                  ),
            ),
            extendBody: true,
            bottomNavigationBar:
                wide
                    ? null
                    : Observer(
                      builder: (context) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          transform: Matrix4.translationValues(
                            0,
                            fullScreenStore.fullscreen
                                ? bottomNavigatorHeight!
                                : 0,
                            0,
                          ),
                          child: _buildNavigationBar(context),
                        );
                      },
                    ),
          ),
        );
      },
    );
  }

  Widget _buildTrailing(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: MediaQuery.of(context).padding.left,
        bottom: MediaQuery.of(context).padding.bottom + 4.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 历史记录按钮
          IconButton(
            icon: Icon(Icons.history),
            tooltip: I18n.of(context).history,
            onPressed: () {
              // 在宽屏模式下使用右侧导航器
              final wideScreenNav = WideScreenNavigator.of(context);
              if (wideScreenNav != null &&
                  wideScreenNav.isWideScreen &&
                  wideScreenNav.contentNavigatorKey != null) {
                wideScreenNav.contentNavigatorKey!.currentState?.push(
                  MaterialPageRoute(builder: (context) => HistoryPage()),
                );
              } else {
                Leader.push(context, HistoryPage());
              }
            },
          ),
          // 主题设置按钮
          IconButton(
            icon: Icon(Icons.palette),
            tooltip: '主题设置',
            onPressed: () async {
              await showDialog(
                context: context,
                barrierColor: Colors.transparent,
                builder: (context) {
                  return Dialog(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 400,
                        maxHeight: MediaQuery.of(context).size.height * 0.6,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ThemePage(),
                      ),
                    ),
                  );
                },
              );
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
              child:
                  accountStore.now != null
                      ? PainterAvatar(
                        url: accountStore.now!.userImage,
                        id: int.tryParse(accountStore.now!.userId) ?? 0,
                      )
                      : Container(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBar(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: NavigationBar(
          height: 68,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surface.withValues(alpha: 0.9),
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.home),
              label: I18n.of(context).home,
            ),
            NavigationDestination(
              icon: Icon(Icons.leaderboard),
              label: I18n.of(context).rank,
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite),
              label: I18n.of(context).quick_view,
            ),
            NavigationDestination(
              icon: Icon(Icons.search),
              label: I18n.of(context).search,
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: I18n.of(context).more,
            ),
          ],
          selectedIndex: index,
          onDestinationSelected: (value) {
            // 切换 Tab 时清除 Navigator 栈
            if (_contentNavigatorKey.currentState != null) {
              _contentNavigatorKey.currentState!.popUntil(
                (route) => route.isFirst,
              );
            }
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
      key: const ValueKey('hello_page_view'),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      controller: _pageController,
      onPageChanged: (index) {
        setState(() {
          this.index = index;
        });
      },
      itemBuilder: (context, index) {
        return list[index];
      },
    );

    final Widget content;
    if (isWideScreen) {
      content = Navigator(
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
      );
    } else {
      content = pageView;
    }

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): const _GoBackIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _GoBackIntent: CallbackAction<_GoBackIntent>(
            onInvoke: (intent) {
              if (isWideScreen) {
                _contentNavigatorKey.currentState?.maybePop();
              } else {
                Navigator.of(context).maybePop();
              }
              return null;
            },
          ),
        },
        child: content,
      ),
    );
  }
}

class _GoBackIntent extends Intent {
  const _GoBackIntent();
}
