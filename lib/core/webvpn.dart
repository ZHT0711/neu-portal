/// 东北大学 WebVPN（Wengine 网关）URL 编码与判定。
///
/// 校外访问 `ecard` / `jwxt` 这类校园网专属主机，以及被学校重定向进网关的门户页时，
/// 把原 URL 编成 `https://webvpn.neu.edu.cn/http(s)/<hex(密钥)+AES-CFB密文主机>/<路径>`。
/// 编码算法：AES-128-CFB128，IV = 密钥本身（与 iOS 版 WebVPN.swift / 泥洞 webvpn.rs 一致）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class WebVPN {
  static const String base = 'https://webvpn.neu.edu.cn';

  /// 学校当前网关密钥（来自 WebVPN 前端；旧默认值 wrdvpnisthebest! 已弃用）。
  static final List<int> key = utf8.encode('b0A58a69394ce73@');

  /// WebVPN 的 CAS 登录 service：用公网一号通的 CASTGC 直接换网关票据。
  static const String casService = 'https://webvpn.neu.edu.cn/login?cas_login=true';

  static bool isWrapped(String url) =>
      Uri.tryParse(url)?.host.toLowerCase() == 'webvpn.neu.edu.cn';

  /// 业务系统走所选线路，公网 CAS 与网关自身保持原始地址。
  static bool supports(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if ({'pass.neu.edu.cn', 'webvpn.neu.edu.cn'}.contains(host)) return false;
    if (host == 'neu.edu.cn' || host.endsWith('.neu.edu.cn')) return true;
    final parts = host.split('.').map(int.tryParse).toList();
    return parts.length == 4 &&
        parts.every((p) => p != null && p >= 0 && p <= 255) &&
        (parts[0] == 10 ||
            (parts[0] == 210 && parts[1] == 30) ||
            (parts[0] == 219 && parts[1] == 216) ||
            (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31) ||
            (parts[0] == 192 && parts[1] == 168));
  }

  /// 校园网专属主机。
  static bool isIntranet(String url) {
    return {
      'ecard.neu.edu.cn',
      'jwxt.neu.edu.cn',
      '219.216.96.4',
    }.contains(Uri.tryParse(url)?.host.toLowerCase());
  }

  /// 把内网 URL 编成 WebVPN 网关地址；已是网关地址则原样返回。
  static String wrap(String raw) {
    final trimmed = raw.trim();
    if (isWrapped(trimmed)) return trimmed;

    final normalized = trimmed.startsWith('//')
        ? 'http:$trimmed'
        : trimmed.contains('://')
        ? trimmed
        : 'http://$trimmed';
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return raw;
    }
    final proto = uri.hasPort ? '${uri.scheme}-${uri.port}' : uri.scheme;
    return '$base/$proto/${encryptHost(uri.host)}${uri.path}'
        '${uri.hasQuery ? '?${uri.query}' : ''}'
        '${uri.hasFragment ? '#${uri.fragment}' : ''}';
  }

  /// 还原学校网关链接，供切回直连时复用缓存和页面中的地址。
  static String unwrap(String raw) {
    if (!isWrapped(raw)) return raw;
    final uri = Uri.parse(raw);
    final match = RegExp(
      r'^/(https?)(?:-(\d+))?/([0-9a-f]+)(/.*)?$',
      caseSensitive: false,
    ).firstMatch(uri.path);
    if (match == null) return raw;
    final encoded = match.group(3)!.toLowerCase();
    final prefix = hexEncode(key);
    if (!encoded.startsWith(prefix) || encoded.length.isOdd) return raw;
    final cipher = <int>[
      for (var i = prefix.length; i < encoded.length; i += 2)
        int.parse(encoded.substring(i, i + 2), radix: 16),
    ];
    var previous = Uint8List.fromList(key);
    final plain = <int>[];
    for (var offset = 0; offset < cipher.length; offset += 16) {
      final block = cipher.sublist(
        offset,
        offset + 16 < cipher.length ? offset + 16 : cipher.length,
      );
      final stream = _aesEncryptBlock(previous);
      for (var i = 0; i < block.length; i++) {
        plain.add(block[i] ^ stream[i]);
      }
      if (block.length == 16) previous = Uint8List.fromList(block);
    }
    final host = utf8.decode(plain, allowMalformed: true);
    if (!RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(host)) return raw;
    final port = match.group(2);
    return '${match.group(1)}://$host${port == null ? '' : ':$port'}'
        '${match.group(4) ?? ''}'
        '${uri.hasQuery ? '?${uri.query}' : ''}'
        '${uri.hasFragment ? '#${uri.fragment}' : ''}';
  }

  /// AES-128-CFB128（IV = key）加密主机名 → hex(密钥) + hex(密文)。
  static String encryptHost(String host) {
    final data = utf8.encode(host);
    var prev = Uint8List.fromList(key);
    final out = BytesBuilder();
    var offset = 0;
    while (offset < data.length) {
      final chunkLen = (16 < data.length - offset) ? 16 : data.length - offset;
      final keystream = _aesEncryptBlock(prev);
      final cipher = Uint8List(chunkLen);
      for (var i = 0; i < chunkLen; i++) {
        cipher[i] = data[offset + i] ^ keystream[i];
      }
      if (chunkLen == 16) prev = cipher;
      out.add(cipher);
      offset += chunkLen;
    }
    return hexEncode(key) + hexEncode(out.toBytes());
  }

  /// 单块 AES-ECB 加密，用作 CFB keystream。
  static Uint8List _aesEncryptBlock(List<int> block) {
    final input = Uint8List(16)..setRange(0, 16, block);
    final engine = AESEngine()..init(true, KeyParameter(Uint8List.fromList(key)));
    final out = Uint8List(16);
    engine.processBlock(input, 0, out, 0);
    return out;
  }

  static String hexEncode(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
