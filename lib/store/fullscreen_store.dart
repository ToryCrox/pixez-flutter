import 'dart:io';
import 'package:mobx/mobx.dart';
import 'package:window_manager/window_manager.dart';
import 'package:pixez/custom/log.dart';

part 'fullscreen_store.g.dart';

class FullScreenStore = _FullScreenStoreBase with _$FullScreenStore;

abstract class _FullScreenStoreBase with Store {
  @observable
  bool fullscreen = false;

  final bool canFullScreen =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @action
  Future<void> toggle() async {
    await setFullScreen(!fullscreen);
  }

  @action
  Future<void> setFullScreen(bool value) async {
    if (!canFullScreen) return;
    try {
      await windowManager.setFullScreen(value);
      fullscreen = value;
    } catch (e) {
      Log.e("设置全屏失败: $e");
    }
  }
}
