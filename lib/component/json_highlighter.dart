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

import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight, Node;
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';

/// JSON 语法高亮组件
class JsonHighlighter extends StatelessWidget {
  /// JSON 数据（已格式化）
  final String json;

  /// 字体大小
  final double fontSize;

  /// 内边距
  final EdgeInsets padding;

  /// 是否使用深色主题
  final bool isDark;

  const JsonHighlighter({
    Key? key,
    required this.json,
    this.fontSize = 11,
    this.padding = const EdgeInsets.all(8),
    this.isDark = false,
  }) : super(key: key);

  List<TextSpan> _convert(List<Node> nodes, Map<String, TextStyle> theme) {
    List<TextSpan> spans = [];
    var currentSpans = spans;
    List<List<TextSpan>> stack = [];

    void _traverse(Node node) {
      if (node.value != null) {
        currentSpans.add(
          node.className == null
              ? TextSpan(text: node.value)
              : TextSpan(text: node.value, style: theme[node.className!]),
        );
      } else if (node.children != null) {
        List<TextSpan> tmp = [];
        currentSpans.add(
          TextSpan(children: tmp, style: theme[node.className!]),
        );
        stack.add(currentSpans);
        currentSpans = tmp;

        for (var n in node.children!) {
          _traverse(n);
          if (n == node.children!.last) {
            currentSpans = stack.isEmpty ? spans : stack.removeLast();
          }
        }
      }
    }

    for (var node in nodes) {
      _traverse(node);
    }

    return spans;
  }

  static const _rootKey = 'root';
  static const _defaultFontColor = Color(0xff000000);
  static const _defaultBackgroundColor = Color(0xffffffff);
  static const _defaultFontFamily = 'monospace';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final useDarkTheme = isDark || isDarkMode;
    final themeData = useDarkTheme ? atomOneDarkTheme : atomOneLightTheme;

    var textStyle = TextStyle(
      fontFamily: _defaultFontFamily,
      color: themeData[_rootKey]?.color ?? _defaultFontColor,
      fontSize: fontSize,
    );

    final nodes = highlight.parse(json, language: 'json').nodes!;
    final spans = _convert(nodes, themeData);

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: themeData[_rootKey]?.backgroundColor ?? _defaultBackgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText.rich(TextSpan(style: textStyle, children: spans)),
    );
  }
}
