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
import 'package:flutter_highlight/flutter_highlight.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final useDarkTheme = isDark || isDarkMode;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: HighlightView(
        json,
        language: 'json',
        theme: useDarkTheme ? atomOneDarkTheme : atomOneLightTheme,
        padding: padding,
        textStyle: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize,
        ),
      ),
    );
  }
}
