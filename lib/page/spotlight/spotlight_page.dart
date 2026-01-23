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

import 'dart:math';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/component/pixez_easy_refresh.dart';
import 'package:pixez/component/spotlight_card.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/hello/recom/spotlight_store.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class SpotLightPage extends StatefulWidget {
  @override
  _SpotLightPageState createState() => _SpotLightPageState();
}

class _SpotLightPageState extends State<SpotLightPage> {
  late ScrollController _controller;
  late EasyRefreshController _refreshController;
  late SpotlightStore _spotlightStore;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _refreshController = EasyRefreshController(
        controlFinishLoad: true, controlFinishRefresh: true);
    _spotlightStore = SpotlightStore(_refreshController);
  }

  @override
  void dispose() {
    _controller.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      return Scaffold(
        appBar: AppBar(
          title: Text(I18n.of(context).spotlight),
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.arrow_upward),
              onPressed: () {
                _controller.animateTo(0,
                    duration: Duration(seconds: 1), curve: Curves.ease);
              },
            )
          ],
        ),
        body: PixezEasyRefresh.builder(
            onLoad: () => _spotlightStore.next(),
            onRefresh: () => _spotlightStore.fetch(),
            header: PixezDefault.header(context),
            refreshOnStart: true,
            controller: _refreshController,
            scrollController: _controller,
            childBuilder: (context, physics, scrollController) {
              return WaterfallFlow.builder(
                gridDelegate: _buildGridDelegate(context),
                physics: physics,
                controller: scrollController,
                itemBuilder: (BuildContext context, int index) {
                  return SpotlightCard(
                      spotlight: _spotlightStore.articles[index]);
                },
                itemCount: _spotlightStore.articles.length,
              );
            }),
      );
    });
  }

  SliverWaterfallFlowDelegate _buildGridDelegate(BuildContext context) {
    var count = 2;
    if (userSetting.crossAdapt) {
      count = _buildSliderValue(context);
    } else {
      count = (MediaQuery.of(context).orientation == Orientation.portrait)
          ? userSetting.crossCount
          : userSetting.hCrossCount;
    }
    return SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
      crossAxisCount: count,
    );
  }

  int _buildSliderValue(BuildContext context) {
    final currentValue =
        (MediaQuery.of(context).orientation == Orientation.portrait
                ? userSetting.crossAdapterWidth
                : userSetting.hCrossAdapterWidth)
            .toDouble();
    var nowAdaptWidth = max(currentValue, 50.0);
    nowAdaptWidth = min(nowAdaptWidth, 2160.0);
    final screenWidth = MediaQuery.of(context).size.width;
    final result = max(screenWidth / nowAdaptWidth, 1.0).toInt();
    return result;
  }
}
