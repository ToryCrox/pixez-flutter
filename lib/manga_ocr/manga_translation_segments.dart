class MangaTranslationBatch {
  final Map<String, String> markers;
  final String sourceText;

  const MangaTranslationBatch({
    required this.markers,
    required this.sourceText,
  });

  factory MangaTranslationBatch.fromBlocks(Map<String, String> blocks) {
    final markers = <String, String>{
      for (final id in blocks.keys) id: '⟪PXEZ_MANGA_BLOCK_${markerId(id)}⟫',
    };
    return MangaTranslationBatch(
      markers: markers,
      sourceText: blocks.entries
          .map((entry) => '${markers[entry.key]}${entry.value}')
          .join('\n'),
    );
  }

  Map<String, String> restore(String translated) {
    final ordered = markers.entries.toList();
    final result = <String, String>{};
    for (var index = 0; index < ordered.length; index++) {
      final current = ordered[index];
      final start = translated.indexOf(current.value);
      if (start < 0) continue;
      final contentStart = start + current.value.length;
      var contentEnd = translated.length;
      for (var next = index + 1; next < ordered.length; next++) {
        final candidate = translated.indexOf(ordered[next].value, contentStart);
        if (candidate >= 0) {
          contentEnd = candidate;
          break;
        }
      }
      result[current.key] =
          translated.substring(contentStart, contentEnd).trim();
    }
    return result;
  }

  static String markerId(String value) {
    final sanitized = value.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
    return sanitized.substring(0, sanitized.length.clamp(0, 64));
  }
}
