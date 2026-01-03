/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/network_speed_floating_ball.dart';
import 'package:pixez/main.dart';

class NetworkSpeedWrapper extends StatelessWidget {
  final Widget? child;

  const NetworkSpeedWrapper({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      if (userSetting.showNetworkSpeedBall) {
        return Stack(
          alignment: Alignment.topLeft,
          clipBehavior: Clip.none,
          children: [
            child ?? Container(),
            const FloatingNetworkSpeedBall(),
          ],
        );
      }
      return child ?? Container();
    });
  }
}
