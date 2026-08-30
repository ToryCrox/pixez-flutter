import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class UgoiraMetadataResponse {
  final UgoiraMetadata ugoiraMetadata;

  const UgoiraMetadataResponse({this.ugoiraMetadata = const UgoiraMetadata()});

  factory UgoiraMetadataResponse.fromMap(Map<String, dynamic> map) => UgoiraMetadataResponse(
        ugoiraMetadata: UgoiraMetadata.fromMap(map.optMap('ugoira_metadata')),
      );
  factory UgoiraMetadataResponse.fromJson(Map<String, dynamic> json) => UgoiraMetadataResponse.fromMap(json);
  Map<String, dynamic> toMap() => {'ugoira_metadata': ugoiraMetadata.toMap()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => ugoiraMetadata.isEmpty;
  UgoiraMetadataResponse copyWith({UgoiraMetadata? ugoiraMetadata}) => UgoiraMetadataResponse(ugoiraMetadata: ugoiraMetadata ?? this.ugoiraMetadata);
  @override
  bool operator ==(Object other) => other is UgoiraMetadataResponse && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'UgoiraMetadataResponse(${toMap()})';
}

class UgoiraMetadata {
  final ZipUrls zipUrls;
  final List<Frame> frames;

  const UgoiraMetadata({this.zipUrls = const ZipUrls(), this.frames = const []});

  factory UgoiraMetadata.fromMap(Map<String, dynamic> map) => UgoiraMetadata(
        zipUrls: ZipUrls.fromMap(map.optMap('zip_urls')),
        frames: [
          ...map.optList(
            'frames',
            (e) => Frame.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
      );
  factory UgoiraMetadata.fromJson(Map<String, dynamic> json) => UgoiraMetadata.fromMap(json);
  Map<String, dynamic> toMap() => {
        'zip_urls': zipUrls.toMap(),
        'frames': frames.map((e) => e.toMap()).toList(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => zipUrls.isEmpty && frames.isEmpty;
  UgoiraMetadata copyWith({ZipUrls? zipUrls, List<Frame>? frames}) => UgoiraMetadata(
        zipUrls: zipUrls ?? this.zipUrls,
        frames: frames == null ? [...this.frames] : [...frames],
      );
  @override
  bool operator ==(Object other) => other is UgoiraMetadata && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'UgoiraMetadata(${toMap()})';
}

class Frame {
  final String file;
  final int delay;

  const Frame({this.file = '', this.delay = 0});
  factory Frame.fromMap(Map<String, dynamic> map) => Frame(file: map.optString('file'), delay: map.optInt('delay'));
  factory Frame.fromJson(Map<String, dynamic> json) => Frame.fromMap(json);
  Map<String, dynamic> toMap() => {'file': file, 'delay': delay};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([file, delay]);
  Frame copyWith({String? file, int? delay}) => Frame(file: file ?? this.file, delay: delay ?? this.delay);
  @override
  bool operator ==(Object other) => other is Frame && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Frame(${toMap()})';
}

class ZipUrls {
  final String medium;
  const ZipUrls({this.medium = ''});
  factory ZipUrls.fromMap(Map<String, dynamic> map) => ZipUrls(medium: map.optString('medium'));
  factory ZipUrls.fromJson(Map<String, dynamic> json) => ZipUrls.fromMap(json);
  Map<String, dynamic> toMap() => {'medium': medium};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => medium.isEmpty;
  ZipUrls copyWith({String? medium}) => ZipUrls(medium: medium ?? this.medium);
  @override
  bool operator ==(Object other) => other is ZipUrls && medium == other.medium;
  @override
  int get hashCode => medium.hashCode;
  @override
  String toString() => 'ZipUrls(${toMap()})';
}
