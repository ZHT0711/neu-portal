import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_state.dart';
import 'core/theme.dart';
import 'core/ios_glass.dart';
import 'core/platform_style.dart';
import 'pages/shell.dart';
import 'widgets/neu_splash.dart';

class NEUPortalApp extends StatefulWidget {
  const NEUPortalApp({super.key, required this.state});

  final AppState state;

  @override
  State<NEUPortalApp> createState() => _NEUPortalAppState();
}

class _NEUPortalAppState extends State<NEUPortalApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // 监听应用生命周期（解决 pixez-flutter Issue #1110 锁屏/后台高 CPU 发热缺陷）
    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.hidden) {
      // 释放键盘焦点与瞬态手势，避免后台轮询
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          // Builder 的 context 在 AppScope 之下，设置变更时随 InheritedNotifier 重建。
          return Builder(
            builder: (ctx) {
              final s = AppScope.of(ctx);
              final useDyn = !isApple && s.useDynamicColor;
              final light = NeuTheme.light(s.seedColor,
                  ios: isApple, dynamicScheme: useDyn ? lightDynamic : null);
              final dark = NeuTheme.dark(s.seedColor,
                  ios: isApple, dynamicScheme: useDyn ? darkDynamic : null);
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
                builder: (context, child) => IosGlassEnvironment(child: child!),
                home: NeuSplashView(
                  isReady: !s.loading,
                  child: const AdaptiveShell(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
