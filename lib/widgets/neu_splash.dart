import 'dart:async';
import 'package:flutter/material.dart';

import '../core/platform_style.dart';
import '../core/ios_glass.dart';

const bool kIsTest = bool.fromEnvironment('FLUTTER_TEST');

/// 东北大学特色启动与全屏加载页面
/// 融合百年东大校徽、校训「自强不息·知行合一」与 Apple 原生液态玻璃微光微动效。
/// 具备严格的生命周期管控与瞬态帧率优化，杜绝后台空转与 GPU 发热。
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  AnimationController? _pulseCtrl;
  Animation<double>? _scaleAnim;
  Animation<double>? _glowAnim;

  bool _splashDone = kIsTest;
  bool _timerFired = false;
  Timer? _dismissTimer;
  Timer? _maxGuardTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (kIsTest || widget.minDuration == Duration.zero) {
      _splashDone = true;
      return;
    }

    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseCtrl = ctrl;

    _scaleAnim = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeOutBack),
    );
    _glowAnim = Tween<double>(begin: 0.15, end: 0.50).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic),
    );

    // 单次优雅进场展开，避免死循环 repeat() 导致 CPU/GPU 100% 满载发热
    ctrl.forward();

    // 预热图片资源，指定 cache 大小节约 GPU 内存
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        precacheImage(
          const ResizeImage(
            AssetImage('assets/icon/neu_crest.png'),
            width: 140,
            height: 140,
          ),
          context,
        );
        precacheImage(
          const ResizeImage(
            AssetImage('assets/icon/logo.png'),
            width: 160,
            height: 160,
          ),
          context,
        );
      }
    });

    _dismissTimer = Timer(widget.minDuration, () {
      if (!mounted) return;
      _timerFired = true;
      _checkDismiss();
    });

    // 保护计时器：即使网络请求在慢速 5G 或离线等待，最多 850ms 自动过渡进主页，
    // 不将用户与 GPU 长时间锁在闪屏着色器循环中
    _maxGuardTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted || _splashDone) return;
      _timerFired = true;
      _dismissImmediately();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 监听系统生命周期：锁屏或退至后台时立即停止一切 Ticker，防范 Issue #1110 后台发热
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _pulseCtrl?.stop();
    } else if (state == AppLifecycleState.resumed && !_splashDone) {
      if (_pulseCtrl?.isAnimating == false) {
        _pulseCtrl?.forward();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && !_splashDone) {
      _dismissImmediately();
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
    if (_timerFired && (widget.isReady || _timerFired) && !_splashDone) {
      _dismissImmediately();
    }
  }

  void _dismissImmediately() {
    if (_splashDone) return;
    _pulseCtrl?.stop();
    _dismissTimer?.cancel();
    _maxGuardTimer?.cancel();
    if (mounted) {
      setState(() => _splashDone = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dismissTimer?.cancel();
    _maxGuardTimer?.cancel();
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

    return RepaintBoundary(
      child: Stack(
        children: [
          // 主内容
          widget.child,

          // 覆盖在最上层的东北大学特色启动层
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _splashDone ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: Material(
                color: bgColor,
                child: SafeArea(
                  child: Column(
                    children: [
                      const Spacer(flex: 3),

                      // 1. 东大校徽液态微光徽章
                      Center(
                        child: _pulseCtrl != null &&
                                _scaleAnim != null &&
                                _glowAnim != null
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
                                                alpha: _glowAnim!.value * 0.40),
                                            blurRadius: 24,
                                            spreadRadius: 2,
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
                        width: 120,
                        height: 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(1.5),
                          child: LinearProgressIndicator(
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
      ),
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
                cacheWidth: 136,
                cacheHeight: 136,
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
              cacheWidth: 136,
              cacheHeight: 136,
              fit: BoxFit.contain,
            ),
          );
  }
}

/// 东北大学特色小巧加载组件（用于课表刷新、状态请求等局部等待状态）
class NeuLoadingIndicator extends StatelessWidget {
  const NeuLoadingIndicator({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary.withValues(alpha: 0.12),
        ),
        padding: EdgeInsets.all(size * 0.15),
        child: Image.asset(
          'assets/icon/neu_crest.png',
          width: size,
          height: size,
          cacheWidth: (size * 2).toInt(),
          cacheHeight: (size * 2).toInt(),
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
