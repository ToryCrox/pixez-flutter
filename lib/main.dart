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

import 'package:flutter/gestures.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pixez/custom/window_frame.dart';
import 'package:pixez/er/prefer.dart';

import 'package:pixez/i18n.dart';
import 'package:pixez/page/novel/history/novel_history_store.dart';
import 'package:pixez/page/splash/splash_page.dart';
import 'package:pixez/page/splash/splash_store.dart';
import 'package:pixez/paths_plugin.dart';
import 'package:pixez/single_instance_plugin.dart';
import 'package:pixez/src/generated/i18n/app_localizations.dart';
import 'package:pixez/store/account_store.dart';
import 'package:pixez/store/book_tag_store.dart';
import 'package:pixez/store/download_store.dart';
import 'package:pixez/store/fullscreen_store.dart';
import 'package:pixez/store/mute_store.dart';

import 'package:pixez/store/tag_history_store.dart';
import 'package:pixez/store/top_store.dart';
import 'package:pixez/store/user_setting.dart';
import 'package:pixez/store/tag_manager_store.dart';
import 'package:pixez/page/task/pending_download_dialog.dart';
import 'package:pixez/custom/image_cache_manager.dart';
import 'package:rhttp/rhttp.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:pixez/debug/mana_manager.dart';
import 'package:pixez/component/network_speed_floating_ball.dart';

import 'custom/log.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();
final UserSetting userSetting = UserSetting();

final MuteStore muteStore = MuteStore();
final AccountStore accountStore = AccountStore();
final TagHistoryStore tagHistoryStore = TagHistoryStore();
final NovelHistoryStore novelHistoryStore = NovelHistoryStore();
final TopStore topStore = TopStore();
final BookTagStore bookTagStore = BookTagStore();
final SplashStore splashStore = SplashStore();
final TagManagerStore tagManagerStore = TagManagerStore();

final FullScreenStore fullScreenStore = FullScreenStore();
final DownloadStore downloadStore = DownloadStore();

final globalNavigatorKey = GlobalKey<NavigatorState>();

main(List<String> args) async {
  await Rhttp.init();

  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    // sqflite ffi init
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbPath = await Paths.getDatabaseFolderPath();
    if (dbPath != null) databaseFactory.setDatabasesPath(dbPath);

    // 确保只有一个实例正在运行
    // Android 和 iOS 应用本身就是单例程序，无需额外操作
    SingleInstancePlugin.initialize();
  }
  if (Platform.isWindows || Platform.isLinux) {
    // 初始化 SharedPreferences，用于保存窗口位置等配置
    await Prefer.init();
    await initWindows(args);
  }

  // 初始化 Mana 调试工具
  ManaManager.instance.initialize();

  final app = ProviderScope(child: MyApp(arguments: args));

  // 根据配置决定是否启用 ManaWidget
  //runApp(ManaManager.instance.isEnabled ? ManaWidget(child: app) : app);
  runApp(app);
}

class MyApp extends StatefulWidget {
  final List<String> arguments;

