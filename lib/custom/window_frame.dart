import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/downloaded/downloaded_page.dart';
import 'package:pixez/page/hello/setting/setting_quality_page.dart';
import 'package:pixez/page/history/history_page.dart';
import 'package:pixez/page/task/job_page.dart';
import 'package:window_manager/window_manager.dart';

import '../page/downloaded/downloaded_authors_page.dart';

const _kTitleBarHeight = 36.0;

// Intent classes for keyboard shortcuts
class _GoBackIntent extends Intent {
  const _GoBackIntent();
}

class _ToggleMaximizeIntent extends Intent {
  const _ToggleMaximizeIntent();
}

final windowFrameController = WindowFrameController();

class WindowFrameController {
  bool useDarkTheme = false;

  bool isHideWindowFrame = false;

  VoidCallback update = () {};

  void setDarkTheme() {
    useDarkTheme = true;
    update();
  }

  void resetTheme() {
    useDarkTheme = false;
    update();
  }

  VoidCallback openSideBar = () {};

  void hideWindowFrame() {
    isHideWindowFrame = true;
    update();
  }

  void showWindowFrame() {
    isHideWindowFrame = false;
    update();
  }
}

class WindowFrame extends StatefulWidget {
  const WindowFrame(this.child, {super.key});

  final Widget child;

  @override
  State<WindowFrame> createState() => _WindowFrameState();
}

class _WindowFrameState extends State<WindowFrame> {
  @override
  void initState() {
    super.initState();
    windowFrameController.update = () {
      setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return widget.child;
    if (windowFrameController.isHideWindowFrame) return widget.child;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): const _GoBackIntent(),
        const SingleActivator(LogicalKeyboardKey.f11): const _ToggleMaximizeIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _GoBackIntent: CallbackAction<_GoBackIntent>(
            onInvoke: (_) {
              final navigator = Navigator.maybeOf(globalNavigatorKey.currentContext!);
              if (navigator != null && navigator.canPop()) {
                navigator.pop();
              }
              return null;
            },
          ),
          _ToggleMaximizeIntent: CallbackAction<_ToggleMaximizeIntent>(
            onInvoke: (_) async {
              if (await windowManager.isMaximized()) {
                windowManager.unmaximize();
              } else {
                windowManager.maximize();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: _kTitleBarHeight),
                  ),
                  child: widget.child,
                ),
              ),
              const _SideBar(),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  color: Colors.transparent,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      brightness:
                          windowFrameController.useDarkTheme ? Brightness.dark : null,
                    ),
                    child: Builder(builder: (context) {
                      return SizedBox(
                        height: _kTitleBarHeight,
                        child: Row(
                          children: [
                            if (!Platform.isMacOS)
                              buildMenuButton(windowFrameController, context)
                            else
                              const DragToMoveArea(
                                child: SizedBox(
                                  height: double.infinity,
                                  width: 16,
                                ),
                              ),
                            Expanded(
                              child: DragToMoveArea(
                                child: Text(
                                  'Pixez',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: (windowFrameController.useDarkTheme ||
                                            Theme.of(context).brightness ==
                                                Brightness.dark)
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                              ),
                            ),
                            if (!Platform.isMacOS)
                              const WindowButtons()
                            else
                              buildMenuButton(windowFrameController, context),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget buildMenuButton(
      WindowFrameController controller, BuildContext context) {
    return InkWell(
      onTap: () {
        controller.openSideBar();
      },
      child: SizedBox(
        width: 42,
        height: double.infinity,
        child: Center(
          child: CustomPaint(
            size: const Size(18, 20),
            painter: _MenuPainter(
                color: (controller.useDarkTheme ||
                        Theme.of(context).brightness == Brightness.dark)
                    ? Colors.white
                    : Colors.black),
          ),
        ),
      ),
    );
  }
}

class _MenuPainter extends CustomPainter {
  final Color color;

  _MenuPainter({this.color = Colors.black});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = getPaint(color);
    final path = Path()
      ..moveTo(0, size.height / 4)
      ..lineTo(size.width, size.height / 4)
      ..moveTo(0, size.height / 4 * 2)
      ..lineTo(size.width, size.height / 4 * 2)
      ..moveTo(0, size.height / 4 * 3)
      ..lineTo(size.width, size.height / 4 * 3);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SideBar extends StatefulWidget {
  const _SideBar();

  @override
  State<_SideBar> createState() => __SideBarState();
}

class __SideBarState extends State<_SideBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  void run() {
    if (_controller.isAnimating) return;
    if (_controller.isCompleted) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 160), value: 0);
    var controller = windowFrameController;
    controller.openSideBar = run;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: CurvedAnimation(
            parent: _controller, curve: Curves.fastEaseInToSlowEaseOut),
        builder: (context, child) {
          var value = _controller.value;
          return Stack(
            children: [
              Positioned.fill(
                  child: GestureDetector(
                onTap: run,
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color:
                      value == 0 ? null : Colors.black.withOpacity(0.2 * value),
                ),
              )),
              Positioned(
                left:
                    !Platform.isMacOS ? (1 - _controller.value) * (-300) : null,
                right: Platform.isMacOS ? (_controller.value - 1) * 300 : null,
                top: 0,
                bottom: 0,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
                  elevation: 2,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                  child: SizedBox(
                    width: 200,
                    height: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.only(top: _kTitleBarHeight),
                      child: const SingleChildScrollView(
                        child: _SideBarBody(),
                      ),
                    ),
                  ),
                ),
              )
            ],
          );
        });
  }
}

