import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';

class NetworkPage extends StatefulWidget {
  final bool? automaticallyImplyLeading;

  const NetworkPage({Key? key, this.automaticallyImplyLeading})
      : super(key: key);

  @override
  _NetworkPageState createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  late bool _automaticallyImplyLeading;
  late TextEditingController _textEditingController;
  late TextEditingController _dnsServersController;

  List<HostResolveInfo> _hostInfoList = [];
  bool _isRefreshingDns = false;
  bool _isTestingLatency = false;

  @override
  void initState() {
    _textEditingController = TextEditingController(
      text: userSetting.pictureSource,
    );
    // DNS服务器列表用逗号分隔显示
    _dnsServersController = TextEditingController(
      text: Hoster.dnsServers.join(', '),
    );
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
    setState(() {
      _hostInfoList = Hoster.getAllResolveInfo();
    });
  }

  Future<void> _refreshAllDns() async {
    setState(() => _isRefreshingDns = true);
    await Hoster.dnsQueryAll();
    _loadHostInfo();
    setState(() => _isRefreshingDns = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DNS 查询完成')),
      );
    }
  }

  Future<void> _refreshSingleDns(String host) async {
    final success = await Hoster.dnsQuery(host);
    _loadHostInfo();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'DNS 查询成功' : 'DNS 查询失败')),
      );
    }
  }

  Future<void> _testAllLatency() async {
    setState(() => _isTestingLatency = true);
    await Hoster.testAllLatency();
    _loadHostInfo();
    setState(() => _isTestingLatency = false);
  }

  Future<void> _testSingleLatency(String host) async {
    await Hoster.testLatency(host);
    _loadHostInfo();
  }

  Future<void> _showEditIpDialog(String host) async {
    final currentCustomIp = Hoster.getCustomIp(host) ?? '';
    final controller = TextEditingController(text: currentCustomIp);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑 IP: $host'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '自定义 IP',
            hintText: '例如: 210.140.139.133',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(I18n.of(context).cancel),
          ),
          if (currentCustomIp.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('清除自定义'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(I18n.of(context).ok),
          ),
        ],
      ),
    );

    if (result != null) {
      await Hoster.setCustomIp(host, result);
      _loadHostInfo();
    }
  }

  Future<void> _saveDnsServers() async {
    final input = _dnsServersController.text.trim();
    if (input.isEmpty) {
      await Hoster.setDnsServers([]);
    } else {
      // 解析逗号分隔的服务器列表
      final servers = input
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      await Hoster.setDnsServers(servers);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.of(context).saved)),
      );
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
            const Padding(padding: EdgeInsets.symmetric(vertical: 5.0)),
            _buildSniBypassSwitch(),
            _buildImageSiteCard(),
            _buildDnsHostSettingsSection(),
          ],
        );
      }),
    );
  }

  // === UI 组件拆分 ===

  Widget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      iconTheme:
          IconThemeData(color: Theme.of(context).textTheme.bodyLarge!.color),
      automaticallyImplyLeading: _automaticallyImplyLeading,
      elevation: 0.0,
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        I18n.of(context).network,
        style: Theme.of(context).textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Text(
        I18n.of(context).network_tip,
        style: const TextStyle(fontSize: 12.0, color: Colors.grey),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSniBypassSwitch() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Observer(builder: (_) {
        return SwitchListTile(
          value: userSetting.disableBypassSni,
          activeColor: Theme.of(context).colorScheme.secondary,
          title: Text(I18n.of(context).disable_sni_bypass),
          subtitle: Text(I18n.of(context).disable_sni_bypass_message),
          onChanged: (value) => _handleSniBypassChange(value),
        );
      }),
    );
  }

  Future<void> _handleSniBypassChange(bool value) async {
    if (value) {
      final result = await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(I18n.of(context).please_note_that),
          content: Text(I18n.of(context).please_note_that_content),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(I18n.of(context).cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('OK'),
              child: Text(I18n.of(context).ok),
            ),
          ],
        ),
      );
      if (result == 'OK') {
        userSetting.setDisableBypassSni(value);
      }
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
          child: Column(
            children: [
              _buildImageSiteHeader(),
              _buildImageSiteOption(I18n.of(context).default_title, ImageHost),
              _buildImageSiteOption(ImageCatHost, ImageCatHost),
              _buildCustomHostInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSiteHeader() {
    return ListTile(
      title: Text(
        I18n.of(context).image_site,
        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge!.color),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.refresh_outlined),
        onPressed: () async {
          userSetting.setPictureSource(ImageHost);
          splashStore.setHost(ImageHost);
          splashStore.helloWord = "= w =";
          splashStore.maybeFetch();
        },
      ),
    );
  }

  Widget _buildImageSiteOption(String title, String source) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge!.color),
      ),
      selected: userSetting.pictureSource == source,
      selectedTileColor: Theme.of(context).colorScheme.secondary,
      onTap: () async {
        userSetting.setPictureSource(source);
        splashStore.setHost(source);
        if (source == ImageHost) {
          splashStore.helloWord = "= w =";
          splashStore.maybeFetch();
        }
      },
    );
  }

  Widget _buildCustomHostInput() {
    return ListTile(
      selected: userSetting.pictureSource != ImageHost &&
          userSetting.pictureSource != ImageCatHost,
      selectedTileColor: Theme.of(context).colorScheme.secondary,
      title: Theme(
        data: Theme.of(context)
            .copyWith(primaryColor: Theme.of(context).colorScheme.secondary),
        child: TextField(
          maxLines: 1,
          controller: _textEditingController,
          decoration: InputDecoration(
            hintText: 'Host',
            suffixIcon: IconButton(
              onPressed: _saveCustomHost,
              icon: const Icon(Icons.check, color: Colors.black),
            ),
            labelText: I18n.of(context).custom_host,
          ),
        ),
      ),
    );
  }

  Future<void> _saveCustomHost() async {
    if (_textEditingController.text.isEmpty) return;
    if (_textEditingController.text.trim().contains(" ")) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("illegal"),
        backgroundColor: Colors.red,
      ));
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
            ..._hostInfoList.map(_buildHostInfoTile).toList(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildDnsServersCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DNS 服务器 (多个用逗号分隔)',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
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
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: _saveDnsServers,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isRefreshingDns ? null : _refreshAllDns,
              icon: _isRefreshingDns
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('刷新全部 DNS'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isTestingLatency ? null : _testAllLatency,
              icon: _isTestingLatency
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speed),
              label: const Text('全部测速'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostInfoTile(HostResolveInfo info) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHostInfoHeader(info),
            const SizedBox(height: 8),
            _buildHostInfoDetails(info),
          ],
        ),
      ),
    );
  }

  Widget _buildHostInfoHeader(HostResolveInfo info) {
    return Row(
      children: [
        Expanded(
          child: Text(
            info.host,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.speed, size: 20),
          tooltip: '测速',
          onPressed: () => _testSingleLatency(info.host),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(8),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: '刷新 DNS',
          onPressed: () => _refreshSingleDns(info.host),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(8),
        ),
        IconButton(
          icon: const Icon(Icons.edit, size: 20),
          tooltip: '编辑 IP',
          onPressed: () => _showEditIpDialog(info.host),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(8),
        ),
      ],
    );
  }

  Widget _buildHostInfoDetails(HostResolveInfo info) {
    final defaultIp = Hoster.getDefaultIp(info.host);
    final dnsIp = Hoster.getDnsIp(info.host);
    final customIp = Hoster.getCustomIp(info.host);
    final latencyText = _getLatencyText(info);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 默认IP
        if (defaultIp != null && defaultIp.isNotEmpty)
          _buildIpRow('默认', defaultIp, Colors.grey, info.source == IpSource.defaultValue),
        // DNS IP
        if (dnsIp != null && dnsIp.isNotEmpty)
          _buildIpRow('DNS', dnsIp, Colors.blue, info.source == IpSource.dns),
        // 自定义IP
        if (customIp != null && customIp.isNotEmpty)
          _buildIpRow('自定义', customIp, Colors.green, info.source == IpSource.custom),
        // 延迟显示
        if (latencyText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _buildLatencyLabel(info),
          ),
      ],
    );
  }

  Widget _buildIpRow(String label, String ip, Color color, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(isActive ? 0.3 : 0.1),
              borderRadius: BorderRadius.circular(4),
              border: isActive ? Border.all(color: color, width: 1.5) : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              ip,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: isActive
                    ? Theme.of(context).textTheme.bodyMedium?.color
                    : Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.5),
                fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
          if (isActive)
            const Icon(Icons.check_circle, size: 16, color: Colors.green),
        ],
      ),
    );
  }

  String _getLatencyText(HostResolveInfo info) {
    if (info.latency == null) return '';
    if (info.latency! < 0) return '超时';
    return '${info.latency}ms';
  }

  Widget _buildLatencyLabel(HostResolveInfo info) {
    final latencyText = _getLatencyText(info);
    Color color;

    if (info.latency == null || info.latency! < 0) {
      color = Colors.red;
    } else if (info.latency! < 100) {
      color = Colors.green;
    } else if (info.latency! < 300) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        latencyText,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
