import 'dart:async';
import 'package:flutter/material.dart';

/// 有限时长的品牌启动层，始终保留底下页面的同一棵元素树。
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
  late final AnimationController _entrance;
  late final Animation<double> _scale;
  bool _removed = false;
  bool _dismissing = false;
  bool _minimumElapsed = false;
  Timer? _dismissTimer;
  Timer? _maxGuardTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scale = Tween<double>(
      begin: 0.97,
      end: 1,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    if (widget.minDuration == Duration.zero) {
      _removed = true;
      return;
    }
    _entrance.forward();
    _dismissTimer = Timer(widget.minDuration, () {
      _minimumElapsed = true;
      if (widget.isReady) _dismiss();
    });
    // 慢网续登仍在后台继续，启动层不会一直阻挡首页。
    _maxGuardTimer = Timer(const Duration(milliseconds: 850), _dismiss);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.stop();
      _dismissTimer?.cancel();
      _maxGuardTimer?.cancel();
      _removed = true;
    }
  }

  @override
  void didUpdateWidget(NeuSplashView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isReady && _minimumElapsed) _dismiss();
  }

  void _dismiss() {
    if (!mounted || _removed || _dismissing) return;
    _entrance.stop();
    _dismissTimer?.cancel();
    _maxGuardTimer?.cancel();
    setState(() => _dismissing = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _entrance.stop();
    } else if (!_removed && !_dismissing && !_entrance.isCompleted) {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dismissTimer?.cancel();
    _maxGuardTimer?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Stack 的结构不随启动层消失而改变，避免首页销毁后重新初始化。
    return Stack(
      children: [
        widget.child,
        if (!_removed)
          Positioned.fill(
            child: BlockSemantics(
              child: IgnorePointer(
                ignoring: _dismissing,
                child: AnimatedOpacity(
                  opacity: _dismissing ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  onEnd: () {
                    if (mounted && _dismissing) {
                      setState(() => _removed = true);
                    }
                  },
                  child: RepaintBoundary(
                    child: Material(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: SafeArea(
                        child: Column(
                          children: [
                            const Spacer(flex: 3),
                            ScaleTransition(
                              scale: _scale,
                              child: Container(
                                width: 104,
                                height: 104,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: scheme.surfaceContainerLow,
                                  border: Border.all(
                                    color: scheme.outlineVariant.withValues(
                                      alpha: dark ? 0.35 : 0.5,
                                    ),
                                  ),
                                ),
                                child: Image.asset(
                                  'assets/icon/neu_crest.png',
                                  color: dark ? scheme.primary : null,
                                  width: 68,
                                  height: 68,
                                  cacheWidth:
                                      (68 *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .ceil(),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '东北大学 · 一号通',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '自强不息 · 知行合一',
                              style: TextStyle(
                                fontSize: 13,
                                letterSpacing: 1.8,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 28),
                            // 只随入场播放一次，不为等待网络持续刷新帧。
                            SizedBox(
                              width: 80,
                              height: 3,
                              child: AnimatedBuilder(
                                animation: _entrance,
                                builder: (context, _) =>
                                    LinearProgressIndicator(
                                      value: _entrance.value,
                                      color: scheme.primary.withValues(
                                        alpha: dark ? 0.65 : 0.8,
                                      ),
                                      backgroundColor: scheme.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                              ),
                            ),
                            const Spacer(flex: 4),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '百年学府 · 智慧互联',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      letterSpacing: 0.8,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'NEUPortal 正式版 1.0.0',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.onSurfaceVariant.withValues(
                                        alpha: 0.7,
                                      ),
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
              ),
            ),
          ),
      ],
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
