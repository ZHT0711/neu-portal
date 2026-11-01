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

  static bool isWrapped(String url) => url.contains('webvpn.neu.edu.cn');

  /// 校园网专属主机。
  static bool isIntranet(String url) {
    final u = url.toLowerCase();
    return u.contains('ecard.neu.edu.cn') ||
        u.contains('jwxt.neu.edu.cn') ||
        u.contains('219.216.96.4');
  }

  /// 把内网 URL 编成 WebVPN 网关地址；已是网关地址则原样返回。
  static String wrap(String raw) {
    final trimmed = raw.trim();
    if (isWrapped(trimmed)) return trimmed;

    var scheme = 'http';
    var rest = trimmed;
    if (trimmed.startsWith('https://')) {
      scheme = 'https';
      rest = trimmed.substring(8);
    } else if (trimmed.startsWith('http://')) {
      rest = trimmed.substring(7);
    } else if (trimmed.startsWith('//')) {
      rest = trimmed.substring(2);
    }

    var query = '';
    final qIndex = rest.indexOf('?');
    if (qIndex >= 0) {
      query = rest.substring(qIndex);
      rest = rest.substring(0, qIndex);
    }

    var hostPort = rest;
    var path = '';
    final slash = rest.indexOf('/');
    if (slash >= 0) {
      hostPort = rest.substring(0, slash);
      path = rest.substring(slash);
    }

    var host = hostPort;
    String? port;
    final colon = hostPort.lastIndexOf(':');
    if (colon > 0) {
      final h = hostPort.substring(0, colon);
      final p = hostPort.substring(colon + 1);
      if (RegExp(r'^\d+$').hasMatch(p)) {
        host = h;
        port = p;
      }
    }

    final proto = port == null ? scheme : '$scheme-$port';
    return '$base/$proto/${encryptHost(host)}$path$query';
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
