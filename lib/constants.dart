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

class Constants {
  static const String no_h = 'assets/images/h_long.jpg';
  static String tagName = "0.9.75";
  static const isGooglePlay = bool.fromEnvironment(
    "IS_GOOGLEPLAY",
    defaultValue: false,
  );
  static int type = 0;
  static String? code_verifier = null;

  /// 为true表示使用FluentUI 否则为false,不应作为Desktop的判断
  static final bool isFluent = false; // Platform.isWindows;

  /// 为true表示使用新下载器，否则为false

  static const String qualitySquareMedium = 'square_medium';
  static const String qualityMedium = 'medium';
  static const String qualityLarge = 'large';
  static const String qualityOriginal = 'origin';

  static const int qualityLevelMedium = 0;
  static const int qualityLevelLarge = 1;
  static const int qualityLevelOriginal = 2;

  static const String ugoira = 'ugoira';
  static const String filterNoUgoira = 'no_ugoira';
  static const String filterOnlyUgoira = 'only_ugoira';
}
