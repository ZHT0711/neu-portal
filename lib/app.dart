import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_state.dart';
import 'core/theme.dart';
import 'pages/shell.dart';

class NEUPortalApp extends StatelessWidget {
  const NEUPortalApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          // Builder 的 context 在 AppScope 之下，设置变更时随 InheritedNotifier 重建。
          return Builder(
            builder: (ctx) {
              final s = AppScope.of(ctx);
              final useDyn = s.useDynamicColor;
              final light = NeuTheme.light(useDyn && lightDynamic != null
                  ? lightDynamic.primary
                  : s.seedColor);
              final dark = NeuTheme.dark(useDyn && darkDynamic != null
                  ? darkDynamic.primary
                  : s.seedColor);
              return MaterialApp(
                title: '东大一号通',
                debugShowCheckedModeBanner: false,
                themeMode: s.themeMode,
                theme: light,
                darkTheme: dark,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('zh', 'CN')],
                locale: const Locale('zh', 'CN'),
                home: const AdaptiveShell(),
              );
            },
          );
        },
      ),
    );
  }
}
