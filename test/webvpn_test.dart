import 'package:flutter_test/flutter_test.dart';

import 'package:neu_portal/core/webvpn.dart';

void main() {
  test('wraps ecard URL with the live school key prefix', () {
    final got = WebVPN.wrap('http://ecard.neu.edu.cn/selfsearch/User/baseinfo.aspx');
    expect(
      got.startsWith('https://webvpn.neu.edu.cn/http/62304135386136393339346365373340'),
      isTrue,
      reason: got,
    );
    expect(got.endsWith('/selfsearch/User/baseinfo.aspx'), isTrue);
    expect(got.contains('ecard.neu.edu.cn'), isFalse);
  });

  test('keeps query string and ticket when wrapping', () {
    final got = WebVPN.wrap('http://ecard.neu.edu.cn/selfsearch/User/baseinfo.aspx?ticket=ST-1');
    expect(got.startsWith('https://webvpn.neu.edu.cn/http/'), isTrue);
    expect(got.contains('/selfsearch/User/baseinfo.aspx?ticket=ST-1'), isTrue);
  });

  test('wraps personal portal host (two-block CFB for long hosts)', () {
    final got = WebVPN.wrap('https://personal.neu.edu.cn/portal/schedule/frontend/default/week-list');
    expect(got.contains('62304135386136393339346365373340a0e4b62c85cb47d1bc166e66c800d19283ef83'), isTrue,
        reason: got);
    expect(got.contains('/portal/schedule/frontend/default/week-list'), isTrue);
    expect(got.contains('personal.neu.edu.cn'), isFalse);
  });

  test('leaves already wrapped URLs untouched', () {
    final u = 'https://webvpn.neu.edu.cn/http/abc/foo';
    expect(WebVPN.wrap(u), u);
  });

  test('isIntranet covers campus-only hosts but not public ones', () {
    expect(WebVPN.isIntranet('http://ecard.neu.edu.cn/x'), isTrue);
    expect(WebVPN.isIntranet('https://jwxt.neu.edu.cn/jwapp'), isTrue);
    expect(WebVPN.isIntranet('https://personal.neu.edu.cn/portal'), isFalse);
    expect(WebVPN.isIntranet('https://pass.neu.edu.cn/tpass/login'), isFalse);
  });
}