class _SideBarBody extends StatelessWidget {
  const _SideBarBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        buildItem(
          icon: Icons.home,
          title: '回到首页',
          onTap: () {
            windowFrameController.openSideBar();
            Leader.popUtilHome(globalNavigatorKey.currentContext!);
          },
        ),
        buildItem(
          icon: Icons.settings,
          title: '偏好设置',
          onTap: () {
            windowFrameController.openSideBar();
            Navigator.of(globalNavigatorKey.currentContext!).push(
              MaterialPageRoute(builder: (context) => SettingQualityPage()),
            );
          },
        ),
        buildItem(
          icon: Icons.download,
          title: '下载任务',
          onTap: () {
            windowFrameController.openSideBar();
            Navigator.of(globalNavigatorKey.currentContext!).push(
              MaterialPageRoute(builder: (context) => JobPage()),
            );
          },
        ),
        buildItem(
          icon: Icons.download,
          title: '下载记录',
          onTap: () {
            windowFrameController.openSideBar();
            Navigator.of(globalNavigatorKey.currentContext!).push(
              MaterialPageRoute(builder: (context) => DownloadedPage()),
            );
          },
        ),
        buildItem(
          icon: Icons.download,
          title: '作者列表',
          onTap: () {
            windowFrameController.openSideBar();
            Navigator.of(globalNavigatorKey.currentContext!).push(
              MaterialPageRoute(builder: (context) => DownloadedAuthorsPage()),
            );
          },
        ),
      ],
    );
  }

  Widget buildItem(
      {required IconData icon,
      required String title,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 16),
              Text(title, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

class WindowButtons extends StatefulWidget {
  const WindowButtons({super.key});

  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> with WindowListener {
  bool isMaximized = false;

  @override
  void initState() {
    windowManager.addListener(this);
    windowManager.isMaximized().then((value) {
      if (value) {
        setState(() {
          isMaximized = true;
        });
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() {
      isMaximized = true;
    });
    super.onWindowMaximize();
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      isMaximized = false;
    });
    super.onWindowUnmaximize();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? Colors.white : Colors.black;
    final hoverColor = dark ? Colors.white30 : Colors.black12;

    return SizedBox(
      width: 138,
      height: _kTitleBarHeight,
      child: Row(
        children: [
          WindowButton(
            icon: MinimizeIcon(color: color),
            hoverColor: hoverColor,
            onPressed: () async {
              bool isMinimized = await windowManager.isMinimized();
              if (isMinimized) {
                windowManager.restore();
              } else {
                windowManager.minimize();
              }
            },
          ),
          if (isMaximized)
            WindowButton(
              icon: RestoreIcon(
                color: color,
              ),
              hoverColor: hoverColor,
              onPressed: () {
                windowManager.unmaximize();
              },
            )
          else
            WindowButton(
              icon: MaximizeIcon(
                color: color,
              ),
              hoverColor: hoverColor,
              onPressed: () {
                windowManager.maximize();
              },
            ),
          WindowButton(
            icon: CloseIcon(
              color: color,
            ),
            hoverIcon: CloseIcon(
              color: !dark ? Colors.white : Colors.black,
            ),
            hoverColor: Colors.red,
            onPressed: () {
              showDialog(
                  context: globalNavigatorKey.currentContext!,
                  builder: (context) {
                    bool isCheck = false;
                    return AlertDialog(
                      title: Text('是否退出程序?'),
                      content: StatefulBuilder(builder: (context, setState) {
                        return Row(
                          children: [
                            Checkbox(
                              value: isCheck,
                              onChanged: (value) {
                                setState(() {
                                  isCheck = value!;
                                });
                              },
                            ),
                            Text('不再提示'),
                          ],
                        );
                      }),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text('否'),
                        ),
                        TextButton(
                          onPressed: () {
                            windowManager.close();
                          },
                          child: Text('是'),
                        ),
                      ],
                    );
                  });
            },
          )
        ],
      ),
    );
  }
}

class WindowButton extends StatefulWidget {
  const WindowButton(
      {required this.icon,
      required this.onPressed,
      required this.hoverColor,
      this.hoverIcon,
      super.key});

  final Widget icon;

  final void Function() onPressed;

  final Color hoverColor;

  final Widget? hoverIcon;

  @override
  State<WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<WindowButton> {
  bool isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (event) => setState(() {
        isHovering = true;
      }),
      onExit: (event) => setState(() {
        isHovering = false;
      }),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: double.infinity,
          decoration:
              BoxDecoration(color: isHovering ? widget.hoverColor : null),
          child: isHovering ? widget.hoverIcon ?? widget.icon : widget.icon,
        ),
      ),
    );
  }
}

