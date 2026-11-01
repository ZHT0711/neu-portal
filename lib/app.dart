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

class _NEUPortalAppState extends State<NEUPortalApp>
    with WidgetsBindingObserver {
  late (ThemeMode, Color, bool, PlatformStylePreference) _appearance;

  (ThemeMode, Color, bool, PlatformStylePreference) get _currentAppearance => (
    widget.state.themeMode,
    widget.state.seedColor,
    widget.state.useDynamicColor,
    widget.state.platformStyle,
  );

  void _onStateChanged() {
    final next = _currentAppearance;
    if (next != _appearance) setState(() => _appearance = next);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appearance = _currentAppearance;
    widget.state.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(NEUPortalApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_onStateChanged);
      widget.state.addListener(_onStateChanged);
      _appearance = _currentAppearance;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(_onStateChanged);
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
          // 仅外观设置变化时重建主题；课表/登录/刷新通知由各页面订阅。
          return Builder(
            builder: (ctx) {
              final s = widget.state;
              final useDyn = !isApple && s.useDynamicColor;
              final light = NeuTheme.light(
                s.seedColor,
                ios: isApple,
                dynamicScheme: useDyn ? lightDynamic : null,
              );
              final dark = NeuTheme.dark(
                s.seedColor,
                ios: isApple,
                dynamicScheme: useDyn ? darkDynamic : null,
              );
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
                home: AnimatedBuilder(
                  animation: s,
                  child: const AdaptiveShell(),
                  builder: (context, child) =>
                      NeuSplashView(isReady: !s.loading, child: child!),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
