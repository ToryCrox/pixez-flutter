import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/onezero_response.dart';
import 'package:rhttp/rhttp.dart' as r;

// === 图片Host常量 ===
const ImageHost = "i.pximg.net";
const ImageCatHost = "i.pixiv.re";
const ImageSHost = "s.pximg.net";

/// IP来源类型
enum IpSource {
  defaultValue,
  dns,
  custom,
}

/// 单个IP的信息（含延迟）
class IpInfo {
  final String ip;
  final int? latency; // null=未测试, -1=超时

  IpInfo(this.ip, {this.latency});

  IpInfo copyWith({String? ip, int? latency}) {
    return IpInfo(ip ?? this.ip, latency: latency ?? this.latency);
  }
}

/// 域名的完整解析信息（包含多来源多IP）
class HostInfo {
  final String host;
  final List<IpInfo> defaultIps;
  final List<IpInfo> dnsIps;
  final List<IpInfo> customIps;
  final IpSource selectedSource;
  final int selectedIndex; // 在选中来源的IP列表中的索引

  HostInfo({
    required this.host,
    this.defaultIps = const [],
    this.dnsIps = const [],
    this.customIps = const [],
    this.selectedSource = IpSource.defaultValue,
    this.selectedIndex = 0,
  });

  /// 获取当前生效的IP
  String get activeIp {
    final list = _getListBySource(selectedSource);
    if (list.isEmpty) {
      // 回退到有数据的来源
      if (customIps.isNotEmpty) return customIps.first.ip;
      if (dnsIps.isNotEmpty) return dnsIps.first.ip;
      if (defaultIps.isNotEmpty) return defaultIps.first.ip;
      return '';
    }
    final idx = selectedIndex.clamp(0, list.length - 1);
    return list[idx].ip;
  }

  List<IpInfo> _getListBySource(IpSource source) {
    switch (source) {
      case IpSource.custom:
        return customIps;
      case IpSource.dns:
        return dnsIps;
      case IpSource.defaultValue:
        return defaultIps;
    }
  }
}

class Hoster {
  // === 分层存储 ===
  static final Map<String, List<String>> _defaultMap = {
    'app-api.pixiv.net': ['210.140.139.155'],
    'oauth.secure.pixiv.net': ['210.140.139.155'],
    ImageHost: ['210.140.139.133'],
    ImageSHost: ['210.140.139.133'],
  };

  static final Map<String, List<String>> _dnsMap = {};
  static final Map<String, List<String>> _customMap = {};

  // 延迟缓存: host -> ip -> latency
  static final Map<String, Map<String, int>> _latencyMap = {};

  // 选择记录
  static final Map<String, IpSource> _selectedSourceMap = {};
  static final Map<String, int> _selectedIndexMap = {};

  // === DNS服务器配置 ===
  static const List<String> defaultDnsServers = ['223.5.5.5'];

  static List<String> get dnsServers {
    final saved = Prefer.getStringList('config_dns_servers');
    if (saved != null && saved.isNotEmpty) return saved;
    return defaultDnsServers;
  }

  static Future<void> setDnsServers(List<String> servers) async {
    if (servers.isEmpty) {
      await Prefer.remove('config_dns_servers');
    } else {
      await Prefer.setStringList('config_dns_servers', servers);
    }
  }

  static final List<String> QUERY_HOST = [
    ImageHost,
    ImageSHost,
    'app-api.pixiv.net',
    'oauth.secure.pixiv.net',
  ];

  // === DNS查询客户端 ===
  static Dio? _dnsClient;
  static Dio get dnsClient {
    _dnsClient ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    return _dnsClient!;
  }

  static r.RhttpCompatibleClient? compatibleClient;

