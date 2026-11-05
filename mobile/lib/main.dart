import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';
import 'package:ip_joker/proxy_link.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IpJokerApp());
}

class IpJokerApp extends StatelessWidget {
  const IpJokerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IP JOKER',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFFe53935)),
        home: const IpJokerHome(),
      );
}

class IpJokerHome extends StatefulWidget {
  const IpJokerHome({super.key});

  @override
  State<IpJokerHome> createState() => _IpJokerHomeState();
}

class _IpJokerHomeState extends State<IpJokerHome> {
  late final WebViewController controller;
  bool ready = false;
  bool nativeReady = false;
  Object? startupError;
  Future<void> _vpnQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'IPJokerNative',
        onMessageReceived: (message) => _handle(message.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => ready = true);
          _showStartupError();
        },
        onWebResourceError: (error) {
          debugPrint('IP JOKER WebView: ${error.description}');
        },
      ))
      ..loadFlutterAsset('assets/index.html');
    _initializeNative();
  }

  Future<void> _initializeNative() async {
    try {
      await SingBox.instance.initialize(const SingBoxOptions(
        logMaxLines: 300,
        android: SingBoxAndroidOptions(
          notificationTitle: 'IP JOKER',
          showTrafficInNotification: true,
          stopActionTitle: 'قطع اتصال',
        ),
      ));
      nativeReady = true;
    } catch (error) {
      startupError = error;
      debugPrint('IP JOKER sing-box init failed: $error');
    }
    if (mounted) setState(() {});
    _showStartupError();
  }

  Future<void> _showStartupError() async {
    if (!ready || startupError == null) return;
    await controller.runJavaScript(
      'window.__ipjokerStartupError && window.__ipjokerStartupError(${jsonEncode(startupError.toString())});',
    );
  }

  Future<void> _reply(String id, Map<String, dynamic> result) async {
    final idLiteral = jsonEncode(id);
    final resultLiteral = jsonEncode(jsonEncode(result));
    try {
      await controller.runJavaScript(
        'window.__ipjokerResolve && window.__ipjokerResolve($idLiteral, $resultLiteral);',
      );
    } catch (error) {
      debugPrint('IP JOKER reply failed: $error');
    }
  }

  Future<Map<String, dynamic>> _probeHttpProxy(String host, int port) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2)
      ..idleTimeout = const Duration(seconds: 1)
      ..maxConnectionsPerHost = 1
      ..findProxy = (_) => 'PROXY $host:$port';
    final watch = Stopwatch()..start();
    try {
      // HTTPS request forces an HTTP CONNECT tunnel. The platform TLS stack
      // negotiates the strongest mutually supported version (TLS 1.3/1.2).
      final request = await client
          .getUrl(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 3));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'IP-JOKER-Proxy-Check/2.0');
      final response = await request.close().timeout(const Duration(seconds: 3));
      final status = response.statusCode;
      await response.drain<void>().timeout(const Duration(seconds: 1));
      return {
        'ok': status == HttpStatus.noContent || (status >= 200 && status < 400),
        'status': status,
        'ms': watch.elapsedMilliseconds,
        'message': status == HttpStatus.noContent || (status >= 200 && status < 400)
            ? 'تونل CONNECT و درخواست HTTPS موفق بود'
            : 'پاسخ مقصد نامعتبر بود: HTTP $status',
      };
    } catch (error) {
      return {
        'ok': false,
        'ms': watch.elapsedMilliseconds,
        'message': error.toString(),
      };
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _fetchText(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('آدرس منبع معتبر نیست');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 2)
      ..userAgent = 'IP-JOKER/1.0';
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      request.followRedirects = true;
      final response = await request.close().timeout(const Duration(seconds: 7));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {'ok': false, 'status': response.statusCode, 'text': ''};
      }
      if (response.contentLength > 2 * 1024 * 1024) {
        return {'ok': false, 'status': response.statusCode, 'text': '', 'message': 'فایل منبع بیش از حد بزرگ است'};
      }
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 7));
      return {'ok': true, 'status': response.statusCode, 'text': text};
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _handle(String raw) async {
    var id = '0';
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      id = data['id']?.toString() ?? '0';
      final action = data['action'] as String? ?? '';
      final args = (data['args'] as Map?)?.cast<String, dynamic>() ?? {};

      switch (action) {
        case 'fetchText':
          final result = await _fetchText((args['url'] ?? '').toString());
          await _reply(id, result);
          break;

        case 'probeProxy':
          final host = (args['host'] ?? '').toString().trim();
          final port = int.tryParse((args['port'] ?? '').toString()) ?? 0;
          final type = (args['type'] ?? 'HTTP').toString().toUpperCase();
          if (type != 'HTTP') {
            await _reply(id, {
              'ok': false,
              'message': 'تست زندهٔ خودکار فعلاً فقط برای پروکسی HTTP پشتیبانی می‌شود',
            });
          } else if (host.isEmpty || port < 1 || port > 65535) {
            await _reply(id, {'ok': false, 'message': 'IP یا پورت نامعتبر است'});
          } else {
            await _reply(id, await _probeHttpProxy(host, port));
          }
          break;

        case 'connect':
          final host = (args['host'] ?? '').toString();
          final port = int.tryParse((args['port'] ?? '').toString()) ?? 0;
          final type = (args['type'] ?? 'HTTP').toString();
          final proxyLink = buildProxyLink(host: host, port: port, type: type);
          await SingBox.instance.requestNotificationPermission();
          await _serializeVpn(() => SingBox.instance.connect(proxyLink));
          await _reply(id, {
            'ok': true,
            'connected': SingBox.instance.status.isActive,
            'message': 'تونل VPN برقرار شد',
          });
          break;

        case 'disconnect':
          await _serializeVpn(() => SingBox.instance.disconnect());
          await _reply(id, {
            'ok': true,
            'connected': false,
            'message': 'اتصال VPN قطع شد',
          });
          break;

        case 'status':
          final status = SingBox.instance.status;
          await _reply(id, {
            'ok': true,
            'connected': status.isActive,
            'message': status.name,
          });
          break;

        case 'save':
          await _reply(id, {'ok': true, 'message': 'پروفایل در حافظهٔ برنامه ذخیره شد'});
          break;

        default:
          await _reply(id, {'ok': false, 'message': 'درخواست ناشناخته است'});
      }
    } on SingBoxException catch (error) {
      await _reply(id, {'ok': false, 'message': error.message});
    } catch (error) {
      debugPrint('IP JOKER action error: $error');
      await _reply(id, {'ok': false, 'message': error.toString()});
    }
  }

  Future<void> _serializeVpn(Future<void> Function() operation) {
    final next = _vpnQueue.then((_) => operation());
    _vpnQueue = next.catchError((Object _) {});
    return next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: controller),
              if (!ready || !nativeReady && startupError == null)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      );
}
