import 'package:flutter/material.dart';
import 'package:pixez/custom/app_mouse_cursor.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';

class SaveEffectTrailing extends StatelessWidget {
  const SaveEffectTrailing({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        return FilterChip(
          mouseCursor: appAdaptiveClickable,
          label: Text(I18n.of(context).save_effect),
          selected: userSetting.saveEffectEnable,
          onSelected: (bool value) {
            userSetting.saveEffectEnable = value;
          },
        );
      },
    );
  }
}
