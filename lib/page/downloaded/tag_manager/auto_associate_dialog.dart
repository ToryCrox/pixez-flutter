import 'package:flutter/material.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/store/tag_manager_store.dart';
import 'package:pixez/page/downloaded/tag_manager/parent_selection_dialog.dart';

class AutoAssociateDialog extends StatefulWidget {
  final List<TagAssociationProposal> proposals;

  const AutoAssociateDialog({super.key, required this.proposals});

  @override
  State<AutoAssociateDialog> createState() => _AutoAssociateDialogState();
}

class _AutoAssociateDialogState extends State<AutoAssociateDialog> {
  late List<_ProposalEditState> _editStates;
  final Map<int, TextEditingController> _controllers = {};
  bool _allSelected = true;

  @override
  void initState() {
    super.initState();
    _editStates = widget.proposals.map((p) {
      final controller = TextEditingController(text: p.newChildName);
      _controllers[p.childTag.id] = controller;
      return _ProposalEditState(
        proposal: p,
        isSelected: true,
        newChildName: p.newChildName,
        parentTag: p.parentTag,
        controller: controller,
      );
    }).toList();
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleAll(bool? value) {
    if (value == null) return;
    setState(() {
      _allSelected = value;
      for (var s in _editStates) {
        s.isSelected = value;
      }
    });
  }

  Future<void> _changeParent(_ProposalEditState state) async {
    final resultId = await showDialog<int>(
      context: context,
      builder: (context) => ParentSelectionDialog(
        currentParentId: state.parentTag.id,
        childTagId: state.proposal.childTag.id,
      ),
    );

    if (resultId != null && resultId != 0) {
      final selectedTag = tagManagerStore.tags.firstWhere((t) => t.tag.id == resultId).tag;
      final mainTag = tagManagerStore.getMainTagByTag(selectedTag);
      setState(() {
        state.parentTag = mainTag ?? selectedTag;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = _editStates.where((s) => s.isSelected).length;

    return AlertDialog(
      title: const Text('智能自动关联预览'),
      content: Container(
        constraints: const BoxConstraints(maxWidth: 800), // Higher limit for sideways layout
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            CheckboxListTile(
              title: const Text('全选'),
              subtitle: Text('已勾选 $selectedCount / ${_editStates.length} 项'),
              value: _allSelected,
              onChanged: _toggleAll,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(),
            Expanded(
              child: ListView.separated(
                itemCount: _editStates.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final state = _editStates[index];
                  final child = state.proposal.childTag;
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: state.isSelected,
                          onChanged: (v) => setState(() => state.isSelected = v ?? false),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${child.name} (${child.translatedName})',
                                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: state.proposal.suggestionReason == '正则匹配' 
                                          ? theme.colorScheme.primaryContainer 
                                          : theme.colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      state.proposal.suggestionReason,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: state.proposal.suggestionReason == '正则匹配' 
                                            ? theme.colorScheme.primary 
                                            : theme.colorScheme.secondary,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '数量: ${child.count}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('新翻译: '),
                                  Expanded(
                                    child: SizedBox(
                                      height: 36,
                                      child: TextField(
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          border: OutlineInputBorder(),
                                        ),
                                        controller: state.controller,
                                        onChanged: (v) => state.newChildName = v,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('归属作品: '),
                                  InkWell(
                                    onTap: () => _changeParent(state),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: theme.dividerColor),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${state.parentTag.name} (${state.parentTag.translatedName})',
                                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: selectedCount == 0 ? null : () {
            final results = _editStates.where((s) => s.isSelected).map((s) => TagAssociationProposal(
              childTag: s.proposal.childTag,
              parentTag: s.parentTag,
              newChildName: s.newChildName,
              suggestionReason: s.proposal.suggestionReason,
            )).toList();
            Navigator.pop(context, results);
          },
          child: const Text('确认关联'),
        ),
      ],
    );
  }
}

class _ProposalEditState {
  final TagAssociationProposal proposal;
  bool isSelected;
  String newChildName;
  DownloadedTag parentTag;
  final TextEditingController controller;

  _ProposalEditState({
    required this.proposal,
    required this.isSelected,
    required this.newChildName,
    required this.parentTag,
    required this.controller,
  });
}
