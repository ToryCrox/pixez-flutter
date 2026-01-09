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
  /// 代码硬编码默认值
  defaultValue,
  /// DoH DNS查询结果
  dns,
  /// 用户自定义
  custom,
}

/// 域名解析信息
class HostResolveInfo {
  final String host;
  final String ip;
  final IpSource source;
  final int? latency; // 延迟 (ms)，null表示未测试

  HostResolveInfo({
    required this.host,
    required this.ip,
    required this.source,
    this.latency,
  });

  HostResolveInfo copyWith({
    String? host,
    String? ip,
    IpSource? source,
    int? latency,
  }) {
    return HostResolveInfo(
      host: host ?? this.host,
      ip: ip ?? this.ip,
      source: source ?? this.source,
      latency: latency ?? this.latency,
    );
  }
}

class Hoster {
  // === 分层存储 ===
  /// 默认硬编码IP
  static final Map<String, String> _constMap = {
    'app-api.pixiv.net': '210.140.139.155',
    'oauth.secure.pixiv.net': '210.140.139.155',
    ImageHost: '210.140.139.133',  // i.pximg.net
    ImageSHost: '210.140.139.133', // s.pximg.net
  };

  /// DNS查询结果IP
  static final Map<String, String> _dnsMap = {};

  /// 用户自定义IP
  static final Map<String, String> _customMap = {};

  /// 延迟缓存
  static final Map<String, int> _latencyMap = {};

  // === DNS服务器配置 ===
  /// 默认DNS服务器列表（可以是域名或IP）
  static const List<String> defaultDnsServers = ['223.5.5.5'];

  /// 获取当前DNS服务器列表
  static List<String> get dnsServers {
    final saved = Prefer.getStringList('config_dns_servers');
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
    return defaultDnsServers;
  }

  /// 设置DNS服务器列表
  static Future<void> setDnsServers(List<String> servers) async {
    if (servers.isEmpty) {
      await Prefer.remove('config_dns_servers');
    } else {
      await Prefer.setStringList('config_dns_servers', servers);
    }
  }

  /// 需要查询的域名列表
  static final List<String> QUERY_HOST = [
    ImageHost,
    ImageSHost,
    'app-api.pixiv.net',
    'oauth.secure.pixiv.net',
  ];

  // === DNS查询专用Dio客户端 ===
  static Dio? _dnsClient;

  /// 获取DNS查询专用的Dio客户端（普通Dio，不使用Rhttp）
  static Dio get dnsClient {
    _dnsClient ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    return _dnsClient!;
  }

  // === 用于其他网络请求的Rhttp客户端 ===
  static r.RhttpCompatibleClient? compatibleClient;

  // === 初始化 ===
  /// 从持久化存储加载配置
  static Future<void> initMap() async {
    try {
      for (var host in QUERY_HOST) {
        // 加载DNS查询结果
        final dnsIp = Prefer.getString('h_dns_$host');
        if (dnsIp != null && dnsIp.isNotEmpty) {
          _dnsMap[host] = dnsIp;
        }
        // 加载用户自定义IP
        final customIp = Prefer.getString('h_custom_$host');
        if (customIp != null && customIp.isNotEmpty) {
          _customMap[host] = customIp;
        }
        // 兼容旧数据：尝试迁移 h_hoster_$host 到 h_dns_$host
        if (_dnsMap[host] == null) {
          final oldIp = Prefer.getString('h_hoster_$host');
          if (oldIp != null && oldIp.isNotEmpty) {
            _dnsMap[host] = oldIp;
            await Prefer.setString('h_dns_$host', oldIp);
            Log.d(() => 'Migrated old host config: $host -> $oldIp');
          }
        }
      }
    } catch (e) {
      Log.e('Failed to init Hoster map', error: e);
    }
  }

  // === IP获取（按优先级：自定义 > DNS > 默认）===
  /// 获取指定域名的解析信息
  static HostResolveInfo getResolveInfo(String host) {
    // 优先级1: 自定义IP
    if (_customMap.containsKey(host) && _customMap[host]!.isNotEmpty) {
      return HostResolveInfo(
        host: host,
        ip: _customMap[host]!,
        source: IpSource.custom,
        latency: _latencyMap[host],
      );
    }
    // 优先级2: DNS查询结果
    if (_dnsMap.containsKey(host) && _dnsMap[host]!.isNotEmpty) {
      return HostResolveInfo(
        host: host,
        ip: _dnsMap[host]!,
        source: IpSource.dns,
        latency: _latencyMap[host],
      );
    }
    // 优先级3: 默认值
    return HostResolveInfo(
      host: host,
      ip: _constMap[host] ?? '',
      source: IpSource.defaultValue,
      latency: _latencyMap[host],
    );
  }

  /// 获取指定域名的IP（简化接口）
  static String getIp(String host) {
    return getResolveInfo(host).ip;
  }

  /// 获取所有域名的解析信息
  static List<HostResolveInfo> getAllResolveInfo() {
    return QUERY_HOST.map((host) => getResolveInfo(host)).toList();
  }

  // === 自定义IP管理 ===
  /// 设置指定域名的自定义IP
  static Future<void> setCustomIp(String host, String ip) async {
    if (ip.isEmpty) {
      _customMap.remove(host);
      await Prefer.remove('h_custom_$host');
    } else {
      _customMap[host] = ip;
      await Prefer.setString('h_custom_$host', ip);
    }
  }

