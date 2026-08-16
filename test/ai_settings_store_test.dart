import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/ai/ai_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'default provider resolves default prompts and can be switched',
    () async {
      final store = AiSettingsStore();
      await store.init();

      await store.upsertProvider(_provider('a', 'Provider A'));
      expect(store.defaultProviderId, 'a');

      await store.upsertProvider(_provider('b', 'Provider B'));
      final prompt = AiPromptPreset(
        id: 'default-prompt',
        name: 'Default prompt',
        sceneId: AiPromptScenes.illustTitle,
        providerId: '',
        useDefaultProvider: true,
        systemPrompt: '{{text}}',
        userTemplate: '{{text}}',
        isActive: true,
      );
      await store.upsertPrompt(prompt);

      expect(
        store.requireActivePrompt(AiPromptScenes.illustTitle).provider.id,
        'a',
      );
      await store.setDefaultProvider('b');
      expect(
        store.requireActivePrompt(AiPromptScenes.illustTitle).provider.id,
        'b',
      );

      final manualPrompt = prompt.copyWith(
        id: 'manual-prompt',
        providerId: 'a',
        useDefaultProvider: false,
      );
      await store.upsertPrompt(manualPrompt);
      expect(
        store.requireActivePrompt(AiPromptScenes.illustTitle).provider.id,
        'a',
      );

      await store.deleteProvider('b');
      expect(store.defaultProviderId, 'a');
    },
  );
}

AiProviderConfig _provider(String id, String name) => AiProviderConfig(
  id: id,
  name: name,
  protocol: AiProtocolType.openAiChatCompletions,
  baseUrl: 'https://example.com/v1',
  apiKey: '',
  model: 'model',
);
