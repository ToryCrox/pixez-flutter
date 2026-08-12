import 'package:pixez/manga_ocr/manga_ocr_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MangaOcrPreferences {
  static const _detectorKey = 'manga_ocr_detector_id';
  static const _recognizerKey = 'manga_ocr_recognizer_id';
  static const _readingOrderKey = 'manga_ocr_reading_order';

  final String detectorId;
  final String recognizerId;
  final MangaReadingOrder readingOrder;

  const MangaOcrPreferences({
    this.detectorId = mangaOcrDefaultDetectorId,
    this.recognizerId = mangaOcrDefaultRecognizerId,
    this.readingOrder = MangaReadingOrder.automatic,
  });

  MangaOcrOptions get options => MangaOcrOptions(readingOrder: readingOrder);

  static Future<MangaOcrPreferences> load() async {
    final values = await SharedPreferences.getInstance();
    return MangaOcrPreferences(
      detectorId: values.getString(_detectorKey) ?? mangaOcrDefaultDetectorId,
      recognizerId:
          values.getString(_recognizerKey) ?? mangaOcrDefaultRecognizerId,
      readingOrder: MangaReadingOrder.fromJson(
        values.getString(_readingOrderKey),
      ),
    );
  }

  Future<void> save() async {
    final values = await SharedPreferences.getInstance();
    await values.setString(_detectorKey, detectorId);
    await values.setString(_recognizerKey, recognizerId);
    await values.setString(_readingOrderKey, readingOrder.name);
  }

  MangaOcrPreferences copyWith({
    String? detectorId,
    String? recognizerId,
    MangaReadingOrder? readingOrder,
  }) => MangaOcrPreferences(
    detectorId: detectorId ?? this.detectorId,
    recognizerId: recognizerId ?? this.recognizerId,
    readingOrder: readingOrder ?? this.readingOrder,
  );
}
