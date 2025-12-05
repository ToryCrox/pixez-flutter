import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pixez/document_plugin.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/hello/setting/save_format_page.dart';

class WindowsPlatformPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    if (Platform.isWindows) return _WindowsPlatformPageState();
    throw UnimplementedError();
  }
}

class _WindowsPlatformPageState extends State<WindowsPlatformPage> {
  String path = "";

  @override
  void initState() {
    super.initState();
    initVoid();
  }

  initVoid() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      version = packageInfo.version;
    });

    String path = (await DocumentPlugin.getPath())!;
    if (mounted) {
      setState(() {
        this.path = path;
      });
    }
  }

  String version = "";
  bool singleFolder = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: ListTile(
        title: Text("Platform Setting"),
        subtitle: Text(
          "For Windows",
          style: TextStyle(color: Colors.blue),
        ),
      ),
      content: Observer(builder: (_) {
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.folder),
                title: Text(I18n.of(context).save_path),
                subtitle: Text(path),
                onTap: () async {
                  await DocumentPlugin.choiceFolder();
                  final path = await DocumentPlugin.getPath();
                  if (mounted) {
                    setState(() {
                      this.path = path!;
                    });
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.format_align_left),
                title: Text(I18n.of(context).save_format),
                subtitle: Text(userSetting.fileNameEval == 1
                    ? "Eval"
                    : userSetting.format ?? ""),
                onTap: () async {
                  if (userSetting.fileNameEval == 1) {
                    // TODO: 没有实现 JSEvalPlugin 所以这里不能用
                    // await showDialog(
                    //   context: context,
                    //   builder: (context) => SaveEvalPage(),
                    // );
                  } else {
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => SaveFormatPage()),
                    );
                    if (result is String) {
                      userSetting.setFormat(result);
                    }
                  }
                },
              ),
              Observer(
                builder: (context) {
                  return SwitchListTile(
                    secondary: Icon(Icons.folder_shared),
                    title: Text(I18n.of(context).separate_folder),
                    subtitle: Text(I18n.of(context).separate_folder_message),
                    value: userSetting.singleFolder,
                    onChanged: (bool value) async {
                      if (value) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('可能会造成保存等待时间过长')));
                      }
                      await userSetting.setSingleFolder(value);
                    },
                  );
                },
              ),
              Observer(
                builder: (context) {
                  return SwitchListTile(
                    secondary: Icon(Icons.folder_open),
                    title: Text("Sanity Single Folder"),
                    value: userSetting.overSanityLevelFolder,
                    onChanged: (bool value) async {
                      await userSetting.setOverSanityLevelFolder(value);
                    },
                  );
                },
              ),
            ],
          ),
        );
      }),
      actions: [
        TextButton(
          child: Text(I18n.of(context).ok),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
