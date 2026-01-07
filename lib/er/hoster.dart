import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio_compatibility_layer/dio_compatibility_layer.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/onezero_response.dart';
import 'package:pixez/debug/mana_manager.dart';
import 'package:rhttp/rhttp.dart' as r;

class Hoster {
  static Map<String, dynamic> _map = Map();
  static Map<String, dynamic> _constMap = {
    "app-api.pixiv.net": "210.140.139.155",
    "oauth.secure.pixiv.net": "210.140.139.155",
    "i.pximg.net": "210.140.139.133",
    "s.pximg.net": "210.140.139.133",
    "doh": "doh.dns.sb",
  };
  static Map<String, dynamic> hardMap() {
    return _map.isEmpty ? _constMap : _map;
  }

  static final List<String> QUERY_HOST = [
    ImageHost,
    ImageSHost,
    'app-api.pixiv.net',
    'oauth.secure.pixiv.net',
  ];

  static Dio httpClient = Dio(
    BaseOptions(
      baseUrl: 'https://1.1.1.1',
    ),
  );
  static r.RhttpCompatibleClient? compatibleClient;

  static Future<Dio> createDioClient() async {
    if (compatibleClient == null) {
      // 添加 Mana Dio 拦截器（网络请求追踪）
      final manaInterceptor = ManaManager.instance.dioInterceptor;
      if (manaInterceptor != null && !httpClient.interceptors.any((i) => i == manaInterceptor)) {
        httpClient.interceptors.add(manaInterceptor);
      }
      return httpClient;
    }
    compatibleClient ??= await r.RhttpCompatibleClient.create(
        settings: userSetting.disableBypassSni
            ? null
            : r.ClientSettings(
                tlsSettings:
                    r.TlsSettings(verifyCertificates: false, sni: false),
              ));
    httpClient.httpClientAdapter = ConversionLayerAdapter(compatibleClient!);
    return httpClient;
  }

  static Future<void> dnsQueryAll() async {
    for (var key in [ImageHost, ImageSHost]) {
      await dnsQuery(key);
    }
  }

  static Future<void> dnsQueryFetcher() async {
    for (var key in [ImageHost, ImageSHost]) {
      await dnsQuery(key);
    }
  }

  static Future<void> initMap() async {
    try {
      for (var key in QUERY_HOST) {
        final value = Prefer.getString('h_hoster_$key');
        if (value != null) {
          _map[key] = value;
        }
      }
    } catch (e) {
      Log.e('Failed to init Hoster map', error: e);
    }
  }

  static Future<void> dnsQuery(String name) async {
    try {
      await createDioClient();
      Response response = await httpClient.get('/dns-query',
          options: Options(
            headers: {
              'accept': 'application/dns-json',
            },
          ),
          queryParameters: {'name': name});
      OnezeroResponse model =
          OnezeroResponse.fromJson(jsonDecode(response.data));
      final answer = model.answer.toList();
      answer.sort((l, r) => r.ttl.compareTo(l.ttl));
      final host = answer.first.data;
      if (host.contains('.')) {
        final num = host.split('.');
        bool allNum = num.every((element) => int.tryParse(element) != null);
        if (allNum) {
          _map[name] = host;
          Prefer.setString('h_hoster_$name', host);
        }
      }
      Log.d(() => host);
    } catch (e) {
      Log.e('Failed to query DNS', error: e);
    }
  }

  static String iPximgNet() {
    final key = "i.pximg.net";
    final result = _map[key];
    if (result == null) return _constMap[key];
    return result;
  }

  static String sPximgNet() {
    final key = "s.pximg.net";
    final result = _map[key];
    if (result == null) return _constMap[key];
    return result;
  }

  static String doh() {
    final key = "doh";
    final result = _map[key];
    if (result == null) return _constMap[key];
    return result;
  }

  static String oauth() {
    final key = "oauth.secure.pixiv.net";
    final result = _map[key];
    if (result == null) return _constMap[key];
    return result;
  }

  static String api() {
    final key = "app-api.pixiv.net";
    final result = _map[key];
    if (result == null) return _constMap[key];
    return result;
  }

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