  const MyApp({super.key, required this.arguments});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  AppLifecycleState? _appState;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _appState = state;
    });
  }

  @override
  void dispose() {
    topStore.dispose();
    subscription.cancel();
    if (Platform.isIOS) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  late StreamSubscription<String> subscription;

  Future<void> _initDownloadStore() async {
    // 获取下载目录 - 优先使用 userSetting.downloadPath
    String? downloadPath = userSetting.downloadPath;
    Log.d("downloadPath: $downloadPath");

    // 如果仍然没有设置目录，使用默认目录
    if (downloadPath == null || downloadPath.isEmpty) {
      final docDir = await getApplicationDocumentsDirectory();
      downloadPath = '${docDir.path}/pixez/downloads';
    }

    // 初始化 downloadStore
    await downloadStore.init(
      downloadPath,
      maxConcurrent: userSetting.maxRunningTask,
    );

    // 后台更新缺少宽高信息的历史图片（每次启动时处理一批）
    //_updateMissingImageDimensions();

    // 加载待下载任务并提示用户确认
    if (Platform.isWindows || Platform.isLinux) {
      _checkPendingDownloads();
    }
  }

  /// 后台更新缺少宽高信息的历史图片
  Future<void> _updateMissingImageDimensions() async {
    // 延迟执行，避免影响启动性能
    await Future.delayed(Duration(seconds: 5));
    // 每次启动处理一批（50张），逐步更新历史数据
    await downloadStore.updateMissingImageDimensions(batchSize: 50);
  }

  Future<void> _checkPendingDownloads() async {
    // 延迟一下,等待UI完全初始化
    await Future.delayed(Duration(seconds: 2));

    final pendingTasks = await downloadStore.loadPendingTasks();
    if (pendingTasks.isEmpty) return;

    // 弹出确认对话框
    final context = globalNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    final selectedTaskKeys = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PendingDownloadDialog(tasks: pendingTasks),
    );

    if (selectedTaskKeys == null || selectedTaskKeys.isEmpty) {
      // // 用户取消了所有任务,清除数据库记录
      await downloadStore.addPausedTasks(pendingTasks);
      return;
    }

    // 用户确认了部分任务,添加到下载队列
    final tasksToDownload =
        pendingTasks
            .where((t) => selectedTaskKeys.contains(t.taskKey))
            .toList();

    // 清除未选中的任务
    final tasksToRemove =
        pendingTasks
            .where((t) => !selectedTaskKeys.contains(t.taskKey))
            .toList();
    if (tasksToRemove.isNotEmpty) {
      await downloadStore.addPausedTasks(tasksToRemove);
    }

    // 添加选中的任务到下载队列
    if (tasksToDownload.isNotEmpty) {
      await downloadStore.addDownloadTasks(tasksToDownload);
    }
  }

  @override
  void initState() {
    subscription = topStore.topStream.listen((event) {
      if (event == "main") {
        setState(() {});
      }
    });

    // 初始化异步操作
    _initialize();

    super.initState();
    if (Platform.isIOS) WidgetsBinding.instance.addObserver(this);

    Future.delayed(Duration.zero, () {
      SingleInstancePlugin.argsParser(widget.arguments);
    });
  }

  Future<void> _initialize() async {
    userSetting.askInit();
    await userSetting.init(); // 等待 userSetting 初始化完成
    accountStore.fetch();
    bookTagStore.init();
    muteStore.init();
    // 初始化图片缓存管理器，设置默认缓存大小为240MB
    imageCacheManager.initialize();
    await _initDownloadStore(); // 确保在 userSetting.init 之后执行
    // 预加载标签数据，确保详情页能正确显示标签状态（收藏、自定义翻译等）
    tagManagerStore.loadTags();
  }

  Widget build(BuildContext context) {
    return _buildMaterial(context);
  }

  Widget _buildMaterial(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
      ),
    );
    final botToastBuilder = BotToastInit();
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return Observer(
          builder: (context) {
            ColorScheme lightColorScheme;
            ColorScheme darkColorScheme;
            if (userSetting.useDynamicColor &&
                lightDynamic != null &&
                darkDynamic != null) {
              lightColorScheme = lightDynamic.harmonized();
              darkColorScheme = darkDynamic.harmonized();
            } else {
              Color primary = userSetting.seedColor;
              lightColorScheme = ColorScheme.fromSeed(seedColor: primary);
              darkColorScheme = ColorScheme.fromSeed(
                seedColor: primary,
                brightness: Brightness.dark,
              );
            }
            final brightness =
                SchedulerBinding.instance.platformDispatcher.platformBrightness;
            if (userSetting.themeInitState != 1) {
              return MaterialApp(
                home: Container(
                  color:
                      brightness == Brightness.dark
                          ? Colors.black
                          : Colors.white,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            return MaterialApp(
              navigatorObservers: [BotToastNavigatorObserver(), routeObserver],
              locale: userSetting.locale,
              navigatorKey: globalNavigatorKey,
              scrollBehavior: MouseDragScrollBehavior(),
              home: Builder(
                builder: (context) {
                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: SystemUiOverlayStyle(
                      systemNavigationBarColor: Colors.transparent,
                      systemNavigationBarDividerColor: Colors.transparent,
                      statusBarColor: Colors.transparent,
                    ),
                    child: SplashPage(),
                  );
                },
              ),
              title: 'PixEz',
              builder: (context, child) {
                if (Platform.isIOS) child = _buildMaskBuilder(context, child);
                child = botToastBuilder(context, child);
                I18n.context = context;
                child = Stack(
                  alignment: Alignment.topLeft,
                  clipBehavior: Clip.none,
                  children: [
                    child,
                    Observer(
                      builder: (context) => userSetting.showNetworkSpeedBall
                            ? FloatingNetworkSpeedBall()
                            : const SizedBox(),
                    ),
                  ],
                );

                if (Platform.isWindows) {
                  return WindowFrame(child);
                }
                return child;
              },
              themeMode: userSetting.themeMode,
              theme: ThemeData.light().copyWith(
                primaryColor: lightColorScheme.primary,
                colorScheme: lightColorScheme,
                scaffoldBackgroundColor: lightColorScheme.surface,
                cardColor: lightColorScheme.surfaceContainer,
                chipTheme: ChipThemeData(
                  backgroundColor: lightColorScheme.surface,
                ),
                canvasColor: lightColorScheme.surfaceContainer,
                dialogTheme: DialogThemeData(
                  backgroundColor: lightColorScheme.surfaceContainer,
                ),
              ),
              darkTheme: ThemeData.dark().copyWith(
                scaffoldBackgroundColor:
                    userSetting.isAMOLED ? Colors.black : null,
                // tabBarTheme: TabBarTheme(dividerColor: Colors.transparent),
                tabBarTheme: TabBarThemeData(dividerColor: Colors.transparent),
                colorScheme: darkColorScheme,
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            );
          },
        );
      },
    );
  }

  _buildMaskBuilder(BuildContext context, Widget? widget) {
    if (userSetting.nsfwMask) {
      final needShowMask =
          (Platform.isAndroid
              ? (_appState == AppLifecycleState.paused ||
                  _appState == AppLifecycleState.paused)
              : _appState == AppLifecycleState.inactive);
      return Stack(
        children: [
          widget ?? Container(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child:
                needShowMask
                    ? Container(
                      color: Theme.of(context).canvasColor,
                      child: Center(child: Icon(Icons.privacy_tip_outlined)),
                    )
                    : null,
          ),
        ],
      );
    } else {
      return widget;
    }
  }
}

Future<void> initWindows(List<String> args) async {
  // 必须加上这一行。
  await windowManager.ensureInitialized();

  // 在 Windows 上提前加载窗口位置信息
  WindowPlacement? placement;
  if (Platform.isWindows) {
    placement = await WindowPlacement.loadFromFile();
  }

  WindowOptions windowOptions = WindowOptions(
    //skipTaskbar: false,
    // 设置初始窗口大小，避免窗口过小
    size: placement?.rect.size ?? const Size(1200, 800),
    // 设置最小窗口大小，防止窗口被调整得太小
    minimumSize: const Size(900, 600),
    titleBarStyle: TitleBarStyle.hidden,
    title: "PixEz",
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // 在 Windows 上先应用窗口位置和尺寸，再显示窗口
    if (Platform.isWindows && placement != null) {
      await placement.applyToWindow();
    }
    
    await windowManager.show();
    await windowManager.focus();
    
    if (Platform.isWindows) {
      WindowPlacement.loop();
    }
  });
}

class MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}