  // === 初始化 ===
  static Future<void> initMap() async {
    try {
      for (var host in QUERY_HOST) {
        // 加载DNS IP列表
        final dnsIps = Prefer.getStringList('h_dns_list_$host');
        if (dnsIps != null && dnsIps.isNotEmpty) {
          _dnsMap[host] = dnsIps;
        }
        // 加载自定义IP列表
        final customIps = Prefer.getStringList('h_custom_list_$host');
        if (customIps != null && customIps.isNotEmpty) {
          _customMap[host] = customIps;
        }
        // 加载选择记录
        final sourceIdx = Prefer.getInt('h_selected_source_$host');
        if (sourceIdx != null) {
          _selectedSourceMap[host] = IpSource.values[sourceIdx.clamp(0, 2)];
        }
        final ipIdx = Prefer.getInt('h_selected_index_$host');
        if (ipIdx != null) {
          _selectedIndexMap[host] = ipIdx;
        }
        // 加载延迟缓存
        final latencyJson = Prefer.getString('h_latency_$host');
        if (latencyJson != null && latencyJson.isNotEmpty) {
          try {
            final map = jsonDecode(latencyJson) as Map<String, dynamic>;
            _latencyMap[host] = map.map((k, v) => MapEntry(k, v as int));
          } catch (_) {}
        }
        // 兼容旧数据迁移
        if (_dnsMap[host] == null || _dnsMap[host]!.isEmpty) {
          final oldIp = Prefer.getString('h_dns_$host') ?? Prefer.getString('h_hoster_$host');
          if (oldIp != null && oldIp.isNotEmpty) {
            _dnsMap[host] = [oldIp];
            await Prefer.setStringList('h_dns_list_$host', [oldIp]);
          }
        }
        if (_customMap[host] == null || _customMap[host]!.isEmpty) {
          final oldCustom = Prefer.getString('h_custom_$host');
          if (oldCustom != null && oldCustom.isNotEmpty) {
            _customMap[host] = [oldCustom];
            await Prefer.setStringList('h_custom_list_$host', [oldCustom]);
          }
        }
      }
    } catch (e) {
      Log.e('Failed to init Hoster map', error: e);
    }
  }

  // === 获取完整信息 ===
  static HostInfo getHostInfo(String host) {
    final defaultIps = (_defaultMap[host] ?? [])
        .map((ip) => IpInfo(ip, latency: _latencyMap[host]?[ip]))
        .toList();
    final dnsIps = (_dnsMap[host] ?? [])
        .map((ip) => IpInfo(ip, latency: _latencyMap[host]?[ip]))
        .toList();
    final customIps = (_customMap[host] ?? [])
        .map((ip) => IpInfo(ip, latency: _latencyMap[host]?[ip]))
        .toList();

    var selectedSource = _selectedSourceMap[host] ?? IpSource.defaultValue;
    // 自动回退：如果选中的来源没有IP，回退到有IP的来源
    if (_getIpList(host, selectedSource).isEmpty) {
      if (customIps.isNotEmpty) {
        selectedSource = IpSource.custom;
      } else if (dnsIps.isNotEmpty) {
        selectedSource = IpSource.dns;
      } else {
        selectedSource = IpSource.defaultValue;
      }
    }

    return HostInfo(
      host: host,
      defaultIps: defaultIps,
      dnsIps: dnsIps,
      customIps: customIps,
      selectedSource: selectedSource,
      selectedIndex: _selectedIndexMap[host] ?? 0,
    );
  }

  static List<String> _getIpList(String host, IpSource source) {
    switch (source) {
      case IpSource.custom:
        return _customMap[host] ?? [];
      case IpSource.dns:
        return _dnsMap[host] ?? [];
      case IpSource.defaultValue:
        return _defaultMap[host] ?? [];
    }
  }

  static List<HostInfo> getAllHostInfo() {
    return QUERY_HOST.map((host) => getHostInfo(host)).toList();
  }

  /// 获取当前生效的IP（简化接口）
  static String getIp(String host) {
    return getHostInfo(host).activeIp;
  }

  // === 选择管理 ===
  static Future<void> setSelectedSource(String host, IpSource source, {int index = 0}) async {
    _selectedSourceMap[host] = source;
    _selectedIndexMap[host] = index;
    await Prefer.setInt('h_selected_source_$host', source.index);
    await Prefer.setInt('h_selected_index_$host', index);
  }

  // === 自定义IP管理 ===
  static List<String> getCustomIps(String host) => _customMap[host] ?? [];

  static Future<void> addCustomIp(String host, String ip) async {
    if (ip.isEmpty || !_isValidIpv4(ip)) return;
    _customMap[host] ??= [];
    if (!_customMap[host]!.contains(ip)) {
      _customMap[host]!.add(ip);
      await Prefer.setStringList('h_custom_list_$host', _customMap[host]!);
    }
  }

  static Future<void> removeCustomIp(String host, String ip) async {
    _customMap[host]?.remove(ip);
    await Prefer.setStringList('h_custom_list_$host', _customMap[host] ?? []);
  }

  static Future<void> setCustomIps(String host, List<String> ips) async {
    final validIps = ips.where((ip) => _isValidIpv4(ip)).toList();
    _customMap[host] = validIps;
    await Prefer.setStringList('h_custom_list_$host', validIps);
  }

  // === DNS查询 ===
  static Future<void> dnsQueryAll() async {
    for (var host in QUERY_HOST) {
      await dnsQuery(host);
    }
  }

  static Future<bool> dnsQuery(String name) async {
    final servers = dnsServers;
    for (final server in servers) {
      final success = await _dnsQueryWithServer(name, server);
      if (success) return true;
    }
    return false;
  }

