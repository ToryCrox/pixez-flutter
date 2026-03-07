import 'dart:async';

import 'package:pixez/models/download_record.dart';

enum ResolutionFilterOp { none, gt, lt }

/// 作者图片筛选执行所需的上下文。
class AuthorImageFilterContext {
  final DownloadedAuthor author;
  final List<DownloadedIllust> illusts;
  final Map<int, List<DownloadedImage>> imagesByIllustId;

  const AuthorImageFilterContext({
    required this.author,
    required this.illusts,
    required this.imagesByIllustId,
  });
}

/// 筛选候选项：一条插画记录 + 一张图片记录。
class AuthorImageCandidate {
  final DownloadedIllust illust;
  final DownloadedImage image;

  const AuthorImageCandidate({required this.illust, required this.image});

  String get id => '${illust.illustId}_${image.part}';
}

/// 可扩展筛选条件接口。
/// 后续新增条件时，只需实现该接口并加入条件列表。
abstract class AuthorImageFilterCondition {
  const AuthorImageFilterCondition();

  FutureOr<List<AuthorImageCandidate>> apply(
    List<AuthorImageCandidate> candidates,
    AuthorImageFilterContext context,
  );
}

/// 条件：排除动图作品。
class ExcludeUgoiraCondition extends AuthorImageFilterCondition {
  const ExcludeUgoiraCondition();

  @override
  List<AuthorImageCandidate> apply(
    List<AuthorImageCandidate> candidates,
    AuthorImageFilterContext context,
  ) {
    return candidates.where((e) => !e.illust.isUgoira).toList();
  }
}

/// 条件：排除 .webp 图片。
class NonWebpCondition extends AuthorImageFilterCondition {
  const NonWebpCondition();

  @override
  List<AuthorImageCandidate> apply(
    List<AuthorImageCandidate> candidates,
    AuthorImageFilterContext context,
  ) {
    return candidates
        .where((e) => e.image.extension.toLowerCase() != '.webp')
        .toList();
  }
}

/// 条件：每个作品仅保留最后 N 张（按 part 升序后取尾部）。
class LastNPerIllustCondition extends AuthorImageFilterCondition {
  final int n;

  const LastNPerIllustCondition({required this.n});

  @override
  List<AuthorImageCandidate> apply(
    List<AuthorImageCandidate> candidates,
    AuthorImageFilterContext context,
  ) {
    if (n <= 0) return const [];

    final Map<int, List<AuthorImageCandidate>> grouped = {};
    for (final candidate in candidates) {
      grouped.putIfAbsent(candidate.illust.illustId, () => []).add(candidate);
    }

    final List<AuthorImageCandidate> result = [];
    for (final group in grouped.values) {
      group.sort((a, b) => a.image.part.compareTo(b.image.part));
      final start = group.length > n ? group.length - n : 0;
      result.addAll(group.sublist(start));
    }
    return result;
  }
}

/// 条件：每个作品仅保留最前 N 张（按 part 升序取头部）。
class FirstNPerIllustCondition extends AuthorImageFilterCondition {
  final int n;

  const FirstNPerIllustCondition({required this.n});

  @override
  List<AuthorImageCandidate> apply(
    List<AuthorImageCandidate> candidates,
    AuthorImageFilterContext context,
  ) {
    if (n <= 0) return const [];

    final Map<int, List<AuthorImageCandidate>> grouped = {};
    for (final candidate in candidates) {
      grouped.putIfAbsent(candidate.illust.illustId, () => []).add(candidate);
    }

    final List<AuthorImageCandidate> result = [];
    for (final group in grouped.values) {
      group.sort((a, b) => a.image.part.compareTo(b.image.part));
      final end = group.length > n ? n : group.length;
      result.addAll(group.sublist(0, end));
    }
    return result;
  }
}

/// 条件：按宽高分辨率过滤。
/// op 为 none 时不参与过滤；gt/lt 为严格大于/小于。
class ResolutionCondition extends AuthorImageFilterCondition {
  final ResolutionFilterOp widthOp;
  final int? widthValue;
  final ResolutionFilterOp heightOp;
  final int? heightValue;

  const ResolutionCondition({
    required this.widthOp,
    required this.widthValue,
    required this.heightOp,
    required this.heightValue,
  });

  @override
  List<AuthorImageCandidate> apply(
    List<AuthorImageCandidate> candidates,
    AuthorImageFilterContext context,
  ) {
    return candidates.where((candidate) {
      final w = candidate.image.width;
      final h = candidate.image.height;

      if (!_matchesSingleDimension(widthOp, widthValue, w)) {
        return false;
      }
      if (!_matchesSingleDimension(heightOp, heightValue, h)) {
        return false;
      }
      return true;
    }).toList();
  }

  bool _matchesSingleDimension(
    ResolutionFilterOp op,
    int? threshold,
    int? value,
  ) {
    if (op == ResolutionFilterOp.none || threshold == null || threshold <= 0) {
      return true;
    }
    if (value == null || value <= 0) {
      // 开启了该维度过滤时，未知宽高直接排除。
      return false;
    }
    if (op == ResolutionFilterOp.gt) {
      return value > threshold;
    }
    return value < threshold;
  }
}

/// 条件：按插画 ID 过滤。
class IllustIdCondition extends AuthorImageFilterCondition {
  final int? illustId;

  const IllustIdCondition({required this.illustId});

  @override
  List<AuthorImageCandidate> apply(
    List<AuthorImageCandidate> candidates,
    AuthorImageFilterContext context,
  ) {
    if (illustId == null || illustId == 0) return candidates;
    return candidates.where((e) => e.illust.illustId == illustId).toList();
  }
}

/// 条件执行器：按顺序执行条件链。
class AuthorImageFilterEngine {
  final List<AuthorImageFilterCondition> conditions;

  const AuthorImageFilterEngine({required this.conditions});

  Future<List<AuthorImageCandidate>> run(
    AuthorImageFilterContext context,
  ) async {
    List<AuthorImageCandidate> candidates = [];

    // 构建初始候选项，先过滤掉 part < 0（如动图合并标记）。
    for (final illust in context.illusts) {
      final images = context.imagesByIllustId[illust.illustId] ?? const [];
      for (final image in images) {
        if (image.part < 0) continue;
        candidates.add(AuthorImageCandidate(illust: illust, image: image));
      }
    }

    for (final condition in conditions) {
      candidates = await condition.apply(candidates, context);
    }

    return candidates;
  }

  /// 默认条件：排除动图 -> 排除 webp -> 每作品最后4张。
  factory AuthorImageFilterEngine.defaultEngine() {
    return const AuthorImageFilterEngine(
      conditions: [
        ExcludeUgoiraCondition(),
        NonWebpCondition(),
        LastNPerIllustCondition(n: 4),
      ],
    );
  }
}
