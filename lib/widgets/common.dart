/// 通用小组件（v2：分组面板 / 入场动画 / 数字动画 / 统一磁贴）。
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/links.dart';
import '../core/platform_style.dart';
import '../core/theme.dart';

/// 页面分区标题。
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
                header: true,
                child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium)),
          ),
          if (action != null)
            if (isApple)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: onAction,
                child: Text(action!,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: scheme.primary)),
              )
            else
              TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// 分组面板：自带 Material（墨水涟漪 / ListTile 正常工作）。
/// 遵循 Apple HIG 规范：卡片内容层使用次级分组背景与微阴影，将液态玻璃留给导航与悬浮控制层，
/// 带来清晰的层级对比，同时消除重复毛玻璃着色器引发的 GPU 发热与卡顿。
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding, this.color});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (isApple) {
      final cardColor = color ??
          (dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF));
      return RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(Ds.rMd),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0x14000000),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: (dark ? Colors.black : const Color(0xFF3553A2))
                    .withValues(alpha: dark ? 0.22 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: padding == null
                ? child
                : Padding(padding: padding!, child: child),
          ),
        ),
      );
    }
    final panelColor = color ?? scheme.surfaceContainerLow;
    return Material(
      color: panelColor,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ds.rLg)),
      clipBehavior: Clip.antiAlias,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

/// 列表项入场动画（按序错开）。
class StaggerIn extends StatefulWidget {
  const StaggerIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn> {
  bool _shown = false;

  Timer? _timer;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _timer?.cancel();
      _shown = true;
    } else if (!_scheduled && !_shown) {
      _scheduled = true;
      _timer = Timer(Duration(milliseconds: 60 * widget.index.clamp(0, 8)), () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedSlide(
      offset: _shown ? Offset.zero : const Offset(0, 0.03),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// 数字滚动动画（非数字内容原样显示）。
class CountUpText extends StatelessWidget {
  const CountUpText(
    this.text, {
    super.key,
    this.style,
    this.suffix = '',
  });

  final String text;
  final TextStyle? style;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final v =
        MediaQuery.disableAnimationsOf(context) ? null : double.tryParse(text);
    if (v == null) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text, style: style),
            if (suffix.isNotEmpty)
              TextSpan(
                  text: ' $suffix',
                  style: style?.copyWith(
                      fontSize: (style?.fontSize ?? 14) * 0.6,
                      fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    final isInt = text.contains('.') == false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: v),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, val, _) {
        final shown = isInt ? val.round().toString() : val.toStringAsFixed(1);
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: shown, style: style),
              if (suffix.isNotEmpty)
                TextSpan(
                    text: ' $suffix',
                    style: style?.copyWith(
                        fontSize: (style?.fontSize ?? 14) * 0.6,
                        fontWeight: FontWeight.w500)),
            ],
          ),
        );
      },
    );
  }
}

/// 应用入口磁贴（图标优先，失败回退首字色块）。
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    required this.name,
    this.iconUrl,
    this.onTap,
    this.dense = false,
  });

  final String name;
  final String? iconUrl;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tone = NeuColors.adaptiveTone(context, NeuColors.avatarColor(name));
    final size = dense ? 42.0 : 48.0;
    final url = iconUrl;
    Widget icon;
    if (url != null && url.startsWith('http')) {
      icon = ClipRRect(
        borderRadius: BorderRadius.circular(size / 3.2),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
            cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
            errorBuilder: (_, _, _) => _letterBox(tone, size),
          ),
        ),
      );
    } else {
      icon = _letterBox(tone, size);
    }
    return Semantics(
      label: name,
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 7),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: dense ? 12 : 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _letterBox(Color tone, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tone.withValues(alpha: 0.22),
            tone.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(size / 3.2),
        border: Border.all(color: tone.withValues(alpha: 0.30)),
      ),
      alignment: Alignment.center,
      child: Text(
        name.characters.first,
        style: TextStyle(
          color: tone,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// 打开门户链接（应用内 WebView / 系统快速浏览器）。
Future<void> openPortalLink(BuildContext context, String url,
        {String title = '页面'}) =>
    AppLinks.open(context, url, title: title);

/// 空状态。
class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text,
      {super.key, this.icon = Icons.emoji_nature_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: scheme.outline),
          ),
          const SizedBox(height: 12),
          Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