  /// 获取指定域名的自定义IP（可能为null）
  static String? getCustomIp(String host) {
    return _customMap[host];
  }

  /// 获取指定域名的DNS查询IP（可能为null）
  static String? getDnsIp(String host) {
    return _dnsMap[host];
  }

  /// 获取指定域名的默认IP
  static String? getDefaultIp(String host) {
    return _constMap[host];
  }

  // === DNS查询 ===
  /// 查询所有域名的DNS
  static Future<void> dnsQueryAll() async {
    for (var host in QUERY_HOST) {
      await dnsQuery(host);
    }
  }

  /// 查询指定域名的DNS（使用配置的DNS服务器列表，依次尝试直到成功）
  static Future<bool> dnsQuery(String name) async {
    final servers = dnsServers;
    for (final server in servers) {
      final success = await _dnsQueryWithServer(name, server);
      if (success) return true;
    }
    return false;
  }

  /// 使用指定DNS服务器查询域名
  static Future<bool> _dnsQueryWithServer(String name, String server) async {
    try {
      // 构建DNS API地址，支持域名或IP
      final apiUrl = 'http://$server/resolve';
      Log.d(() => 'DNS query: $name via $apiUrl');

      Response response = await dnsClient.get(
        apiUrl,
        options: Options(
          headers: {'accept': 'application/dns-json'},
        ),
        queryParameters: {'name': name, 'type': 'A'},
      );

      final data = response.data is String
          ? jsonDecode(response.data)
          : response.data;
      OnezeroResponse model = OnezeroResponse.fromJson(data);

      if (model.answer.isEmpty) {
        Log.w(() => 'DNS query returned no answers for $name');
        return false;
      }

      final answer = model.answer.toList();
      answer.sort((l, r) => r.ttl.compareTo(l.ttl));
      final ip = answer.first.data;

      // 验证IP格式
      if (_isValidIpv4(ip)) {
        _dnsMap[name] = ip;
        await Prefer.setString('h_dns_$name', ip);
        Log.d(() => 'DNS resolved: $name -> $ip');
        return true;
      } else {
        Log.w(() => 'Invalid IP format from DNS: $ip');
        return false;
      }
    } catch (e) {
      Log.e('Failed to query DNS for $name via $server', error: e);
      return false;
    }
  }

  /// 验证IPv4格式
  static bool _isValidIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final num = int.tryParse(part);
      return num != null && num >= 0 && num <= 255;
    });
  }

  // === 连通性测试 ===
  /// 测试指定域名的连通性，返回延迟(ms)，失败返回-1
  static Future<int> testLatency(String host) async {
    final ip = getIp(host);
    if (ip.isEmpty) return -1;

    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(
        ip,
        443,
        timeout: const Duration(seconds: 5),
      );
      stopwatch.stop();
      await socket.close();

      final latency = stopwatch.elapsedMilliseconds;
      Log.d(() => 'Latency test: $host ($ip) -> $latency ms');
      _latencyMap[host] = latency;
      return latency;
    } catch (e) {
      Log.e('Latency test failed for $host ($ip)', error: e);
      _latencyMap[host] = -1;
      return -1;
    }
  }

  /// 测试所有域名的连通性
  static Future<Map<String, int>> testAllLatency() async {
    final results = <String, int>{};
    for (var host in QUERY_HOST) {
      results[host] = await testLatency(host);
    }
    return results;
  }

  // === 兼容旧接口 ===
  /// 兼容旧代码：DNS查询（用于 fetcher.dart）
  static Future<void> dnsQueryFetcher() async {
    for (var key in [ImageHost, ImageSHost]) {
      await dnsQuery(key);
    }
  }

  /// 兼容旧代码：返回当前生效的IP映射（用于 weiss_plugin.dart）
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

  static String host(String url) {
    return splashStore.host;
  }

  /// 创建图片请求的 ClientSettings（用于 i.pximg.net 和 s.pximg.net）
  static r.ClientSettings? createImageClientSettings() {
    if (userSetting.disableBypassSni) return null;

    return r.ClientSettings(
      tlsSettings: r.TlsSettings(verifyCertificates: false, sni: false),
      dnsSettings: r.DnsSettings.dynamic(
        resolver: (host) async {
          if (host == 'i.pximg.net') {
            return [iPximgNet()];
          }
          if (host == 's.pximg.net') {
            return [sPximgNet()];
          }
          return await InternetAddress.lookup(host)
              .then((value) => value.map((e) => e.address).toList());
        },
      ),
    );
  }

  /// 创建 API 请求的 ClientSettings（用于 app-api.pixiv.net）
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

  /// 创建 OAuth 请求的 ClientSettings（用于 oauth.secure.pixiv.net）
  static r.ClientSettings? createOAuthClientSettings() {
    if (userSetting.disableBypassSni) return null;

    return r.ClientSettings(
      tlsSettings: r.TlsSettings(verifyCertificates: false, sni: false),
      dnsSettings: r.DnsSettings.dynamic(
        resolver: (host) async {
          final ip = oauth();
          return [ip];
        },
      ),
    );
  }

  static Map<String, String> header({String? url}) {
    Map<String, String> map = {
      "referer": "https://app-api.pixiv.net/",
      "User-Agent": "PixivIOSApp/5.8.0",
    };
    return map;
  }
}
