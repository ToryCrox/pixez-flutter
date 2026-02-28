/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful, but WITHOUT ANY
 *  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 *  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along with
 *  this program. If not, see <http://www.gnu.org/licenses/>.
 */



import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/picker/colorpicker.dart';
import 'package:pixez/component/picker/utils.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';

class ColorPickPage extends StatefulWidget {
  final Color initialColor;

  ColorPickPage({required this.initialColor});

  @override
  _ColorPickPageState createState() => _ColorPickPageState();
}

class _ColorPickPageState extends State<ColorPickPage> {
  late Color pickerColor;
  @override
  void initState() {
    pickerColor = widget.initialColor;
    super.initState();
  }



  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(I18n.of(context).pick_a_color),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorPicker(
              enableAlpha: false,
              pickerColor: pickerColor,
              onColorChanged: (Color color) {
                setState(() {
                  pickerColor = color;
                });
                _applyColor(color);
              },
              pickerAreaHeightPercent: 0.8,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in Colors.primaries)
                  InkWell(
                    onTap: () {
                      setState(() {
                        pickerColor = color;
                      });
                      _applyColor(color);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: pickerColor.value == color.value
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: pickerColor.value == color.value
                            ? [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: pickerColor.value == color.value
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 24)
                          : null,
                    ),
                  )
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.edit),
          tooltip: "16 radix RGB",
          onPressed: () async {
            final TextEditingController textEditingController =
                TextEditingController(
                    text: pickerColor.toHexString(
                        includeHashSign: false,
                        enableAlpha: false,
                        toUpperCase: false));

            String? result = await showDialog<String>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text("16 radix RGB"),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    content: TextField(
                      controller: textEditingController,
                      maxLength: 6,
                      decoration: const InputDecoration(
                          prefix: Text("color(0xff"), suffix: Text(")")),
                    ),
                    actions: <Widget>[
                      TextButton(
                          onPressed: () {
                            final result = textEditingController.text
                                .trim()
                                .toLowerCase();
                            if (result.length != 6) {
                              return;
                            }
                            Navigator.of(context)
                                .pop("color(0xff${result})");
                          },
                          child: Text(I18n.of(context).ok)),
                      TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text(I18n.of(context).cancel)),
                    ],
                  );
                });
            if (result != null) {
              Color color = _stringToColor(result); //迅速throw出来
              if (!context.mounted) return;
              setState(() {
                pickerColor = color;
              });
              _applyColor(color);
            }
          },
        ),
        TextButton(
          onPressed: () {
            _applyColor(widget.initialColor);
            Navigator.of(context).pop();
          },
          child: const Text("还原"),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(pickerColor);
          },
          child: Text(I18n.of(context).ok),
        ),
      ],
    );
  }

  void _applyColor(Color color) {
    userSetting.setThemeData(color);
    topStore.setTop("main");
  }

  Color _stringToColor(String colorString) {
    String valueString =
        colorString.split('(0x')[1].split(')')[0]; // kind of hacky..
    int value = int.parse(valueString, radix: 16);
    Color otherColor = new Color(value);
    return otherColor;
  }
}

class ThemePage extends StatefulWidget {
  @override
  _ThemePageState createState() => _ThemePageState();
}

class _ThemePageState extends State<ThemePage> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      return Scaffold(
        appBar: AppBar(
            title: Text(I18n.of(context).theme),
            bottom: TabBar(
                controller: TabController(
                  length: 3,
                  initialIndex: ThemeMode.values.indexOf(userSetting.themeMode),
                  vsync: this,
                ),
                onTap: (i) {
                  userSetting.setThemeMode(i);
                },
                tabs: [
                  Tab(
                    text: I18n.of(context).system,
                  ),
                  Tab(
                    text: I18n.of(context).light,
                  ),
                  Tab(text: I18n.of(context).dark)
                ])),
        body: Observer(builder: (_) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Card(
                    child: SwitchListTile(
                  value: userSetting.isAMOLED,
                  onChanged: (v) => userSetting.setIsAMOLED(v),
                  title: Text("AMOLED"),
                )),
              ),
              SliverToBoxAdapter(
                child: Card(
                    child: SwitchListTile(
                  value: userSetting.useDynamicColor,
                  onChanged: (v) async {
                    await userSetting.setUseDynamicColor(v);
                    topStore.setTop("main");
                  },
                  title: Text(I18n.of(context).dynamic_color),
                )),
              ),
              if (!userSetting.useDynamicColor)
                SliverToBoxAdapter(
                  child: Card(
                    child: ListTile(
                      leading: SizedBox(
                        width: 30,
                        height: 30,
                        child: Container(
                          decoration: BoxDecoration(
                              color: userSetting.seedColor,
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      title: Text(I18n.of(context).seed_color),
                      onTap: () {
                        _pickColor();
                      },
                    ),
                  ),
                )
            ],
          );
        }),
      );
    });
  }

  _pickColor() async {
    Color? result = await showDialog<Color>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => ColorPickPage(initialColor: userSetting.seedColor),
    );
    if (result == null) {
      // 预防返回键等意外退出没有走到 pop(pickerColor) 导致主题无法恢复
      await userSetting.setThemeData(userSetting.seedColor);
      topStore.setTop("main");
    }
  }
}
