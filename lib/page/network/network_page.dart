import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';

class NetworkPage extends StatefulWidget {
  final bool? automaticallyImplyLeading;
  const NetworkPage({Key? key, this.automaticallyImplyLeading}) : super(key: key);

  @override
  _NetworkPageState createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  late bool _automaticallyImplyLeading;
  late TextEditingController _textEditingController;
  late TextEditingController _dnsServersController;

  List<HostInfo> _hostInfoList = [];
  bool _isRefreshingDns = false;
  bool _isTestingLatency = false;

  @override
  void initState() {
    _textEditingController = TextEditingController(text: userSetting.pictureSource);
    _dnsServersController = TextEditingController(text: Hoster.dnsServers.join(', '));
    _automaticallyImplyLeading = widget.automaticallyImplyLeading ?? false;
    _loadHostInfo();
    super.initState();
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    _dnsServersController.dispose();
    super.dispose();
  }

  void _loadHostInfo() {
    setState(() => _hostInfoList = Hoster.getAllHostInfo());
  }

  Future<void> _refreshAllDns() async {
    setState(() => _isRefreshingDns = true);
    await Hoster.dnsQueryAll();
    _loadHostInfo();
    setState(() => _isRefreshingDns = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('DNS 查询完成')));
    }
  }

  Future<void> _testAllLatency() async {
    setState(() => _isTestingLatency = true);
    await Hoster.testAllLatency();
    _loadHostInfo();
    setState(() => _isTestingLatency = false);
  }

  Future<void> _testHostLatency(String host) async {
    await Hoster.testAllIpsForHost(host);
    _loadHostInfo();
  }

  Future<void> _selectIp(String host, IpSource source, int index) async {
    await Hoster.setSelectedSource(host, source, index: index);
    _loadHostInfo();
  }

  void _copyDohUrl(String host) {
    final url = 'https://doh.dns.sb/dns-query?name=$host';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制: $url')));
  }

  Future<void> _showAddCustomIpDialog(String host) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: Text('添加自定义 IP: $host'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'IP 地址或 DNS JSON',
            hintText: '输入IP地址，或粘贴DNS查询JSON结果',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(I18n.of(context).cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(I18n.of(context).ok),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final ips = _parseIpsFromInput(result);
      for (final ip in ips) {
        await Hoster.addCustomIp(host, ip);
      }
      _loadHostInfo();
      if (mounted && ips.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加 ${ips.length} 个IP')));
      }
    }
  }

  /// 解析输入内容，支持纯IP或DNS JSON格式
  List<String> _parseIpsFromInput(String input) {
    final trimmed = input.trim();
    // 尝试作为JSON解析
    if (trimmed.startsWith('{')) {
      try {
        final json = jsonDecode(trimmed) as Map<String, dynamic>;
        final answers = json['Answer'] as List<dynamic>?;
        if (answers != null) {
          return answers
              .map((a) => (a as Map<String, dynamic>)['data'] as String?)
              .where((ip) => ip != null && _isValidIpv4(ip))
              .cast<String>()
              .toList();
        }
      } catch (_) {}
    }
    // 尝试按逗号/换行分割
    final parts = trimmed.split(RegExp(r'[,\n\s]+'));
    return parts.where((ip) => _isValidIpv4(ip.trim())).map((ip) => ip.trim()).toList();
  }

  bool _isValidIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  Future<void> _removeCustomIp(String host, String ip) async {
    await Hoster.removeCustomIp(host, ip);
    _loadHostInfo();
  }

  Future<void> _saveDnsServers() async {
    final input = _dnsServersController.text.trim();
    final List<String> servers = input.isEmpty
        ? []
        : input.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    await Hoster.setDnsServers(servers);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(I18n.of(context).saved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Observer(builder: (_) {
        return ListView(
          children: [
            _buildAppBar(),
            _buildTitle(),
            _buildTip(),
            const SizedBox(height: 8),
            _buildSniBypassSwitch(),
            _buildImageSiteCard(),
            _buildDnsHostSettingsSection(),
          ],
        );
      }),
    );
  }

  Widget _buildAppBar() => AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: Theme.of(context).textTheme.bodyLarge!.color),
        automaticallyImplyLeading: _automaticallyImplyLeading,
        elevation: 0.0,
      );

  Widget _buildTitle() => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(I18n.of(context).network,
            style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
      );

  Widget _buildTip() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Text(I18n.of(context).network_tip,
            style: const TextStyle(fontSize: 12.0, color: Colors.grey), textAlign: TextAlign.center),
      );

  Widget _buildSniBypassSwitch() => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Observer(builder: (_) {
          return SwitchListTile(
            value: userSetting.disableBypassSni,
            activeThumbColor: Theme.of(context).colorScheme.secondary,
            title: Text(I18n.of(context).disable_sni_bypass),
            subtitle: Text(I18n.of(context).disable_sni_bypass_message),
            onChanged: (value) => _handleSniBypassChange(value),
          );
        }),
      );

  Future<void> _handleSniBypassChange(bool value) async {
    if (value) {
      final result = await showDialog(
        context: context,
        useRootNavigator: false,
        builder: (_) => AlertDialog(
          title: Text(I18n.of(context).please_note_that),
          content: Text(I18n.of(context).please_note_that_content),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(I18n.of(context).cancel)),
            TextButton(onPressed: () => Navigator.of(context).pop('OK'), child: Text(I18n.of(context).ok)),
          ],
        ),
      );
      if (result == 'OK') userSetting.setDisableBypassSni(value);
    } else {
      userSetting.setDisableBypassSni(value);
    }
  }

  Widget _buildImageSiteCard() {
    return Visibility(
      visible: !userSetting.disableBypassSni,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Card(
          child: Column(children: [
            ListTile(
              title: Text(I18n.of(context).image_site,
                  style: TextStyle(color: Theme.of(context).textTheme.bodyLarge!.color)),
              trailing: IconButton(
                icon: const Icon(Icons.refresh_outlined),
                onPressed: () {
                  userSetting.setPictureSource(ImageHost);
                  splashStore.setHost(ImageHost);
                  splashStore.helloWord = "= w =";
                  splashStore.maybeFetch();
                },
              ),
            ),
            _buildImageSiteOption(I18n.of(context).default_title, ImageHost),
            _buildImageSiteOption(ImageCatHost, ImageCatHost),
            _buildCustomHostInput(),
          ]),
        ),
      ),
    );
  }

  Widget _buildImageSiteOption(String title, String source) => ListTile(
        title: Text(title, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge!.color)),
        selected: userSetting.pictureSource == source,
        selectedTileColor: Theme.of(context).colorScheme.secondary,
        onTap: () {
          userSetting.setPictureSource(source);
          splashStore.setHost(source);
          if (source == ImageHost) {
            splashStore.helloWord = "= w =";
            splashStore.maybeFetch();
          }
        },
      );

  Widget _buildCustomHostInput() => ListTile(
        selected: userSetting.pictureSource != ImageHost && userSetting.pictureSource != ImageCatHost,
        selectedTileColor: Theme.of(context).colorScheme.secondary,
        title: TextField(
          maxLines: 1,
          controller: _textEditingController,
          decoration: InputDecoration(
            hintText: 'Host',
            suffixIcon: IconButton(onPressed: _saveCustomHost, icon: const Icon(Icons.check)),
            labelText: I18n.of(context).custom_host,
          ),
        ),
      );

  Future<void> _saveCustomHost() async {
    if (_textEditingController.text.isEmpty) return;
    if (_textEditingController.text.trim().contains(" ")) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("illegal"), backgroundColor: Colors.red));
      return;
    }
    await userSetting.setPictureSource(_textEditingController.text.trim());
    FocusScope.of(context).requestFocus(FocusNode());
  }

  // === DNS与Host设置区域 ===
  Widget _buildDnsHostSettingsSection() {
    return Visibility(
      visible: !userSetting.disableBypassSni,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('DNS 与 Host 设置'),
            _buildDnsServersCard(),
            _buildActionButtons(),
            ..._hostInfoList.map(_buildHostInfoCard).toList(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _buildDnsServersCard() => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('DNS 服务器 (多个用逗号分隔)', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _dnsServersController,
                  decoration: InputDecoration(
                    hintText: Hoster.defaultDnsServers.join(', '),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.save), onPressed: _saveDnsServers),
            ]),
          ]),
        ),
      );

  Widget _buildActionButtons() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isRefreshingDns ? null : _refreshAllDns,
              icon: _isRefreshingDns
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: const Text('刷新DNS'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isTestingLatency ? null : _testAllLatency,
              icon: _isTestingLatency
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.speed),
              label: const Text('全部测速'),
            ),
          ),
        ]),
      );

  Widget _buildHostInfoCard(HostInfo info) {
    // 合并所有IP为一个列表，带来源标签
    final allIps = <_IpWithSource>[
      ...info.defaultIps.asMap().entries.map((e) => _IpWithSource(e.value, IpSource.defaultValue, e.key)),
      ...info.dnsIps.asMap().entries.map((e) => _IpWithSource(e.value, IpSource.dns, e.key)),
      ...info.customIps.asMap().entries.map((e) => _IpWithSource(e.value, IpSource.custom, e.key)),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 标题行
          Row(children: [
            Expanded(child: SelectableText(info.host, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            IconButton(
              icon: const Icon(Icons.speed, size: 20),
              tooltip: '测速',
              onPressed: () => _testHostLatency(info.host),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
            IconButton(
              icon: const Icon(Icons.link, size: 20),
              tooltip: '复制DoH URL',
              onPressed: () => _copyDohUrl(info.host),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              tooltip: '添加自定义IP',
              onPressed: () => _showAddCustomIpDialog(info.host),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
          ]),
          const SizedBox(height: 8),
          // IP横向排列
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: allIps.map((item) => _buildIpChip(item, info)).toList(),
          ),
        ]),
      ),
    );
  }

  Widget _buildIpChip(_IpWithSource item, HostInfo hostInfo) {
    final isSelected = hostInfo.selectedSource == item.source && hostInfo.selectedIndex == item.index;
    final color = _getSourceColor(item.source);
    final latencyText = item.ipInfo.latency == null
        ? ''
        : (item.ipInfo.latency! < 0 ? '超时' : '${item.ipInfo.latency}ms');

    return InkWell(
      onTap: () => _selectIp(hostInfo.host, item.source, item.index),
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: item.ipInfo.ip));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制: ${item.ipInfo.ip}')));
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.25) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300, width: isSelected ? 2 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // 来源标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
            child: Text(_getSourceLabel(item.source), style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 4),
          // IP
          Text(item.ipInfo.ip, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: isSelected ? color : null)),
          // 延迟
          if (latencyText.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(latencyText, style: TextStyle(fontSize: 9, color: _getLatencyColor(item.ipInfo.latency))),
          ],
          // 选中标记
          if (isSelected) ...[
            const SizedBox(width: 4),
            Icon(Icons.check_circle, size: 12, color: color),
          ],
          // 删除按钮（仅自定义）
          if (item.source == IpSource.custom) ...[
            const SizedBox(width: 2),
            GestureDetector(
              onTap: () => _removeCustomIp(hostInfo.host, item.ipInfo.ip),
              child: const Icon(Icons.close, size: 12, color: Colors.red),
            ),
          ],
        ]),
      ),
    );
  }

  String _getSourceLabel(IpSource source) {
    switch (source) {
      case IpSource.defaultValue: return '默认';
      case IpSource.dns: return 'DNS';
      case IpSource.custom: return '自定义';
    }
  }

  Color _getSourceColor(IpSource source) {
    switch (source) {
      case IpSource.defaultValue: return Colors.grey;
      case IpSource.dns: return Colors.blue;
      case IpSource.custom: return Colors.green;
    }
  }

  Color _getLatencyColor(int? latency) {
    if (latency == null || latency < 0) return Colors.red;
    if (latency < 100) return Colors.green;
    if (latency < 300) return Colors.orange;
    return Colors.red;
  }
}

/// 辅助类：IP + 来源信息
class _IpWithSource {
  final IpInfo ipInfo;
  final IpSource source;
  final int index;
  _IpWithSource(this.ipInfo, this.source, this.index);
}
