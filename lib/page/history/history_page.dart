import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pixez/component/pixez_easy_refresh.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/illust_card.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/history/history_store.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final HistoryStore store = HistoryStore();
  final TextEditingController _textEditingController = TextEditingController();

  @override
  void initState() {
    super.initState();
    store.fetch(refresh: true);
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    store.easyRefreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _textEditingController,
          onChanged: (word) {
            store.search(word.trim());
          },
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: I18n.of(context).search_word_hint,
          ),
        ),
        actions: <Widget>[
          Observer(builder: (context) {
            if (_textEditingController.text.isNotEmpty) {
              return IconButton(
                icon: Icon(Icons.close),
                onPressed: () {
                  _textEditingController.clear();
                  store.search("");
                },
              );
            }
            return Container();
          }),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.delete),
        onPressed: () {
          _cleanAll(context);
        },
      ),
      body: Observer(builder: (context) {
        if (store.loading && store.illusts.isEmpty) {
          return Center(child: CircularProgressIndicator());
        }
        if (!store.loading && store.illusts.isEmpty) {
          return Center(child: Text("No Data"));
        }
        return _buildBody();
      }),
    );
  }

  Widget _buildBody() {
    return PixezEasyRefresh.builder(
      controller: store.easyRefreshController,
      onRefresh: () async {
        await store.fetch(refresh: true);
      },
      onLoad: () async {
        await store.fetch(refresh: false);
      },
      header: PixezDefault.header(context),
      footer: PixezDefault.footer(context),
      childBuilder: (context, physics, scrollController) {
        if (userSetting.useWaterfallFlow) {
          return WaterfallFlow.builder(
            physics: physics,
            controller: scrollController,
            padding: EdgeInsets.all(5.0),
            gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
              crossAxisCount: _getCrossAxisCount(),
              crossAxisSpacing: 5.0,
              mainAxisSpacing: 5.0,
            ),
            itemCount: store.illusts.length,
            itemBuilder: (context, index) {
              return IllustCard(
                store: store.illusts[index],
                layoutMode: IllustCardLayoutMode.waterfall,
                lightingStore: null,
                onLongPress: () {
                  _showDeleteDialog(context, store.illusts[index].id);
                },
              );
            },
          );
        } else {
          return GridView.builder(
            physics: physics,
            controller: scrollController,
            padding: EdgeInsets.all(5.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _getCrossAxisCount(),
              childAspectRatio: userSetting.gridAspectRatio,
              crossAxisSpacing: 5.0,
              mainAxisSpacing: 5.0,
            ),
            itemCount: store.illusts.length,
            itemBuilder: (context, index) {
              return IllustCard(
                store: store.illusts[index],
                layoutMode: IllustCardLayoutMode.grid,
                lightingStore: null,
                onLongPress: () {
                  _showDeleteDialog(context, store.illusts[index].id);
                },
              );
            },
          );
        }
      },
    );
  }

  int _getCrossAxisCount() {
    if (userSetting.crossAdapt) {
      return _buildSliderValue();
    } else {
      return (MediaQuery.of(context).orientation == Orientation.portrait)
          ? userSetting.crossCount
          : userSetting.hCrossCount;
    }
  }

  int _buildSliderValue() {
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

  Future<void> _cleanAll(BuildContext context) async {
    final result = await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("${I18n.of(context).delete} ${I18n.of(context).all}?"),
            actions: <Widget>[
              TextButton(
                child: Text(I18n.of(context).cancel),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text(I18n.of(context).ok),
                onPressed: () {
                  Navigator.of(context).pop("OK");
                },
              ),
            ],
          );
        });
    if (result == "OK") {
      store.deleteAll();
    }
  }

  Future<void> _showDeleteDialog(BuildContext context, int id) async {
    final result = await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("${I18n.of(context).delete}?"),
            actions: <Widget>[
              TextButton(
                child: Text(I18n.of(context).cancel),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text(I18n.of(context).ok),
                onPressed: () {
                  Navigator.of(context).pop("OK");
                },
              ),
            ],
          );
        });
    if (result == "OK") {
      store.delete(id);
    }
  }
}
