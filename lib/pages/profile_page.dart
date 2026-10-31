import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/platform_style.dart';
import '../core/ios_glass.dart';
import '../core/demo_data.dart';
import '../core/tab_scroller.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'login_page.dart';

/// 个人中心 + 外观设置。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    TabScroller.attach(4, _scroll);
  }

  @override
  void dispose() {
    TabScroller.detach(4);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final u = s.user;

    return Scaffold(
      appBar: const PageAppBar(title: '我的'),
      body: ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(16, 4, 16, portalBottomInset(context)),
        children: [
          // 用户卡
          StaggerIn(
            index: 0,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(Ds.rXl),
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withValues(alpha: 0.18),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 1.6),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: u.avatarUrl.startsWith('http')
                        ? Image.network(
                            u.avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Center(
                              child: Text(
                                u.name.characters.first,
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              u.name.characters.first,
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${u.sid} · ${u.identity} · ${u.department}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: scheme.onPrimaryContainer
                                      .withValues(alpha: 0.85)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          u.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color: scheme.onPrimaryContainer
                                      .withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (s.mode == SessionMode.demo) ...[
            const SizedBox(height: 12),
            StaggerIn(
              index: 1,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                ),
                icon: const Icon(Icons.login),
                label: const Text('登录统一身份认证'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),

          // 外观
          StaggerIn(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _GroupTitle('外观'),
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.contrast),
                        title: Text('主题模式'),
                        subtitle: Text('自动 / 亮色 / 暗色'),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: AdaptiveSegments<ThemeMode>(
                            values: const {
                              ThemeMode.system: '自动',
                              ThemeMode.light: '浅色',
                              ThemeMode.dark: '深色'
                            },
                            selected: s.themeMode,
                            onChanged: s.setThemeMode,
                          ),
                        ),
                      ),
                      if (!isApple)
                        SwitchListTile(
                          secondary: const Icon(Icons.palette_outlined),
                          title: const Text('动态取色 (Material You)'),
                          subtitle: const Text('Android 12+ 跟随壁纸配色'),
                          value: s.useDynamicColor,
                          onChanged: s.setUseDynamicColor,
                        ),
                      ListTile(
                        leading: const Icon(Icons.colorize),
                        title: const Text('主题色'),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 4),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final c in const [
                                Color(0xFF3553A2), // 东大蓝（默认）
                                Color(0xFF1E7A5A),
                                Color(0xFFB4345C),
                                Color(0xFF8C3FA8),
                                Color(0xFF006874),
                                Color(0xFF7A5900),
                              ])
                                _SeedDot(
                                  color: c,
                                  selected: (isApple || !s.useDynamicColor) &&
                                      s.seedColor == c,
                                  onTap: () => s.setSeedColor(c),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 数据
          const SizedBox(height: 20),
          StaggerIn(
            index: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _GroupTitle('数据'),
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('数据来源'),
                        subtitle: Text('东北大学一号通门户（personal.neu.edu.cn）'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.explore_outlined),
                        title: const Text('离线演示数据'),
                        trailing: Text(
                          s.mode == SessionMode.demo ? '当前使用' : '未启用',
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurfaceVariant),
                        ),
                        onTap: () {
                          s.enterDemo();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已切换到离线演示数据')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (s.mode == SessionMode.live) ...[
            const SizedBox(height: 20),
            Panel(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Icon(Icons.logout, color: scheme.error),
                title: Text('退出登录', style: TextStyle(color: scheme.error)),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final wasMounted = context.mounted;
                  await s.logout();
                  if (wasMounted) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('已退出登录，已清除保存的凭证')),
                    );
                  }
                },
              ),
            ),
          ],

          const SizedBox(height: 24),
          Center(
            child: Text(
              '东大一号通 v1.2.0\n'
              '${isApple ? 'iOS 设计' : 'Material 3'} · ${demoNews.length} 条真实资讯快照',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.7,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 4, 9),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _SeedDot extends StatelessWidget {
  const _SeedDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const names = {
      0xFF3553A2: '东大蓝',
      0xFF1E7A5A: '松绿',
      0xFFB4345C: '玫红',
      0xFF8C3FA8: '紫藤',
      0xFF006874: '孔雀蓝',
      0xFF7A5900: '赭金'
    };
    return Semantics(
      label: '主题色：${names[color.toARGB32()]}',
      selected: selected,
      button: true,
      child: SizedBox(
        width: 48,
        height: 48,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(
              child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(
                      width: 3,
                      color: Theme.of(context).colorScheme.onSurface,
                    )
                  : null,
              boxShadow: selected
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.45), blurRadius: 8)
                    ]
                  : null,
            ),
            child: selected
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null,
          )),
        ),
      ),
    );
  }
}
