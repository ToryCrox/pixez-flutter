import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/page/hello/setting/ai_settings_page.dart';

bool isAiTranslationConfigurationError(Object error) {
  if (error is AiConfigurationException) return true;
  final message = error.toString();
  return message.contains('AI 服务') ||
      message.contains('AI 提示词') ||
      message.contains('请前往 AI 设置');
}

Future<void> showAiTranslationError(BuildContext context, Object error) async {
  final message = error.toString();
  if (!isAiTranslationConfigurationError(error)) {
    BotToast.showText(text: message);
    return;
  }

  await showDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(I18n.of(dialogContext).ai_translation_not_configured),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(I18n.of(dialogContext).cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AiSettingsPage()),
                  );
                }
              },
              child: Text(I18n.of(dialogContext).go_to_ai_settings),
            ),
          ],
        ),
  );
}
