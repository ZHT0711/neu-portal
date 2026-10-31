import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../core/platform_style.dart';
import '../widgets/common.dart';
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

class _LoginPageState extends State<LoginPage> {
  final _sid = TextEditingController();
  final _pwd = TextEditingController();
  bool _remember = true;
  bool _keepLogin = true;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

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
    if (_loading) return;
    if (_sid.text.trim().isEmpty || _pwd.text.isEmpty) {
      setState(() => _error = '请输入学号/工号和密码');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
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
      _finish();
    } on PortalException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '暂时无法登录，请检查网络；校外请先连接 VPN。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _finish() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacement(
          MaterialPageRoute(builder: (_) => const AdaptiveShell()));
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
    _sid.dispose();
    _pwd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const PageAppBar(title: '统一身份认证'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(24)),
                            child: Icon(
                                isApple
                                    ? CupertinoIcons.building_2_fill
                                    : Icons.account_balance,
                                color: scheme.onPrimaryContainer,
                                size: 32),
                          )),
                      const SizedBox(height: 24),
                      Text('连接你的校园生活', style: text.headlineMedium),
                      const SizedBox(height: 8),
                      Text('使用东北大学统一身份认证账号登录',
                          style: text.bodyLarge
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 28),
                      Panel(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            _field(
                                controller: _sid,
                                label: '学号 / 工号',
                                autofillHints: const [AutofillHints.username],
                                action: TextInputAction.next),
                            const SizedBox(height: 16),
                            _field(
                                controller: _pwd,
                                label: '密码',
                                autofillHints: const [AutofillHints.password],
                                password: true,
                                action: TextInputAction.done),
                          ])),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('记住账号'),
                        value: _remember,
                        onChanged: _loading
                            ? null
                            : (value) => setState(() => _remember = value),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('保持登录'),
                        subtitle: const Text('凭证加密保存在本机，可随时退出并清除'),
                        value: _keepLogin,
                        onChanged: _loading
                            ? null
                            : (value) => setState(() => _keepLogin = value),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Semantics(
                              liveRegion: true,
                              child: Text(_error!,
                                  style: text.bodyMedium
                                      ?.copyWith(color: scheme.error))),
                        ),
                      const SizedBox(height: 20),
                      AdaptiveFilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                    SizedBox(
                                        width: 18,
                                        height: 18,
                                        child:
                                            CircularProgressIndicator.adaptive(
                                                strokeWidth: 2)),
                                    SizedBox(width: 12),
                                    Text('正在登录…'),
                                  ])
                            : const Text('登录'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                AppScope.of(context).enterDemo();
                                _finish();
                              },
                        child: const Text('先体验离线演示'),
                      ),
                      const SizedBox(height: 16),
                      Text('未开启保持登录时，密码仅用于本次认证。',
                          textAlign: TextAlign.center,
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
      {required TextEditingController controller,
      required String label,
      required List<String> autofillHints,
      required TextInputAction action,
      bool password = false}) {
    final toggle = password
        ? IconButton(
            tooltip: _obscure ? '显示密码' : '隐藏密码',
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(_obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
          )
        : null;
    if (isApple) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        CupertinoTextField(
          controller: controller,
          placeholder: label,
          enabled: !_loading,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          obscureText: password && _obscure,
          suffix: toggle,
          autofillHints: autofillHints,
          textInputAction: action,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType:
              password ? TextInputType.visiblePassword : TextInputType.text,
          onSubmitted: (_) {
            if (password) {
              _submit();
            } else {
              FocusScope.of(context).nextFocus();
            }
          },
        ),
      ]);
    }
    return TextField(
      controller: controller,
      enabled: !_loading,
      obscureText: password && _obscure,
      autofillHints: autofillHints,
      textInputAction: action,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: label, suffixIcon: toggle),
      onSubmitted: (_) {
        if (password) _submit();
      },
    );
  }
}
