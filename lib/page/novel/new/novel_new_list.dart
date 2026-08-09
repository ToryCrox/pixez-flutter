import 'package:flutter/material.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/lighting/lighting_store.dart';
import 'package:pixez/main.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/page/novel/component/novel_lighting_list.dart';

class NovelNewList extends StatefulWidget {
  const NovelNewList({super.key});

  @override
  State<NovelNewList> createState() => _NovelNewListState();
}

class _NovelNewListState extends State<NovelNewList> {
  String restrict = 'public';
  late FutureGet futureGet;

  String get _cacheKey => 'novel_follow_${accountStore.now!.userId}_$restrict';

  @override
  void initState() {
    futureGet = () => apiClient.getNovelFollow(restrict);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: Icon(Icons.list),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16.0),
                    ),
                  ),
                  builder: (context) {
                    return SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            title: Text(I18n.of(context).public),
                            onTap: () {
                              setState(() {
                                restrict = 'public';
                                futureGet =
                                    () => apiClient.getNovelFollow(restrict);
                              });
                              Navigator.of(context).pop();
                            },
                          ),
                          ListTile(
                            title: Text(I18n.of(context).private),
                            onTap: () {
                              setState(() {
                                restrict = 'private';
                                futureGet =
                                    () => apiClient.getNovelFollow(restrict);
                              });
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Expanded(
            child: NovelLightingList(futureGet: futureGet, cacheKey: _cacheKey),
          ),
        ],
      ),
    );
  }
}
