import 'package:flutter_test/flutter_test.dart';
import 'package:ip_joker/proxy_link.dart';

void main() {
  group('buildProxyLink', () {
    test('builds HTTP, HTTPS and SOCKS5 links', () {
      expect(buildProxyLink(host: 'proxy.example.com', port: 8080, type: 'HTTP'),
          'http://proxy.example.com:8080');
      expect(buildProxyLink(host: 'proxy.example.com', port: 443, type: 'HTTPS'),
          'https://proxy.example.com:443');
      expect(buildProxyLink(host: '192.0.2.10', port: 1080, type: 'SOCKS5'),
          'socks5://192.0.2.10:1080');
    });

    test('brackets IPv6 addresses', () {
      expect(buildProxyLink(host: '2001:db8::1', port: 1080, type: 'SOCKS5'),
          'socks5://[2001:db8::1]:1080');
      expect(buildProxyLink(host: '[2001:db8::1]', port: 1080, type: 'SOCKS5'),
          'socks5://[2001:db8::1]:1080');
    });

    test('rejects invalid values', () {
      expect(() => buildProxyLink(host: '', port: 80, type: 'HTTP'), throwsFormatException);
      expect(() => buildProxyLink(host: 'host', port: 0, type: 'HTTP'), throwsFormatException);
      expect(() => buildProxyLink(host: 'host', port: 65536, type: 'HTTP'), throwsFormatException);
      expect(() => buildProxyLink(host: 'http://host', port: 80, type: 'HTTP'), throwsFormatException);
      expect(() => buildProxyLink(host: 'host', port: 80, type: 'VLESS'), throwsFormatException);
    });
  });
}
