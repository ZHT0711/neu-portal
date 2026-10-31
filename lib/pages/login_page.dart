import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_state.dart';
import '../core/portal_client.dart';
import 'shell.dart';

/// 统一身份认证登录页。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _sid = TextEditingController();
  final _pwd = TextEditingController();
  bool _remember = true;
  bool _keepLogin = true;
  bool _obscure = true;
  bool _loading = false;
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  Future<void> _loadRemembered() async {
    // 记住的账号存在本地偏好里（不存密码）。
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('cas.user');
    if (!mounted) return;
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        _sid.text = saved;
        _remember = true;
      });
    }
  }

  Future<void> _submit() async {
    if (_sid.text.trim().isEmpty || _pwd.text.isEmpty) {
      _toast('请输入学号/工号和密码');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final state = AppScope.of(context);
    try {
      await state.login(_sid.text.trim(), _pwd.text);
      final p = await SharedPreferences.getInstance();
      if (_remember) {
        await p.setString('cas.user', _sid.text.trim());
      } else {
        await p.remove('cas.user');
      }
      // 保持登录：凭证进本机安全存储，之后各系统 SSO 免登录、重启自动续登
      if (_keepLogin) {
        await state.saveCredentials(_sid.text.trim(), _pwd.text);
      } else {
        await state.clearCredentials();
      }
      if (!mounted) return;
      _toast('欢迎回来，${state.user.name}');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdaptiveShell()),
      );
    } on PortalException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('登录失败：网络不可达（校外请先连接 VPN），或试试离线体验');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _entrance.dispose();
    _sid.dispose();
    _pwd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width > 700;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 背景：品牌色渐变 + 装饰圆
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary,
                  Color.lerp(scheme.primary, Colors.black, 0.35)!,
                ],
              ),
            ),
          ),
          Positioned(
            right: -80,
            top: -60,
            child: _blob(260, Colors.white.withValues(alpha: 0.06)),
          ),
          Positioned(
            left: -70,
            bottom: 40,
            child: _blob(200, Colors.white.withValues(alpha: 0.05)),
          ),
          // 内容
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _entrance,
                  curve: Curves.easeOutCubic,
                ),
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: _entrance,
                    curve: Curves.easeOutCubic,
                  )),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 400 : 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Brand(),
                        const SizedBox(height: 26),
                        Card(
                          color: scheme.surface
                              .withValues(alpha: 0.96),
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '账号登录',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 18),
                                TextField(
                                  controller: _sid,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9]')),
                                  ],
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.badge_outlined),
                                    labelText: '学号 / 工号',
                                    hintText: '请输入你的学号',
                                  ),
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _pwd,
                                  obscureText: _obscure,
                                  onSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    prefixIcon:
                                        const Icon(Icons.lock_outline),
                                    labelText: '密码',
                                    suffixIcon: IconButton(
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                      icon: Icon(_obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    SizedBox(
                                      height: 32,
                                      child: Checkbox(
                                        value: _remember,
                                        onChanged: (v) =>
                                            setState(() => _remember = v ?? true),
                                      ),
                                    ),
                                    const Text('记住账号',
                                        style: TextStyle(fontSize: 13)),
                                    const Spacer(),
                                    SizedBox(
                                      height: 32,
                                      child: Checkbox(
                                        value: _keepLogin,
                                        onChanged: (v) =>
                                            setState(() => _keepLogin = v ?? true),
                                      ),
                                    ),
                                    const Text('保持登录',
                                        style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                FilledButton(
                                  onPressed: _loading ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _loading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2.4),
                                        )
                                      : const Text(
                                          '登  录',
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600),
                                        ),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _loading
                                      ? null
                                      : () {
                                          AppScope.of(context).enterDemo();
                                          Navigator.of(context).pushReplacement(
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    const AdaptiveShell()),
                                          );
                                        },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  icon: const Icon(Icons.explore_outlined,
                                      size: 18),
                                  label: const Text('离线体验（演示数据）'),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '使用学校统一身份认证（CAS）账号登录，'
                                  '密码仅用于本次认证，不会被存储。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '东北大学 NORTHEASTERN UNIVERSITY\n'
                          '沈阳市和平区文化路三号巷11号',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.6,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size),
        ),
      );
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: const Icon(Icons.account_balance,
              color: Colors.white, size: 34),
        ),
        const SizedBox(height: 14),
        const Text(
          '统一身份认证',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'NORTHEASTERN UNIVERSITY UNIFORM IDENTITY AUTHENTICATION',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.66),
            fontSize: 9,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}