  static Future<bool> _dnsQueryWithServer(String name, String server) async {
    try {
      final apiUrl = 'http://$server/resolve';
      Log.d(() => 'DNS query: $name via $apiUrl');

      Response response = await dnsClient.get(
        apiUrl,
        options: Options(headers: {'accept': 'application/dns-json'}),
        queryParameters: {'name': name, 'type': 'A'},
      );

      final data = response.data is String ? jsonDecode(response.data) : response.data;
      OnezeroResponse model = OnezeroResponse.fromJson(data);

      if (model.answer.isEmpty) return false;

      // 收集所有A记录IP
      final ips = model.answer
          .where((a) => _isValidIpv4(a.data))
          .map((a) => a.data)
          .toSet()
          .toList();

      if (ips.isNotEmpty) {
        _dnsMap[name] = ips;
        await Prefer.setStringList('h_dns_list_$name', ips);
        Log.d(() => 'DNS resolved: $name -> $ips');
        return true;
      }
      return false;
    } catch (e) {
      Log.e('Failed to query DNS for $name via $server', error: e);
      return false;
    }
  }

  static bool _isValidIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final num = int.tryParse(part);
      return num != null && num >= 0 && num <= 255;
    });
  }

  // === 延迟测试 ===
  static Future<int> testIpLatency(String ip) async {
    if (ip.isEmpty) return -1;
    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(ip, 443, timeout: const Duration(seconds: 5));
      stopwatch.stop();
      await socket.close();
      final latency = stopwatch.elapsedMilliseconds;
      Log.d(() => 'Latency test: $ip -> $latency ms');
      return latency;
    } catch (e) {
      Log.e('Latency test failed for $ip', error: e);
      return -1;
    }
  }

  static Future<void> testAllIpsForHost(String host) async {
    _latencyMap[host] ??= {};
    final allIps = <String>{
      ...(_defaultMap[host] ?? []),
      ...(_dnsMap[host] ?? []),
      ...(_customMap[host] ?? []),
    };
    for (final ip in allIps) {
      final latency = await testIpLatency(ip);
      _latencyMap[host]![ip] = latency;
    }
    // 持久化延迟缓存
    await _saveLatencyCache(host);
  }

  static Future<void> _saveLatencyCache(String host) async {
    final map = _latencyMap[host];
    if (map != null && map.isNotEmpty) {
      await Prefer.setString('h_latency_$host', jsonEncode(map));
    }
  }

  static Future<void> testAllLatency() async {
    for (var host in QUERY_HOST) {
      await testAllIpsForHost(host);
    }
  }

  // === 兼容旧接口 ===
  static Future<void> dnsQueryFetcher() async {
    for (var key in [ImageHost, ImageSHost]) {
      await dnsQuery(key);
    }
  }

  static Map<String, dynamic> hardMap() {
    final result = <String, dynamic>{};
    for (var host in QUERY_HOST) {
      result[host] = getIp(host);
    }
    return result;
  }

  static String iPximgNet() => getIp("i.pximg.net");
  static String sPximgNet() => getIp("s.pximg.net");
  static String oauth() => getIp("oauth.secure.pixiv.net");
  static String api() => getIp("app-api.pixiv.net");

  static String host(String url) => splashStore.host;

  // === ClientSettings ===
  static r.ClientSettings? createImageClientSettings() {
    if (userSetting.disableBypassSni) return null;
    return r.ClientSettings(
      tlsSettings: r.TlsSettings(verifyCertificates: false, sni: false),
      dnsSettings: r.DnsSettings.dynamic(
        resolver: (host) async {
          if (host == 'i.pximg.net') return [iPximgNet()];
          if (host == 's.pximg.net') return [sPximgNet()];
          return await InternetAddress.lookup(host).then((v) => v.map((e) => e.address).toList());
        },
      ),
    );
  }

  static r.ClientSettings? createApiClientSettings() {
    if (userSetting.disableBypassSni) return null;
    return r.ClientSettings(
      tlsSettings: r.TlsSettings(verifyCertificates: false, sni: false),
      dnsSettings: r.DnsSettings.dynamic(
        resolver: (host) async {
          final ip = api();
          Log.d(() => "api ip: $ip");
          return [ip];
        },
      ),
    );
  }

  static r.ClientSettings? createOAuthClientSettings() {
    if (userSetting.disableBypassSni) return null;
    return r.ClientSettings(
      tlsSettings: r.TlsSettings(verifyCertificates: false, sni: false),
      dnsSettings: r.DnsSettings.dynamic(
        resolver: (host) async => [oauth()],
      ),
    );
  }

  static Map<String, String> header({String? url}) {
    return {
      "referer": "https://app-api.pixiv.net/",
      "User-Agent": "PixivIOSApp/5.8.0",
    };
  }
}
