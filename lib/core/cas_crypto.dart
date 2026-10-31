/// 东北大学统一身份认证（CAS）密码加密。
/// 与门户前端 JSEncrypt 完全一致：RSA PKCS#1 v1.5，公钥来自 login_neu.js。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

const String kNeuCasLoginUrl =
    'https://pass.neu.edu.cn/tpass/login?service='
    'https%3A%2F%2Fpersonal.neu.edu.cn%2Fportal%2Fmanage%2Fcommon%2Fcas_login%2F1'
    '%3Fredirect%3Dhttps%253A%252F%252Fpersonal.neu.edu.cn%252Fportal';

/// login_neu.js 中 publicKeyStr 的模数（2048-bit），指数固定 65537。
const String _kModulusHex =
    '009e3036f032ca5d9cf16ca9a8f7fd569152dfd66afec2d2d72d7b7ab02e168810adb1bcc5'
    'e5ec26ec0459780752de266daa560f9fa21c5283b0e361fc9c02bfb5f15c21be9d6752b46a'
    'd9f4537f6858218fcd8b8ab4b25e32e3598835d5b805eda23adc90e8cb5bd0778149da3462'
    'ee231d1f61eeba974a3d5a35367062cd6507e2231b36874d33d4403d21d4a7571895416483'
    'fa5b0fdc96578764d3dbcee56b8638eb4dd240d2932bf42f5df72671cc1311dd485ba1f01b'
    '10fa42b9089c18878ac296c66bde37b50349a41167f27dec6d180b7da90f7f164f9de2cd77'
    '8ad29fe453f5f7ed53f9e79ba6d7055616f3c8b9cf48ee030fd7e86ae5af97e9cfbeb5';

class CasCrypto {
  static final BigInt _n = BigInt.parse(_kModulusHex, radix: 16);
  static final BigInt _e = BigInt.from(65537);
  static final int _k = _n.bitLength + 7 >> 3; // 256

  /// RSA-PKCS1v15(utf8(username + password)) → base64。
  static String encrypt(String plaintext) {
    final msg = utf8.encode(plaintext);
    if (msg.length > _k - 11) {
      throw ArgumentError('plaintext too long for RSA block');
    }
    final rand = Random.secure();
    final ps = Uint8List(_k - 3 - msg.length);
    for (var i = 0; i < ps.length; i++) {
      ps[i] = rand.nextInt(255) + 1; // 非零填充
    }
    final block = BytesBuilder()
      ..addByte(0x00)
      ..addByte(0x02)
      ..add(ps)
      ..addByte(0x00)
      ..add(msg);
    final m = _bytesToBigInt(block.toBytes());
    final c = m.modPow(_e, _n);
    return base64.encode(_bigIntToBytes(c, _k));
  }

  static BigInt _bytesToBigInt(List<int> bytes) {
    var r = BigInt.zero;
    for (final b in bytes) {
      r = (r << 8) | BigInt.from(b);
    }
    return r;
  }

  static Uint8List _bigIntToBytes(BigInt v, int length) {
    final hex = v.toRadixString(16).padLeft(length * 2, '0');
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
