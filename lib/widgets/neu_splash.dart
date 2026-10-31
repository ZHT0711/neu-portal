import 'dart:async';
import 'package:flutter/material.dart';

import '../core/platform_style.dart';
import '../core/ios_glass.dart';

const bool kIsTest = bool.fromEnvironment('FLUTTER_TEST');

/// 东北大学特色启动与全屏加载页面
/// 融合百年东大校徽、校训「自强不息·知行合一」与 Apple 原生液态玻璃微光微动效。
class NeuSplashView extends StatefulWidget {
  const NeuSplashView({
    super.key,
    required this.child,
    this.minDuration = const Duration(milliseconds: 650),
    this.isReady = true,
  });

  final Widget child;
  final Duration minDuration;
  final bool isReady;

  @override
  State<NeuSplashView> createState() => _NeuSplashViewState();
}

class _NeuSplashViewState extends State<NeuSplashView>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseCtrl;
  Animation<double>? _scaleAnim;
  Animation<double>? _glowAnim;

  bool _splashDone = kIsTest;
  bool _timerFired = false;

  @override
  void initState() {
    super.initState();
    if (kIsTest || widget.minDuration == Duration.zero) {
      _splashDone = true;
      return;
    }

    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseCtrl = ctrl;

    _scaleAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic),
    );
    _glowAnim = Tween<double>(begin: 0.25, end: 0.70).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic),
    );

    // 预热图片资源，防止进入主页首帧卡顿
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        precacheImage(const AssetImage('assets/icon/neu_crest.png'), context);
        precacheImage(const AssetImage('assets/icon/logo.png'), context);
        precacheImage(const AssetImage('assets/icon/icon_main.png'), context);
      }
    });

    Timer(widget.minDuration, () {
      if (!mounted) return;
      _timerFired = true;
      _checkDismiss();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && !_splashDone) {
      _pulseCtrl?.stop();
      _splashDone = true;
    }
  }

  @override
  void didUpdateWidget(NeuSplashView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isReady && !oldWidget.isReady) {
      _checkDismiss();
    }
  }

  void _checkDismiss() {
    if (_timerFired && widget.isReady && !_splashDone) {
      _pulseCtrl?.stop();
      setState(() => _splashDone = true);
    }
  }

  @override
  void dispose() {
    _pulseCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_splashDone) return widget.child;

    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isApple
        ? (dark ? const Color(0xFF0D1117) : const Color(0xFFF7F8FA))
        : scheme.surface;

    return Stack(
      children: [
        // 主内容（在后台预构建，零卡顿平滑展示）
        widget.child,

        // 覆盖在最上层的东北大学特色启动与预加载层
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _splashDone ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: Material(
              color: bgColor,
              child: SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 3),

                    // 1. 东大校徽呼吸液态微光徽章
                    Center(
                      child: _pulseCtrl != null && _scaleAnim != null && _glowAnim != null
                          ? AnimatedBuilder(
                              animation: _pulseCtrl!,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _scaleAnim!.value,
                                  child: Container(
                                    width: 104,
                                    height: 104,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: scheme.primary.withValues(
                                              alpha: _glowAnim!.value * 0.45),
                                          blurRadius: 28,
                                          spreadRadius: 4,
                                        ),
                                        BoxShadow(
                                          color: Colors.white.withValues(
                                              alpha: dark ? 0.05 : 0.4),
                                          blurRadius: 10,
                                          offset: const Offset(0, -2),
                                        ),
                                      ],
                                    ),
                                    child: child,
                                  ),
                                );
                              },
                              child: _buildBadge(context, dark, scheme),
                            )
                          : _buildBadge(context, dark, scheme),
                    ),

                    const SizedBox(height: 24),

                    // 2. 东北大学 · 一号通
                    Text(
                      '东北大学 · 一号通',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: scheme.onSurface,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // 3. 东大校训：自强不息 · 知行合一
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 16,
                          height: 1,
                          color: scheme.primary.withValues(alpha: 0.4),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            '自强不息 · 知行合一',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.8,
                              color: isApple
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Container(
                          width: 16,
                          height: 1,
                          color: scheme.primary.withValues(alpha: 0.4),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // 4. 液态微光流动条
                    SizedBox(
                      width: 130,
                      height: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(1.5),
                        child: isApple && _pulseCtrl != null
                            ? Container(
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.12),
                                ),
                                child: AnimatedBuilder(
                                  animation: _pulseCtrl!,
                                  builder: (context, _) {
                                    return Align(
                                      alignment: Alignment(
                                          -1.0 + 2.0 * _pulseCtrl!.value, 0),
                                      child: Container(
                                        width: 50,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              scheme.primary
                                                  .withValues(alpha: 0.0),
                                              scheme.primary,
                                              scheme.primary
                                                  .withValues(alpha: 0.0),
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(1.5),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              )
                            : LinearProgressIndicator(
                                backgroundColor:
                                    scheme.primary.withValues(alpha: 0.12),
                                minHeight: 3,
                              ),
                      ),
                    ),

                    const Spacer(flex: 4),

                    // 5. 底部版权与版本
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '百年学府 · 智慧互联',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.8,
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'NEUPortal 正式版 1.0.0',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(BuildContext context, bool dark, ColorScheme scheme) {
    return isApple
        ? IosGlassSurface(
            radius: 52,
            child: Center(
              child: Image.asset(
                'assets/icon/neu_crest.png',
                width: 68,
                height: 68,
                fit: BoxFit.contain,
              ),
            ),
          )
        : Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerHigh,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Image.asset(
              'assets/icon/neu_crest.png',
              width: 68,
              height: 68,
              fit: BoxFit.contain,
            ),
          );
  }
}

/// 东北大学特色小巧加载组件（用于课表刷新、状态请求等局部等待状态）
class NeuLoadingIndicator extends StatefulWidget {
  const NeuLoadingIndicator({super.key, this.size = 28});

  final double size;

  @override
  State<NeuLoadingIndicator> createState() => _NeuLoadingIndicatorState();
}

class _NeuLoadingIndicatorState extends State<NeuLoadingIndicator>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (!kIsTest) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primary.withValues(alpha: 0.12),
      ),
      padding: EdgeInsets.all(widget.size * 0.15),
      child: Image.asset(
        'assets/icon/neu_crest.png',
        fit: BoxFit.contain,
      ),
    );

    if (_ctrl == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: content,
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl!,
        builder: (context, child) {
          final scale = 0.88 + 0.24 * _ctrl!.value;
          final opacity = 0.55 + 0.45 * _ctrl!.value;
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: child,
            ),
          );
        },
        child: content,
      ),
    );
  }
}