/// Close
class CloseIcon extends StatelessWidget {
  final Color color;

  const CloseIcon({super.key, required this.color});

  @override
  Widget build(BuildContext context) => _AlignedPaint(_ClosePainter(color));
}

class _ClosePainter extends _IconPainter {
  _ClosePainter(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    Paint p = getPaint(color, true);
    canvas.drawLine(const Offset(0, 0), Offset(size.width, size.height), p);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), p);
  }
}

/// Maximize
class MaximizeIcon extends StatelessWidget {
  final Color color;

  const MaximizeIcon({super.key, required this.color});

  @override
  Widget build(BuildContext context) => _AlignedPaint(_MaximizePainter(color));
}

class _MaximizePainter extends _IconPainter {
  _MaximizePainter(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    Paint p = getPaint(color);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width - 1, size.height - 1), p);
  }
}

/// Restore
class RestoreIcon extends StatelessWidget {
  final Color color;

  const RestoreIcon({
    super.key,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => _AlignedPaint(_RestorePainter(color));
}

class _RestorePainter extends _IconPainter {
  _RestorePainter(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    Paint p = getPaint(color);
    canvas.drawRect(Rect.fromLTRB(0, 2, size.width - 2, size.height), p);
    canvas.drawLine(const Offset(2, 2), const Offset(2, 0), p);
    canvas.drawLine(const Offset(2, 0), Offset(size.width, 0), p);
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width, size.height - 2), p);
    canvas.drawLine(Offset(size.width, size.height - 2),
        Offset(size.width - 2, size.height - 2), p);
  }
}

/// Minimize
class MinimizeIcon extends StatelessWidget {
  final Color color;

  const MinimizeIcon({super.key, required this.color});

  @override
  Widget build(BuildContext context) => _AlignedPaint(_MinimizePainter(color));
}

class _MinimizePainter extends _IconPainter {
  _MinimizePainter(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    Paint p = getPaint(color);
    canvas.drawLine(
        Offset(0, size.height / 2), Offset(size.width, size.height / 2), p);
  }
}

/// Helpers
abstract class _IconPainter extends CustomPainter {
  _IconPainter(this.color);

  final Color color;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AlignedPaint extends StatelessWidget {
  const _AlignedPaint(this.painter);

  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    return Align(
        alignment: Alignment.center,
        child: CustomPaint(size: const Size(10, 10), painter: painter));
  }
}

Paint getPaint(Color color, [bool isAntiAlias = false]) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..isAntiAlias = isAntiAlias
  ..strokeWidth = 1;

class WindowPlacement {
  final Rect rect;

  final bool isMaximized;

  const WindowPlacement(this.rect, this.isMaximized);

  Map<String, dynamic> toMap() {
    return {
      'rect': {
        'left': rect.left,
        'top': rect.top,
        'right': rect.right,
        'bottom': rect.bottom,
      },
      'isMaximized': isMaximized,
    };
  }

