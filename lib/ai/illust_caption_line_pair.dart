/// 插画简介中一行原文及其对应译文。
class IllustCaptionLinePair {
  final String source;
  final String translation;

  const IllustCaptionLinePair({
    required this.source,
    required this.translation,
  });

  /// 空白行只属于原文排版，不应再追加一行空白译文。
  bool get isSourceBlank => _visibleText(source).isEmpty;

  /// 无需翻译的内容会原样返回，此时不重复展示。
  bool get hasDistinctTranslation =>
      _visibleText(source) != _visibleText(translation);

  /// 根据 HTML 换行标签和文本换行符配对。
  ///
  /// 翻译请求会保护这些分隔符。旧缓存或异常响应若未能保留分隔符，退回
  /// 到整段显示，避免把错误的译文错配到其他原文行。
  static List<IllustCaptionLinePair> fromHtml(
    String source,
    String translation,
  ) {
    final sourceLines = _splitLines(source);
    final translatedLines = _splitLines(translation);
    if (sourceLines.length != translatedLines.length) {
      return [IllustCaptionLinePair(source: source, translation: translation)];
    }
    return List.generate(
      sourceLines.length,
      (index) => IllustCaptionLinePair(
        source: sourceLines[index],
        translation: translatedLines[index],
      ),
    );
  }

  static List<String> _splitLines(String html) {
    final matches = _lineSeparator.allMatches(html);
    if (matches.isEmpty) return [html];

    final lines = <String>[];
    var start = 0;
    for (final match in matches) {
      lines.add(html.substring(start, match.start));
      start = match.end;
    }
    lines.add(html.substring(start));
    return lines;
  }

  static final _lineSeparator = RegExp(
    r'<br\s*/?\s*>|\r\n|\r|\n',
    caseSensitive: false,
  );

  static final _htmlTag = RegExp(r'<[^>]*>');
  static final _whitespace = RegExp(r'\s+');

  static String _visibleText(String html) =>
      html.replaceAll(_htmlTag, '').replaceAll(_whitespace, ' ').trim();
}
