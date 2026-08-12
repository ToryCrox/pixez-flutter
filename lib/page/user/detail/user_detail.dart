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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixez/ai/ai_translation_error_handler.dart';
import 'package:pixez/component/selectable_html.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/user_detail.dart';
import 'package:pixez/page/follow/follow_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

class UserDetailPage extends StatefulWidget {
  final UserDetail? userDetail;
  final bool isNewNested;
  final bool? isNovel;

  UserDetailPage({
    Key? key,
    required this.userDetail,
    this.isNewNested = false,
    this.isNovel,
  }) : super(key: key);

  @override
  _UserDetailPageState createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  bool _isNovel = false;
  bool _isNewNested = false;
  String _translatedComment = '';
  String _translationSource = '';
  bool _isTranslatingComment = false;

  @override
  void initState() {
    _isNewNested = widget.isNewNested;
    _isNovel = widget.isNovel ?? false;
    super.initState();
    _hydrateCachedComment();
  }

  @override
  void didUpdateWidget(covariant UserDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userDetail?.user.id != widget.userDetail?.user.id ||
        oldWidget.userDetail?.user.comment != widget.userDetail?.user.comment) {
      _translatedComment = '';
      _translationSource = '';
      _hydrateCachedComment();
    }
  }

  String get _comment => widget.userDetail?.user.comment?.trim() ?? '';

  Future<void> _hydrateCachedComment() async {
    final detail = widget.userDetail;
    final comment = _comment;
    if (detail == null || comment.isEmpty) return;
    final translation = await aiTranslationService.cachedAuthorIntroduction(
      userId: detail.user.id,
      html: comment,
    );
    if (mounted &&
        widget.userDetail?.user.id == detail.user.id &&
        _comment == comment &&
        translation != null) {
      setState(() {
        _translatedComment = translation;
        _translationSource = comment;
      });
    }
  }

  Future<void> _translateComment() async {
    final detail = widget.userDetail;
    final comment = _comment;
    if (detail == null || comment.isEmpty || _isTranslatingComment) return;
    setState(() => _isTranslatingComment = true);
    try {
      final translation = await aiTranslationService
          .translateAuthorIntroduction(
            userId: detail.user.id,
            html: comment,
            forceRefresh:
                _translatedComment.isNotEmpty && _translationSource == comment,
          );
      if (mounted &&
          widget.userDetail?.user.id == detail.user.id &&
          _comment == comment) {
        setState(() {
          _translatedComment = translation;
          _translationSource = comment;
        });
      }
    } catch (error) {
      await showAiTranslationError(context, error);
    } finally {
      if (mounted) setState(() => _isTranslatingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    var detail = widget.userDetail;
    var profile = widget.userDetail?.profile;
    var public = widget.userDetail?.profile_publicity;
    if (_isNewNested)
      return SafeArea(
        top: false,
        bottom: false,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: Builder(
            builder: (context) {
              return _buildScrollView(context, detail, profile, public);
            },
          ),
        ),
      );
    return _buildScrollView(context, detail, profile, public);
  }

  CustomScrollView _buildScrollView(
    BuildContext context,
    UserDetail? detail,
    Profile? profile,
    Profile_publicity? public,
  ) {
    return CustomScrollView(
      key: PageStorageKey<String>("user_detail"),
      slivers: [
        if (_isNewNested)
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              child: SelectionArea(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child:
                      _comment.isEmpty
                          ? SelectableHtml(data: '~')
                          : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed:
                                      _isTranslatingComment
                                          ? null
                                          : _translateComment,
                                  icon:
                                      _isTranslatingComment
                                          ? const SizedBox.square(
                                            dimension: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Icon(
                                            Icons.auto_awesome_outlined,
                                            size: 16,
                                          ),
                                  label: Text(
                                    _translatedComment.isNotEmpty &&
                                            _translationSource == _comment
                                        ? '重新 AI ${I18n.of(context).translate}'
                                        : 'AI ${I18n.of(context).translate}',
                                  ),
                                ),
                              ),
                              SelectableHtml(data: _comment),
                              if (_translatedComment.isNotEmpty &&
                                  _translationSource == _comment) ...[
                                const Divider(),
                                SelectableHtml(data: _translatedComment),
                              ],
                            ],
                          ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: DataTable(
              columns: <DataColumn>[
                DataColumn(label: Text(I18n.of(context).nickname)),
                DataColumn(
                  label: Expanded(child: Text(detail?.user.name ?? "")),
                ),
              ],
              rows: <DataRow>[
                DataRow(
                  cells: [
                    DataCell(Text(I18n.of(context).painter_id)),
                    DataCell(
                      Text(detail?.user.id.toString() ?? ""),
                      onTap: () {
                        try {
                          Clipboard.setData(
                            ClipboardData(text: detail!.user.id.toString()),
                          );
                        } catch (e) {}
                      },
                    ),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(Text(I18n.of(context).total_follow_users)),
                    DataCell(
                      Text(detail?.profile.total_follow_users.toString() ?? ""),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (BuildContext context) {
                              return Scaffold(
                                appBar: AppBar(
                                  title: Text(I18n.of(context).followed),
                                ),
                                body:
                                    detail == null
                                        ? Container()
                                        : FollowList(
                                          id: detail.user.id,
                                          isNovel: _isNovel,
                                        ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(Text(I18n.of(context).total_mypixiv_users)),
                    DataCell(
                      Text(
                        detail?.profile.total_mypixiv_users.toString() ?? "",
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (BuildContext context) {
                              return Scaffold(
                                appBar: AppBar(),
                                body:
                                    detail == null
                                        ? Container()
                                        : FollowList(
                                          id: detail.user.id,
                                          isFollowMe: true,
                                        ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(Text(I18n.of(context).twitter_account)),
                    DataCell(
                      Text(profile?.twitter_account ?? ""),
                      onTap: () async {
                        final url = profile?.twitter_url;
                        if (url != null) {
                          try {
                            if (Platform.isIOS) {
                              await launchUrlString(
                                url,
                                mode: LaunchMode.externalApplication,
                              );
                            } else {
                              await launchUrlString(url);
                            }
                          } catch (e) {
                            Share.share(url);
                          }
                        }
                      },
                    ),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(Text(I18n.of(context).gender)),
                    DataCell(Text(detail?.profile.gender ?? "")),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(Text(I18n.of(context).job)),
                    DataCell(Text(detail?.profile.job ?? "")),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(Text('Pawoo')),
                    DataCell(
                      Text(public?.pawoo != null ? 'Link' : 'none'),
                      onTap: () async {
                        if (public?.pawoo == null || !public!.pawoo) return;
                        var url = detail?.profile.pawoo_url;
                        try {
                          await launchUrlString(url!);
                        } catch (e) {}
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: Container(height: 200)),
      ],
    );
  }
}
