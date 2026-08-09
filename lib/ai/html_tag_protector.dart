import 'package:pixez/ai/ai_client.dart';

class HtmlTagProtection {
  final String protectedText;
  final List<String> _tokens;
  final Map<String, String> _originalTags;

  const HtmlTagProtection(this.protectedText, this._tokens, this._originalTags);

  factory HtmlTagProtection.protect(String html) {
    final originalTags = <String, String>{};
    final tokens = <String>[];
    var index = 0;
    final protectedText = html.replaceAllMapped(
      RegExp(r'<!--[\s\S]*?-->|</?[A-Za-z][^>]*>'),
      (match) {
        final token = '⟪PXEZ_HTML_TAG_${index.toString().padLeft(4, '0')}⟫';
        originalTags[token] = match.group(0)!;
        tokens.add(token);
        index++;
        return token;
      },
    );
    return HtmlTagProtection(protectedText, tokens, originalTags);
  }

  String restore(String translated) {
    final found =
        RegExp(
          r'⟪PXEZ_HTML_TAG_\d{4}⟫',
        ).allMatches(translated).map((match) => match.group(0)!).toList();
    if (!_sameSequence(found, _tokens) ||
        RegExp(r'<!--[\s\S]*?-->|</?[A-Za-z][^>]*>').hasMatch(translated)) {
      throw const AiRequestException('AI 未能完整保留介绍中的 HTML 标签，请重新翻译');
    }
    var result = translated;
    for (final token in _tokens) {
      result = result.replaceAll(token, _originalTags[token]!);
    }
    return result;
  }

  bool _sameSequence(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
