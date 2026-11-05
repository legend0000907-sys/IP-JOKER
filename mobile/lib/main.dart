import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';
import 'package:ip_joker/proxy_link.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? startupError;
  try {
    await SingBox.instance.initialize(const SingBoxOptions(
      logMaxLines: 2000,
      android: SingBoxAndroidOptions(
        notificationTitle: 'IP JOKER',
        showTrafficInNotification: true,
        stopActionTitle: 'قطع اتصال',
      ),
    ));
  } catch (error) {
    startupError = error;
  }
  runApp(IpJokerApp(startupError: startupError));
}

class IpJokerApp extends StatelessWidget {
  const IpJokerApp({super.key, this.startupError});
  final Object? startupError;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IP JOKER',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFFe53935)),
        home: IpJokerHome(startupError: startupError),
      );
}

class IpJokerHome extends StatefulWidget {
  const IpJokerHome({super.key, this.startupError});
  final Object? startupError;

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
      ..addJavaScriptChannel(
        'IPJokerNative',
        onMessageReceived: (message) => _handle(message.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => ready = true);
          if (widget.startupError != null) {
            _showStartupError();
          }
        },
        onWebResourceError: (error) {
          debugPrint('IP JOKER WebView: ${error.description}');
        },
      ))
      ..loadFlutterAsset('assets/index.html');
  }

  Future<void> _showStartupError() async {
    final error = widget.startupError;
    if (error == null || !mounted) return;
    await controller.runJavaScript(
      'window.__ipjokerStartupError && window.__ipjokerStartupError(${jsonEncode(error.toString())});',
    );
  }

  Future<void> _reply(String id, Map<String, dynamic> result) async {
    final idLiteral = jsonEncode(id);
    final resultLiteral = jsonEncode(jsonEncode(result));
    await controller.runJavaScript(
      'window.__ipjokerResolve && window.__ipjokerResolve($idLiteral, $resultLiteral);',
    );
  }

  Future<void> _handle(String raw) async {
    var id = '0';
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      id = data['id']?.toString() ?? '0';
      final action = data['action'] as String? ?? '';
      final args = (data['args'] as Map?)?.cast<String, dynamic>() ?? {};

      switch (action) {
        case 'connect':
          final host = (args['host'] ?? '').toString();
          final port = int.tryParse((args['port'] ?? '').toString()) ?? 0;
          final type = (args['type'] ?? 'HTTP').toString();
          final proxyLink = buildProxyLink(host: host, port: port, type: type);
          await SingBox.instance.requestNotificationPermission();
          await SingBox.instance.connect(proxyLink);
          await _reply(id, {
            'ok': true,
            'connected': SingBox.instance.status.isActive,
            'message': 'تونل VPN برقرار شد',
          });
          break;

        case 'disconnect':
          await SingBox.instance.disconnect();
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
          // The original HTML stores saved profiles in persistent WebView localStorage.
          await _reply(id, {'ok': true, 'message': 'پروفایل ذخیره شد'});
          break;

        default:
          await _reply(id, {'ok': false, 'message': 'درخواست ناشناخته است'});
      }
    } on SingBoxException catch (error) {
      await _reply(id, {'ok': false, 'message': error.message});
    } catch (error) {
      await _reply(id, {'ok': false, 'message': error.toString()});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: controller),
              if (!ready) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      );
}
