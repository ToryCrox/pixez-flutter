import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixez/manga_ocr/manga_ocr_controller.dart';
import 'package:pixez/manga_ocr/manga_ocr_models.dart';

class MangaOcrOverlay extends StatelessWidget {
  final MangaPageOcrResult result;
  final String? selectedBlockId;
  final ValueChanged<String> onSelected;

  const MangaOcrOverlay({
    super.key,
    required this.result,
    required this.selectedBlockId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (result.imageWidth <= 0 || result.imageHeight <= 0) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageRatio = result.imageWidth / result.imageHeight;
        final viewportRatio = constraints.maxWidth / constraints.maxHeight;
        late final double displayWidth;
        late final double displayHeight;
        if (imageRatio > viewportRatio) {
          displayWidth = constraints.maxWidth;
          displayHeight = displayWidth / imageRatio;
        } else {
          displayHeight = constraints.maxHeight;
          displayWidth = displayHeight * imageRatio;
        }
        final offsetX = (constraints.maxWidth - displayWidth) / 2;
        final offsetY = (constraints.maxHeight - displayHeight) / 2;
        return Stack(
          children: [
            for (final block in result.blocks)
              Positioned(
                left: offsetX + block.bounds.left * displayWidth,
                top: offsetY + block.bounds.top * displayHeight,
                width: block.bounds.width * displayWidth,
                height: block.bounds.height * displayHeight,
                child: Tooltip(
                  message:
                      block.sourceText.isEmpty ? '识别失败/低置信度' : block.sourceText,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelected(block.id),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color:
                            selectedBlockId == block.id
                                ? Colors.amber.withValues(alpha: 0.20)
                                : Colors.transparent,
                        border: Border.all(
                          color:
                              block.isLowConfidence
                                  ? Colors.orangeAccent
                                  : selectedBlockId == block.id
                                  ? Colors.amber
                                  : Colors.lightBlueAccent,
                          width: selectedBlockId == block.id ? 2.5 : 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class MangaOcrSidePanel extends StatefulWidget {
  final MangaOcrController controller;
  final VoidCallback onClose;
  final VoidCallback onRetryTranslation;
  final VoidCallback onForceOcr;

  const MangaOcrSidePanel({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onRetryTranslation,
    required this.onForceOcr,
  });

  @override
  State<MangaOcrSidePanel> createState() => _MangaOcrSidePanelState();
}

class _MangaOcrSidePanelState extends State<MangaOcrSidePanel> {
  final _itemKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant MangaOcrSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final id = widget.controller.selectedBlockId;
    final itemContext = id == null ? null : _itemKeys[id]?.currentContext;
    if (itemContext != null) {
      Scrollable.ensureVisible(
        itemContext,
        duration: const Duration(milliseconds: 180),
        alignment: 0.2,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final blocks = controller.result?.blocks ?? const <MangaTextBlock>[];
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 12,
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('当前页 OCR 与翻译'),
              subtitle:
                  controller.message.isEmpty ? null : Text(controller.message),
              trailing: IconButton(
                tooltip: '关闭',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ),
            if (controller.isRunning)
              LinearProgressIndicator(value: controller.progress),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child:
                  blocks.isEmpty
                      ? Center(
                        child: Text(
                          controller.isRunning ? '正在自动检测整页文字…' : '当前页未检测到文字',
                        ),
                      )
                      : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: blocks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final block = blocks[index];
                          final key = _itemKeys.putIfAbsent(
                            block.id,
                            GlobalKey.new,
                          );
                          final selected =
                              controller.selectedBlockId == block.id;
                          return Card(
                            key: key,
                            color:
                                selected
                                    ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                    : null,
                            child: InkWell(
                              onTap: () => controller.selectBlock(block.id),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text('#${index + 1}'),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${block.language} · ${_directionLabel(block.direction)}',
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                        ),
                                        const Spacer(),
                                        Text(
                                          '检测 ${(block.detectionConfidence * 100).round()}%  '
                                          'OCR ${(block.recognitionConfidence * 100).round()}%',
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                    if (block.warning != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        block.warning!,
                                        style: const TextStyle(
                                          color: Colors.orangeAccent,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    SelectableText(
                                      block.sourceText.isEmpty
                                          ? '（未识别出文字）'
                                          : block.sourceText,
                                    ),
                                    if (block.translatedText.isNotEmpty) ...[
                                      const Divider(height: 20),
                                      SelectableText(block.translatedText),
                                    ],
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: IconButton(
                                        tooltip: '复制原文和译文',
                                        visualDensity: VisualDensity.compact,
                                        onPressed:
                                            () => Clipboard.setData(
                                              ClipboardData(
                                                text: [
                                                      block.sourceText,
                                                      block.translatedText,
                                                    ]
                                                    .where(
                                                      (text) => text.isNotEmpty,
                                                    )
                                                    .join('\n'),
                                              ),
                                            ),
                                        icon: const Icon(Icons.copy, size: 18),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (controller.isRunning)
                    OutlinedButton.icon(
                      onPressed: controller.cancel,
                      icon: const Icon(Icons.stop),
                      label: const Text('取消'),
                    )
                  else ...[
                    OutlinedButton.icon(
                      onPressed: widget.onRetryTranslation,
                      icon: const Icon(Icons.translate),
                      label: const Text('重新翻译'),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.onForceOcr,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新 OCR'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _directionLabel(MangaTextDirection direction) =>
      switch (direction) {
        MangaTextDirection.horizontal => '横排',
        MangaTextDirection.vertical => '竖排',
        MangaTextDirection.unknown => '方向未知',
      };
}
