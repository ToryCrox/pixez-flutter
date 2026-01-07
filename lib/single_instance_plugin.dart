import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/main.dart';
import 'package:pixez/custom/log.dart';

class SingleInstancePlugin {
  static final platform = const EventChannel("pixez/single_instance");
  static bool _isInitialized = false;

  // 这个函数是确保同一时间有且只有一个Pixez实例存在的
  //
  // 它需要将其他实例的命令行参数转发给第一个实例
  // 然后结束自己的进程
  static void initialize({Function()? callback}) {
    if (_isInitialized) throw Exception('ReInitialized');
    platform.receiveBroadcastStream().listen(
      (event) {
        final args = event.toString().split('\n');
        Log.d('Received args from another instance: $args');
        argsParser(args, callback: callback);
      },
    );
    _isInitialized = true;
  }

  /// 解析命令行参数字符串
  static void argsParser(List<String> args, {Function()? callback}) async {
    if (args.length < 1) return;

    final uri = Uri.tryParse(args[0]);
    if (uri != null) {
      Log.d('argsParser(): Valid URI: "$uri"');

      if (callback != null) callback();
      Leader.pushWithUri(routeObserver.navigator!.context, uri);
    }
  }
}
