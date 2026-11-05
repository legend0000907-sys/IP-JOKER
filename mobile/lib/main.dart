import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sing_box/sing_box.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SingBox.instance.initialize(const SingBoxOptions(
    android: SingBoxAndroidOptions(
      notificationTitle: 'IP JOKER',
      showTrafficInNotification: true,
      stopActionTitle: 'قطع اتصال',
    ),
  ));
  runApp(const IpJokerApp());
}

class IpJokerApp extends StatelessWidget {
  const IpJokerApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: IpJokerHome(),
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

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('IPJokerNative',
          onMessageReceived: (message) => _handle(message.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => ready = true),
      ))
      ..loadFlutterAsset('assets/index.html');
  }

  Future<void> _reply(String id, Map<String, dynamic> result) async {
    final encoded = jsonEncode(jsonEncode(result));
    await controller.runJavaScript(
      'window.__ipjokerResolve && window.__ipjokerResolve($id, $encoded);',
    );
  }

  Future<void> _handle(String raw) async {
    String id = '0';
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      id = jsonEncode(data['id']?.toString() ?? '0');
      final action = data['action'] as String? ?? '';
      final args = (data['args'] as Map?)?.cast<String, dynamic>() ?? {};
      if (action == 'connect') {
        final host = (args['host'] ?? '').toString().trim();
        final port = int.tryParse((args['port'] ?? '').toString()) ?? 0;
        final type = (args['type'] ?? 'HTTP').toString().toUpperCase();
        if (host.isEmpty || port < 1 || port > 65535) {
          await _reply(id, {'ok': false, 'message': 'IP/دامنه یا پورت معتبر نیست'});
          return;
        }
        final scheme = switch (type) {
          'SOCKS5' => 'socks5',
          'HTTPS' => 'https',
          _ => 'http',
        };
        final safeHost = host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
        final link = '$scheme://$safeHost:$port';
        await SingBox.instance.connect(link);
        await _reply(id, {'ok': true, 'message': 'VPN متصل شد'});
      } else if (action == 'disconnect') {
        await SingBox.instance.disconnect();
        await _reply(id, {'ok': true, 'message': 'اتصال قطع شد'});
      } else if (action == 'status') {
        await _reply(id, {
          'ok': true,
          'connected': SingBox.instance.status.isActive,
          'message': SingBox.instance.status.name,
        });
      } else if (action == 'save') {
        await _reply(id, {'ok': true, 'message': 'پروفایل در رابط برنامه ذخیره شد'});
      } else {
        await _reply(id, {'ok': false, 'message': 'درخواست ناشناخته'});
      }
    } on SingBoxException catch (e) {
      await _reply(id, {'ok': false, 'message': e.message});
    } catch (e) {
      await _reply(id, {'ok': false, 'message': e.toString()});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Stack(children: [
        WebViewWidget(controller: controller),
        if (!ready) const Center(child: CircularProgressIndicator()),
      ]),
    ),
  );
}