  factory WindowPlacement.fromMap(Map<String, dynamic> map) {
    return WindowPlacement(
      Rect.fromLTRB(map['rect']['left'], map['rect']['top'],
          map['rect']['right'], map['rect']['bottom']),
      map['isMaximized'],
    );
  }

  Future<void> applyToWindow() async {
    await windowManager.setBounds(rect);

    if (!validate(rect)) {
      await windowManager.center();
    }

    if (isMaximized) {
      await windowManager.maximize();
    }
  }

  Future<void> writeToFile() async {
    print("writeToFile ${toMap()}");
    Prefer.setString('window_frame', jsonEncode(toMap()));
  }

  static Future<WindowPlacement> loadFromFile() async {
    try {
      final jsonString = Prefer.getString('window_frame');
      if (jsonString == null || jsonString.isEmpty) {
        return defaultPlacement;
      }
      var json = jsonDecode(jsonString);
      print("loadFromFile $json");
      return WindowPlacement.fromMap(json);
    } catch (e) {
      print("loadFromFile error $e");
      return defaultPlacement;
    }
  }

  // static Future<WindowPlacement> loadFromFile() async {
  //   try {
  //     // var file = File("${App.dataPath}/window_placement");
  //     // if (!file.existsSync()) {
  //     //   return defaultPlacement;
  //     // }
  //     final jsonString = PrefsHelper.getString('window_frame');
  //     //var json = jsonDecode(await file.readAsString());
  //     if (jsonString.isEmpty) {
  //       return defaultPlacement;
  //     }
  //     var json = jsonDecode(jsonString);
  //     var rect =
  //         Rect.fromLTWH(json['x'], json['y'], json['width'], json['height']);
  //     return WindowPlacement(rect, json['isMaximized']);
  //   } catch (e) {
  //     return defaultPlacement;
  //   }
  // }

  static Future<WindowPlacement> get current async {
    var rect = await windowManager.getBounds();
    var isMaximized = await windowManager.isMaximized();
    return WindowPlacement(rect, isMaximized);
  }

  static const defaultPlacement =
      WindowPlacement(Rect.fromLTWH(10, 10, 900, 600), false);

  static WindowPlacement cache = defaultPlacement;

  static Timer? timer;

  static void loop() async {
    timer ??= Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      var placement = await WindowPlacement.current;
      if (!validate(placement.rect)) {
        return;
      }
      if (placement.rect != cache.rect ||
          placement.isMaximized != cache.isMaximized) {
        cache = placement;
        await placement.writeToFile();
      }
    });
  }

  static bool validate(Rect rect) {
    return rect.topLeft.dx >= 0 && rect.topLeft.dy >= 0;
  }
}

class VirtualWindowFrame extends StatefulWidget {
  const VirtualWindowFrame({
    super.key,
    required this.child,
  });

  /// The [child] contained by the VirtualWindowFrame.
  final Widget child;

  @override
  State<StatefulWidget> createState() => _VirtualWindowFrameState();
}

class _VirtualWindowFrameState extends State<VirtualWindowFrame>
    with WindowListener {
  bool _isFocused = true;
  bool _isMaximized = false;
  bool _isFullScreen = false;

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Widget _buildVirtualWindowFrame(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: (_isMaximized || _isFullScreen) ? 0 : 1,
        ),
        boxShadow: <BoxShadow>[
          if (!_isMaximized && !_isFullScreen)
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              offset: Offset(0.0, _isFocused ? 4 : 2),
              blurRadius: 6,
            )
        ],
      ),
      child: widget.child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DragToResizeArea(
      enableResizeEdges: (_isMaximized || _isFullScreen) ? [] : null,
      child: _buildVirtualWindowFrame(context),
    );
  }

  @override
  void onWindowFocus() {
    setState(() {
      _isFocused = true;
    });
  }

  @override
  void onWindowBlur() {
    setState(() {
      _isFocused = false;
    });
  }

  @override
  void onWindowMaximize() {
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      _isMaximized = false;
    });
  }

  @override
  void onWindowEnterFullScreen() {
    setState(() {
      _isFullScreen = true;
    });
  }

  @override
  void onWindowLeaveFullScreen() {
    setState(() {
      _isFullScreen = false;
    });
  }
}

// ignore: non_constant_identifier_names
TransitionBuilder VirtualWindowFrameInit() {
  return (_, Widget? child) {
    return VirtualWindowFrame(
      child: child!,
    );
  };
}
