import 'package:flutter_test/flutter_test.dart';
import 'package:neu_portal/core/portal_client.dart';

void main() {
  group('CookieJar Tests', () {
    test(
      'gateway cookies with the same name retain paths, host scope and Secure',
      () {
        final jar = CookieJar();
        final gateway = Uri.parse('https://webvpn.neu.edu.cn/');
        jar.absorbRaw(
          gateway,
          'SESS_ID=root; Path=/, SESS_ID=portal; Path=/https/portal; Secure',
        );
        final request = Uri.parse('https://webvpn.neu.edu.cn/https/portal/api');
        expect(jar.headerFor(request), 'SESS_ID=portal; SESS_ID=root');
        expect(
          jar.headerFor(Uri.parse('https://webvpn.neu.edu.cn/https/portalx')),
          'SESS_ID=root',
        );
        expect(
          jar.headerFor(Uri.parse('http://webvpn.neu.edu.cn/https/portal/api')),
          'SESS_ID=root',
        );
        expect(
          jar.headerFor(Uri.parse('https://child.webvpn.neu.edu.cn/')),
          isNull,
        );
        expect(
          jar.browserCookies().map((c) => c.path),
          containsAll(['/', '/https/portal']),
        );
        jar.absorbRaw(gateway, 'SESS_ID=; Path=/https/portal; Max-Age=0');
        expect(jar.headerFor(request), 'SESS_ID=root');
      },
    );

    test('splitSetCookie handles comma in Expires date without splitting cookie', () {
      const raw =
          'Language=zh_CN; Max-Age=604800; Expires=Sat, 07 Nov 2026 15:02:20 GMT; Path=/, '
          'JSESSIONID=1A2569910E0AAA259D4EA42D6DC9A919; Path=/tpass; HttpOnly, '
          'SESS_ID=0g84eK6NusKa4QkgQXzp5dXmYP1V4gpres1G9PbF; path=/; domain=personal.neu.edu.cn; httponly; samesite=lax';

      final cookies = CookieJar.splitSetCookie(raw);
      expect(cookies.length, 3);
      expect(
        cookies[0],
        startsWith('Language=zh_CN; Max-Age=604800; Expires=Sat, 07 Nov 2026'),
      );
      expect(
        cookies[1],
        startsWith('JSESSIONID=1A2569910E0AAA259D4EA42D6DC9A919'),
      );
      expect(
        cookies[2],
        startsWith('SESS_ID=0g84eK6NusKa4QkgQXzp5dXmYP1V4gpres1G9PbF'),
      );
    });

    test('CookieJar domain matching and cross-subdomain sharing', () {
      final jar = CookieJar();
      // CAS sets domain cookie .neu.edu.cn and host cookie pass.neu.edu.cn
      jar.absorbRaw(
        Uri.parse('https://pass.neu.edu.cn/tpass/login'),
        'CASTGC=TGC-12345; domain=.neu.edu.cn; path=/, JSESSIONID=PASS99; Path=/tpass',
      );
      // Portal sets personal.neu.edu.cn
      jar.absorbRaw(
        Uri.parse('https://personal.neu.edu.cn/portal'),
        'SESS_ID=SESS88; domain=personal.neu.edu.cn; path=/',
      );

      // pass.neu.edu.cn gets both CASTGC and JSESSIONID
      final passHeader = jar.headerFor(
        Uri.parse('https://pass.neu.edu.cn/tpass/login'),
      );
      expect(passHeader, contains('CASTGC=TGC-12345'));
      expect(passHeader, contains('JSESSIONID=PASS99'));

      // personal.neu.edu.cn gets CASTGC (.neu.edu.cn) and SESS_ID (personal.neu.edu.cn)
      final personalHeader = jar.headerFor(
        Uri.parse('https://personal.neu.edu.cn/portal'),
      );
      expect(personalHeader, contains('CASTGC=TGC-12345'));
      expect(personalHeader, contains('SESS_ID=SESS88'));

      // jwxt.neu.edu.cn gets CASTGC (.neu.edu.cn) for SSO
      final jwxtHeader = jar.headerFor(
        Uri.parse('https://jwxt.neu.edu.cn/jwapp/sys'),
      );
      expect(jwxtHeader, contains('CASTGC=TGC-12345'));
      expect(jwxtHeader, isNot(contains('SESS_ID=SESS88')));

      // hasCookie works properly
      expect(
        jar.hasCookie(
          Uri.parse('https://personal.neu.edu.cn/portal'),
          'SESS_ID',
        ),
        isTrue,
      );
      expect(
        jar.hasCookie(Uri.parse('https://jwxt.neu.edu.cn/'), 'CASTGC'),
        isTrue,
      );
      expect(
        jar.hasCookie(Uri.parse('https://pass.neu.edu.cn/'), 'SESS_ID'),
        isFalse,
      );
    });

    test('CookieJar deletion on Max-Age=0 or empty value', () {
      final jar = CookieJar();
      final uri = Uri.parse('https://personal.neu.edu.cn/portal');
      jar.absorbRaw(uri, 'SESS_ID=abc; path=/');
      expect(jar.hasCookie(uri, 'SESS_ID'), isTrue);

      // Expire via Max-Age=0
      jar.absorbRaw(uri, 'SESS_ID=deleted; Max-Age=0; path=/');
      expect(jar.hasCookie(uri, 'SESS_ID'), isFalse);
    });

    test(
      'Cookie snapshot includes exact and dot-prefixed domains for WebView',
      () {
        final jar = CookieJar();
        jar.absorbRaw(
          Uri.parse('https://pass.neu.edu.cn/tpass/login'),
          'CASTGC=TGC-123; domain=.neu.edu.cn; path=/',
        );

        final snap = jar.cookieSnapshot();
        expect(snap.containsKey('neu.edu.cn'), isTrue);
        expect(snap.containsKey('.neu.edu.cn'), isTrue);
        expect(snap['neu.edu.cn']?['CASTGC'], equals('TGC-123'));
        expect(snap['.neu.edu.cn']?['CASTGC'], equals('TGC-123'));
      },
    );
  });

  group('userInfoDSL Robust Extraction Tests', () {
    test('extractUserFromHtml succeeds with trailing semicolon and newlines', () {
      const html = '''
<!DOCTYPE html>
<html>
<head>
  <script type="text/javascript">
    window.userInfoDSL = {
      "uid": "10086",
      "name": "张学友",
      "xgh": "20230001",
      "identity": "本科生",
      "depart": "软件学院",
      "email": "zhang@stu.neu.edu.cn",
      "avatar": "https://personal.neu.edu.cn/u/10086.jpg"
    };
  </script>
</head>
</html>
''';
        final user = PortalClient.extractUserFromHtml(html);
        expect(user, isNotNull);
        expect(user!.name, equals('张学友'));
        expect(user.sid, equals('20230001'));
        expect(user.department, equals('软件学院'));
        expect(user.email, equals('zhang@stu.neu.edu.cn'));
      },
    );

    test('extractUserFromHtml succeeds with nested objects and trailing statements', () {
      const html = '''
<script>
  window.userInfoDSL = {
    "uid": "20002",
    "name": "李四",
    "xgh": "20240002",
    "identity": "研究生",
    "depart": "信息科学与工程学院",
    "email": "lisi@neu.edu.cn",
    "avatar": "",
    "config": {
      "theme": "dark",
      "roles": [{"id": 1, "name": "student"}]
    }
  };
  initApp({debug: false});
</script>
''';
        final user = PortalClient.extractUserFromHtml(html);
        expect(user, isNotNull);
        expect(user!.name, equals('李四'));
        expect(user.sid, equals('20240002'));
        expect(user.identity, equals('研究生'));
      },
    );

    test('extractUserFromHtml succeeds with strings containing braces and quotes', () {
      const html = '''
<script>
  userInfoDSL = {
    "uid": "30003",
    "name": "王五{特注}",
    "xgh": "20250003",
    "identity": "本科生",
    "depart": "计算机学院;创新班",
    "email": "wang5@neu.edu.cn",
    "avatar": "https://neu.edu.cn/pic?a=1&b=2"
  };
</script>
''';
        final user = PortalClient.extractUserFromHtml(html);
        expect(user, isNotNull);
        expect(user!.name, equals('王五{特注}'));
        expect(user.department, equals('计算机学院;创新班'));
      },
    );

    test('extractUserFromHtml returns null for login/CAS redirect page without DSL', () {
      const html = '''
<!DOCTYPE html>
<html>
<head><title>统一身份认证</title></head>
<body>
  <form id="loginForm" action="/tpass/login">
    <span id="errormsg">账号或密码错误</span>
  </form>
</body>
</html>
''';
        final user = PortalClient.extractUserFromHtml(html);
        expect(user, isNull);
      },
    );
  });
}
