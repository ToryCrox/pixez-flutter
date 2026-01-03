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
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/ban_tag.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/novel_recom_response.dart';

extension HostExts on Uri {
  Uri toTureUri() {
    if (userSetting.disableBypassSni) {
      return this;
    } else {
      if (userSetting.pictureSource != ImageHost) {
        try {
          if (userSetting.pictureSource!.contains('/')) {
            final preHost = this.host;
            return Uri.parse(
                '${this.toString().replaceAll(preHost, userSetting.pictureSource!)}');
          }
          return this.replace(host: userSetting.pictureSource);
        } catch (e) {}
      }
      if (this.host == ImageHost) {
        return this.replace(host: splashStore.host);
      } else if (this.host == ImageSHost) {
        return this.replace(host: splashStore.host);
      }
    }
    return this;
  }
}

extension TimeExts on String {
  String toShortTime() {
    try {
      var formatter = new DateFormat('yyyy-MM-dd HH:mm');
      return formatter.format(DateTime.parse(this).toLocal());
    } catch (e) {
      return this;
    }
  }

  String toShortDate() {
    try {
      var formatter = new DateFormat('yyyy-MM-dd');
      return formatter.format(DateTime.parse(this).toLocal());
    } catch (e) {
      return this;
    }
  }

  String toTranslateText() {
    return this
        .replaceAll("</br>", "\n")
        .replaceAll("<br />", "\n")
        .replaceAll("<strong>", "")
        .replaceAll("</strong>", "")
        .replaceAll("<p>", "")
        .replaceAll("</p>", "");
  }

  // String toTrueUrl() {
  //   if (userSetting.disableBypassSni || this.contains("novel")) {
  //     return this;
  //   } else {
  //     if (userSetting.pictureSource != ImageHost) {
  //       try {
  //         if (userSetting.pictureSource!.contains('/')) {
  //           Uri preUri = Uri.parse(this);
  //           final preHost = preUri.host;
  //           return this.replaceAll(preHost, userSetting.pictureSource!);
  //         }
  //         return Uri.parse(this)
  //             .replace(host: userSetting.pictureSource)
  //             .toString();
  //       } catch (e) {}
  //     }
  //     if (this.contains(ImageHost)) {
  //       return this.replaceFirst(ImageHost, splashStore.host);
  //     }
  //     if (this.contains(ImageSHost)) {
  //       return this.replaceFirst(ImageSHost, splashStore.host);
  //     }
  //   }
  //   return this;
  // }

  String toLegal() {
    String result = this
        .replaceAll("/", "")
        .replaceAll("\\", "")
        .replaceAll(":", "")
        .replaceAll("*", "")
        .replaceAll("?", "")
        .replaceAll(">", "")
        .replaceAll("|", "")
        .replaceAll("<", "")
        .replaceAll("\"", "")
        .replaceAll("\n", "")
        .replaceAll("\r", "")
        .replaceAll("\t", "");
    
    // Windows平台需要移除控制字符
    if (Platform.isWindows) {
      // 移除控制字符
      result = result.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    }
    
    // 移除尾随空格和点（Windows不允许文件名以空格或点结尾）
    result = result.trim();
    while (result.endsWith('.') || result.endsWith(' ')) {
      result = result.substring(0, result.length - 1).trim();
    }
    
    // 移除Windows保留名称（CON, PRN, AUX, NUL, COM1-9, LPT1-9等）
    final reservedNames = ['CON', 'PRN', 'AUX', 'NUL'];
    for (int i = 1; i <= 9; i++) {
      reservedNames.add('COM$i');
      reservedNames.add('LPT$i');
    }
    if (reservedNames.contains(result.toUpperCase())) {
      result = '_$result';
    }
    
    // 如果结果为空，使用默认名称
    if (result.isEmpty) {
      result = 'unnamed';
    }
    
    return result;
  }
}

extension NovelExts on Novel {
  bool hateByUser() {
    for (var t in muteStore.banTags) {
      for (var f in this.tags) {
        if (t.isRegexMatch(f.name)) {
          return true;
        }
      }
      final allText = tags.map((e) => '#${e.name}').join('');
      if (t.isRegexMatch(allText)) {
        return true;
      }
    }
    for (var j in muteStore.banUserIds) {
      if (j.userId == this.user.id.toString()) {
        return true;
      }
    }
    for (var i in muteStore.banillusts)
      if (this.id == int.parse(i.illustId)) {
        return true;
      }
    return false;
  }
}

extension FileSizeExts on int {
  /// 格式化文件大小为人类可读的格式 (B, KB, MB, GB)
  String formatFileSize() {
    if (this < 1024) {
      return '${this}B';
    } else if (this < 1024 * 1024) {
      return '${(this / 1024).toStringAsFixed(1)}KB';
    } else if (this < 1024 * 1024 * 1024) {
      return '${(this / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(this / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }
}

extension IllustExts on Illusts {
  String get commentCountText =>
      totalComments == null ? '' : '($totalComments)';
  bool hIsNotAllow() {
    if (userSetting.hIsNotAllow) {
      if (tags.any((tag) => tag.name.startsWith('R-18'))) {
        return true;
      }
    }
    return false;
  }

  bool hateByUser({bool ai = false, bool includeR18Setting = false}) {
    if (includeR18Setting) {
      if (userSetting.hIsNotAllow) {
        for (final tag in tags) {
          if (tag.name.startsWith('R-18')) return true;
        }
      }
    }
    if (muteStore.banAIIllust && illustAIType == 2 && !ai) {
      return true;
    }
    for (var t in muteStore.banTags) {
      for (var f in this.tags) {
        if (t.isRegexMatch(f.name)) {
          return true;
        }
      }
      final allText = tags.map((e) => '#${e.name}').join('');
      if (t.isRegexMatch(allText)) {
        return true;
      }
    }
    for (var j in muteStore.banUserIds) {
      if (j.userId == this.user.id.toString()) {
        return true;
      }
    }
    for (var i in muteStore.banillusts)
      if (this.id == int.parse(i.illustId)) {
        return true;
      }
    if (accountStore.now?.mailAddress
            .toLowerCase()
            .contains("pxezfeedback@outlook.com") ==
        true) {
      if (sanityLevel > 4) return true;
    }
    return false;
  }
}
