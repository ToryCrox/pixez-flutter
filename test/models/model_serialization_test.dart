import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/custom/pixiv_url_util.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/models/bookmark.dart' as bookmark;
import 'package:pixez/models/comment_response.dart' as comment;
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/illust.dart' as illust;
import 'package:pixez/models/illust_series_detail.dart' as illust_series;
import 'package:pixez/models/novel_recom_response.dart' as novel;
import 'package:pixez/models/novel_web_response.dart' as novel_web;
import 'package:pixez/models/onezero_response.dart';
import 'package:pixez/models/original_image.dart';
import 'package:pixez/models/spotlight_response.dart';
import 'package:pixez/models/tags.dart' as tags;
import 'package:pixez/models/ugoira_metadata_response.dart' as ugoira;
import 'package:pixez/models/user_detail.dart' as user_detail;

void main() {
  group('手写模型序列化', () {
    test('TypeUtil 保留原有 List/Map 直接返回语义', () {
      final strings = <String>['one'];
      final ints = <int>[1];
      final dynamicValues = <dynamic>[{'value': 1}];
      final map = <String, dynamic>{'value': 1};

      expect(identical(TypeUtil.parseStringList(strings), strings), isTrue);
      expect(identical(TypeUtil.parseIntList(ints), ints), isTrue);
      expect(
        identical(TypeUtil.parseDynamicList(dynamicValues), dynamicValues),
        isTrue,
      );
      expect(identical(TypeUtil.parseMap(map), map), isTrue);
    });

    test('插画及嵌套用户、标签、动图字段可以 round-trip', () {
      final source = <String, dynamic>{
        'id': 123,
        'title': '测试插画',
        'type': 'ugoira',
        'image_urls': {
          'square_medium': 'https://i.pximg.net/square.jpg',
          'medium': 'https://i.pximg.net/medium.jpg',
          'large': 'https://i.pximg.net/large.jpg',
        },
        'caption': 'caption',
        'restrict': 0,
        'user': {
          'id': 88,
          'name': '画师',
          'account': 'artist',
          'profile_image_urls': {'medium': 'https://i.pximg.net/user.jpg'},
          'comment': 'hello',
          'is_followed': true,
        },
        'tags': [
          {'name': 'tag', 'translated_name': '标签'},
        ],
        'tools': ['clip studio'],
        'create_date': '2024-01-02T03:04:05Z',
        'page_count': 1,
        'width': 1200,
        'height': 800,
        'sanity_level': 6,
        'x_restrict': 1,
        'meta_single_page': {
          'original_image_url': 'https://i.pximg.net/original.jpg',
        },
        'meta_pages': [
          {
            'image_urls': {
              'square_medium': 'square',
              'medium': 'medium',
              'large': 'large',
              'original': 'original',
            },
          },
        ],
        'total_view': 10,
        'total_bookmarks': 20,
        'is_bookmarked': true,
        'visible': true,
        'is_muted': false,
        'illust_ai_type': 2,
        'series': {'id': 7, 'title': '系列'},
        'illust_book_style': 0,
        'total_comments': 3,
      };

      final value = illust.Illusts.fromJson(source);
      final roundTripped = illust.Illusts.fromJson(value.toJson());

      expect(roundTripped, value);
      expect(value.toJson()['x_restrict'], 1);
      expect(value.toJson()['illust_ai_type'], 2);
      expect(value.illustAiType, 2);
      expect(value.illustAIType, 2);
      expect(value.metaPages, hasLength(1));
      expect(value.user.isFollowed, isTrue);
    });

    test('用户详情、评论和系列可以 round-trip', () {
      final detail = user_detail.UserDetail.fromJson({
        'user': {
          'id': 9,
          'name': 'user',
          'account': 'account',
          'profile_image_urls': {'medium': 'medium'},
          'is_followed': true,
        },
        'profile': {
          'birth_year': 1990,
          'total_follow_users': 10,
          'twitter_url': 'https://twitter.example/user',
        },
        'profile_publicity': {
          'birth_day': '01-01',
          'birth_year': '1990',
          'pawoo': true,
        },
        'workspace': {
          'pc': 'PC',
          'workspace_image_url': {'url': 'image'},
        },
      });

      expect(user_detail.UserDetail.fromJson(detail.toJson()), detail);
      expect(detail.toJson()['profile_publicity'], containsPair('birth_day', '01-01'));

      final comments = comment.CommentResponse.fromJson({
        'total_comments': 1,
        'comments': [
          {
            'id': 2,
            'comment': '评论',
            'date': '2024-02-03T04:05:06Z',
            'user': {'id': 3, 'name': 'commenter'},
            'parent_comment': {'id': 1, 'comment': '父评论'},
            'has_replies': true,
            'stamp': {'stamp_id': 4, 'stamp_url': 'stamp'},
          },
        ],
        'next_url': 'next',
      });
      expect(comment.CommentResponse.fromJson(comments.toJson()), comments);
      expect(comments.comments.single.stamp?.stampUrl, 'stamp');

      final series = illust_series.IllustSeriesDetailResponse.fromJson({
        'illust_series_context': {
          'content_order': 1,
          'next': {'id': 2, 'title': 'next'},
        },
        'illust_series_detail': {
          'id': 7,
          'title': 'series',
          'cover_image_urls': {'medium': 'cover'},
          'watchlist_added': true,
        },
      });
      expect(
        illust_series.IllustSeriesDetailResponse.fromJson(series.toJson()),
        series,
      );
    });

    test('小说、书签、标签、Answer/TTL 和特辑可以 round-trip', () {
      final novelValue = novel.Novel.fromJson({
        'id': 10,
        'title': '小说',
        'caption': '说明',
        'restrict': 0,
        'x_restrict': 1,
        'is_original': true,
        'image_urls': {'square_medium': 'square', 'medium': 'medium'},
        'create_date': '2024-03-04T05:06:07Z',
        'tags': [
          {
            'name': 'novel tag',
            'translated_name': '小说标签',
            'added_by_uploaded_user': true,
          },
        ],
        'user': {'id': 8, 'name': 'author'},
        'series': {'id': 9, 'title': 'series'},
        'novel_ai_type': 2,
      });
      expect(novel.Novel.fromJson(novelValue.toJson()), novelValue);
      expect(novelValue.NovelAIType, 2);

      final bookmarkValue = bookmark.BookmarkRsp.fromJson({
        'bookmark_detail': {
          'is_bookmarked': true,
          'tags': [{'name': 'tag', 'is_registered': true}],
          'restrict': 'public',
        },
      });
      expect(bookmark.BookmarkRsp.fromJson(bookmarkValue.toJson()), bookmarkValue);

      final autoWords = tags.AutoWords.fromJson({
        'tags': [{'name': 'tag', 'translated_name': '标签'}],
      });
      expect(tags.AutoWords.fromJson(autoWords.toJson()), autoWords);

      const answer = OnezeroAnswer(name: 'A', type: 1, data: 'data', ttl: 60);
      final onezero = OnezeroResponse.fromJson({
        'Answer': [answer.toJson()],
      });
      expect(OnezeroResponse.fromJson(onezero.toJson()), onezero);
      expect(onezero.toJson()['Answer'], hasLength(1));
      expect((onezero.toJson()['Answer'] as List).single['TTL'], 60);

      final spotlight = SpotlightResponse.fromJson({
        'spotlight_articles': [
          {
            'id': 5,
            'title': '特辑',
            'pure_title': '特辑',
            'thumbnail': 'thumb',
            'article_url': 'article',
            'publish_date': '2024-05-06T07:08:09Z',
          },
        ],
        'next_url': null,
      });
      expect(SpotlightResponse.fromJson(spotlight.toJson()), spotlight);
    });

    test('动态 Map/列表模型会复制解析边界并保留嵌套结构', () {
      final source = <String, dynamic>{
        'id': '10',
        'title': 'web novel',
        'seriesId': {
          'nested': [1],
        },
        'tags': ['tag'],
        'rating': {'like': 2, 'bookmark': 3, 'view': 4},
        'glossaryItems': [
          {
            'name': 'term',
          },
        ],
        'images': {
          '1': {
            'novelImageId': 'image',
            'sl': '1',
            'urls': {'original': 'original'},
          },
        },
        'illusts': {
          '1': {
            'illust': {
              'images': {'small': 'small'},
            },
          },
        },
      };

      final value = novel_web.NovelWebResponse.fromJson(source);
      (source['seriesId'] as Map)['nested'] = <int>[99];
      (source['glossaryItems'] as List).clear();

      expect((value.seriesId as Map)['nested'], [1]);
      expect(value.glossaryItems, hasLength(1));
      expect(novel_web.NovelWebResponse.fromJson(value.toJson()), value);
      expect(value.copyWith(seriesId: null).seriesId, isNull);
    });

    test('缺失字段和错误类型使用默认值且不抛异常', () {
      expect(() => illust.Illusts.fromJson({
            'id': 'invalid',
            'image_urls': <dynamic>[],
            'tags': 'not-json',
            'meta_pages': <dynamic>[1, 'bad'],
          }),
          returnsNormally);
      expect(() => novel.Novel.fromJson({'create_date': <dynamic>[]}), returnsNormally);
      expect(() => comment.Comment.fromJson({'date': <dynamic>[]} ), returnsNormally);
      expect(() => ugoira.UgoiraMetadataResponse.fromJson({}), returnsNormally);
      expect(() => SpotlightArticle.fromJson({'publish_date': {'bad': true}}), returnsNormally);
      expect(const illust.Illusts().isEmpty, isTrue);
      expect(novel.Novel().isEmpty, isTrue);
      expect(const ugoira.UgoiraMetadataResponse().isEmpty, isTrue);
    });

    test('copyWith 不修改原对象并支持显式清空 nullable 字段', () {
      final original = illust.Illusts(
        metaSinglePage: const illust.MetaSinglePage(originalImageUrl: 'url'),
        series: const illust.IllustSeries(id: 1, title: 'series'),
        totalComments: 3,
        tags: const [illust.Tags(name: 'tag')],
      );
      final cleared = original.copyWith(
        metaSinglePage: null,
        series: null,
        totalComments: null,
        tags: <illust.Tags>[],
      );

      expect(original.metaSinglePage, isNotNull);
      expect(original.series, isNotNull);
      expect(original.totalComments, 3);
      expect(original.tags, hasLength(1));
      expect(cleared.metaSinglePage, isNull);
      expect(cleared.series, isNull);
      expect(cleared.totalComments, isNull);
      expect(cleared.tags, isEmpty);

      final list = <illust.Tags>[const illust.Tags(name: 'external')];
      final copied = original.copyWith(tags: list);
      list.clear();
      expect(copied.tags, hasLength(1));
    });
  });

  group('SQLite 模型兼容性', () {
    test('下载图片保留 ID、0/1 布尔值和原图 URL 压缩', () {
      const originalUrl =
          'https://i.pximg.net/img-original/img/2024/01/01/00/00/00/1.jpg';
      final image = DownloadedImage(
        id: 7,
        illustId: 8,
        part: 1,
        fileName: 'file',
        extension: '.jpg',
        fileSize: 12,
        originalUrl: originalUrl,
      );
      final map = image.toMap(includeId: true);

      expect(map[DownloadedImageColumns.id], 7);
      expect(
        map[DownloadedImageColumns.originalUrl],
        PixivUrlUtil.compressOriginalUrl(originalUrl),
      );
      expect(DownloadedImage.fromMap(map), image);
      expect(DownloadedImage.fromMap({...map, DownloadedImageColumns.width: 'bad'}).width, isNull);
    });

    test('下载插画保留 GZIP/URL 压缩、布尔值及旧 image_urls 回退', () {
      final source = illust.Illusts(
        id: 12,
        title: 'downloaded',
        type: 'ugoira',
        imageUrls: const illust.ImageUrls(
          medium: 'https://i.pximg.net/img-original/img/medium.jpg',
        ),
        user: const illust.User(id: 5, name: 'artist'),
        tags: const [illust.Tags(name: 'tag')],
      );
      final record = DownloadedIllust.fromIllusts(
        source,
        'artist/12',
        downloadTime: 42,
        isTranslated: true,
      );
      final map = record.toMap();

      expect(map[DownloadedIllustColumns.isTranslated], 1);
      expect(map[DownloadedIllustColumns.illustJson], startsWith('GZIP:'));
      expect(
        map[DownloadedIllustColumns.imageUrlsJson],
        contains(PixivUrlUtil.pxImgPlaceholder),
      );
      expect(DownloadedIllust.fromMap(map).toIllusts().imageUrls.medium,
          source.imageUrls.medium);

      final oldMap = <String, dynamic>{
        ...map,
        DownloadedIllustColumns.imageUrlsJson: '',
        DownloadedIllustColumns.illustJson: jsonEncode(source.toJson()),
      };
      expect(
        DownloadedIllust.fromMap(oldMap).toIllusts().imageUrls.medium,
        source.imageUrls.medium,
      );
      expect(record.copyWith(id: 9).toMap(includeId: true)[DownloadedIllustColumns.id], 9);
    });

    test('原图模型保留列名、ID、nullable 和 0/1 布尔值', () {
      const set = OriginalImageSet(
        id: 3,
        illustId: 4,
        editionName: 'default',
        isDefault: true,
      );
      final setMap = set.toMap(includeId: true);
      expect(setMap['id'], 3);
      expect(setMap['illust_id'], 4);
      expect(setMap['is_default'], 1);
      expect(OriginalImageSet.fromMap(setMap), set);

      const mapping = OriginalPageMapping(
        id: 5,
        setId: 3,
        displayOrder: 1,
        downloadedPart: 0,
        relationType: OriginalRelationType.replacement,
        manuallyAdjusted: true,
      );
      final mappingMap = mapping.toMap(includeId: true);
      expect(mappingMap['manually_adjusted'], 1);
      expect(OriginalPageMapping.fromMap(mappingMap), mapping);
      expect(mapping.copyWith(downloadedPart: null).downloadedPart, isNull);
    });
  });
}
