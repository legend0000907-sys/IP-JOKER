String buildProxyLink({
  required String host,
  required int port,
  required String type,
}) {
  final normalizedHost = host.trim();
  final normalizedType = type.trim().toUpperCase();
  if (normalizedHost.isEmpty ||
      normalizedHost.contains(' ') ||
      normalizedHost.contains('://') ||
      port < 1 ||
      port > 65535 ||
      !{'HTTP', 'HTTPS', 'SOCKS5'}.contains(normalizedType)) {
    throw const FormatException('Invalid proxy address, type, or port');
  }

  final unwrappedHost = normalizedHost.startsWith('[') && normalizedHost.endsWith(']')
      ? normalizedHost.substring(1, normalizedHost.length - 1)
      : normalizedHost;
  final safeHost = unwrappedHost.contains(':') ? '[$unwrappedHost]' : unwrappedHost;
  final scheme = switch (normalizedType) {
    'SOCKS5' => 'socks5',
    'HTTPS' => 'https',
    _ => 'http',
  };
  final link = '$scheme://$safeHost:$port';
  final parsed = Uri.tryParse(link);
  if (parsed == null || parsed.host.isEmpty || parsed.port != port) {
    throw const FormatException('Invalid proxy address');
  }
  return link;
}
