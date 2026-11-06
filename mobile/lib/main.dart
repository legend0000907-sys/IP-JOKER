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

  Future<Map<String, dynamic>> _probeProxy(String host, int port, String type) async {
    final watch = Stopwatch()..start();
    Socket? socket;
    try {
      const targetHost = 'www.gstatic.com';
      const targetPort = 443;
      final kind = type.toUpperCase();
      if (kind == 'SOCKS5') {
        socket = await Socket.connect(host, port, timeout: const Duration(seconds: 4));
        final reader = _SocketReader(socket);
        socket.add([0x05, 0x01, 0x00]);
        await socket.flush();
        final greeting = await reader.readExact(2).timeout(const Duration(seconds: 3));
        if (greeting[0] != 0x05 || greeting[1] != 0x00) throw const FormatException('SOCKS5 no-auth negotiation failed');
        final domain = utf8.encode(targetHost);
        socket.add([0x05, 0x01, 0x00, 0x03, domain.length, ...domain, 0x01, 0xBB]);
        await socket.flush();
        final head = await reader.readExact(4).timeout(const Duration(seconds: 4));
        if (head[0] != 0x05 || head[1] != 0x00) throw FormatException('SOCKS5 CONNECT rejected (code ${head[1]})');
        final atyp = head[3];
        final addrLen = atyp == 0x01 ? 4 : atyp == 0x04 ? 16 : atyp == 0x03 ? (await reader.readExact(1)).first : -1;
        if (addrLen < 0) throw const FormatException('Invalid SOCKS5 address type');
        await reader.readExact(addrLen + 2).timeout(const Duration(seconds: 3));
      } else if (kind == 'HTTP' || kind == 'HTTPS') {
        if (kind == 'HTTPS') {
          socket = await SecureSocket.connect(host, port, timeout: const Duration(seconds: 5), supportedProtocols: const ['http/1.1']);
        } else {
          socket = await Socket.connect(host, port, timeout: const Duration(seconds: 4));
        }
        final reader = _SocketReader(socket);
        socket.add(utf8.encode('CONNECT $targetHost:$targetPort HTTP/1.1\r\nHost: $targetHost:$targetPort\r\nUser-Agent: IP-JOKER-Proxy-Check/3.0\r\nProxy-Connection: close\r\n\r\n'));
        await socket.flush();
        final header = utf8.decode(await reader.readHeader().timeout(const Duration(seconds: 5)), allowMalformed: true);
        final firstLine = header.split('\r\n').first;
        if (!RegExp(r'^HTTP/1\.[01] 200(?: |$)').hasMatch(firstLine)) throw FormatException('CONNECT rejected: $firstLine');
      } else {
        throw FormatException('Unsupported proxy type: $type');
      }
      return {'ok': true, 'status': 200, 'ms': watch.elapsedMilliseconds, 'message': kind + ' proxy tunnel handshake succeeded'};
    } catch (error) {
      return {'ok': false, 'ms': watch.elapsedMilliseconds, 'message': error.toString()};
    } finally {
      socket?.destroy();
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
          if (!const ['HTTP', 'HTTPS', 'SOCKS5'].contains(type)) {
            await _reply(id, {'ok': false, 'message': 'نوع پروکسی پشتیبانی نمی‌شود'});
          } else if (host.isEmpty || port < 1 || port > 65535) {
            await _reply(id, {'ok': false, 'message': 'IP یا پورت نامعتبر است'});
          } else {
            await _reply(id, await _probeProxy(host, port, type));
          }
          break;

        case 'connect':
          final host = (args['host'] ?? '').toString();
          final port = int.tryParse((args['port'] ?? '').toString()) ?? 0;
          final type = (args['type'] ?? 'HTTP').toString();
          final proxyLink = buildProxyLink(host: host, port: port, type: type);
          await SingBox.instance.requestNotificationPermission();
          await _serializeVpn(() => SingBox.instance.connect(proxyLink));
          await Future<void>.delayed(const Duration(milliseconds: 700));
          final active = SingBox.instance.status.isActive;
          await _reply(id, {
            'ok': active,
            'connected': active,
            'message': active ? 'سرویس VPN فعال شد؛ دسترسی واقعی اینترنت هنوز باید آزمایش شود' : 'موتور VPN فعال نشد؛ وضعیت اتصال ناموفق است',
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

class _SocketReader {
  _SocketReader(Socket socket) : _iterator = StreamIterator<List<int>>(socket);
  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = [];
  Future<List<int>> readExact(int count) async {
    while (_buffer.length < count) {
      if (!await _iterator.moveNext()) throw const SocketException('Proxy closed the connection unexpectedly');
      _buffer.addAll(_iterator.current);
    }
    final result = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return result;
  }
  Future<List<int>> readHeader() async {
    while (true) {
      for (var i = 0; i <= _buffer.length - 4; i++) {
        if (_buffer[i] == 13 && _buffer[i+1] == 10 && _buffer[i+2] == 13 && _buffer[i+3] == 10) {
          final result = _buffer.sublist(0, i+4);
          _buffer.removeRange(0, i+4);
          return result;
        }
      }
      if (_buffer.length > 16384) throw const FormatException('Proxy response headers exceed 16 KiB');
      if (!await _iterator.moveNext()) throw const SocketException('Proxy closed before response headers completed');
      _buffer.addAll(_iterator.current);
    }
  }
}
