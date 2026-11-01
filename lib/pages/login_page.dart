import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_state.dart';
import '../core/cas_crypto.dart';
import '../core/platform_style.dart';
import '../core/portal_client.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'webview_page.dart';

/// 统一身份认证登录页。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _sid = TextEditingController();
  final _pwd = TextEditingController();
  final _graphic = TextEditingController();
  final _sms = TextEditingController();
  bool _remember = true;
  bool _keepLogin = true;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  // 新设备短信二次认证
  bool _secondAuth = false;
  bool _smsRequested = false;
  bool _secondAuthLoading = false;
  String? _secondAuthError;
  Uint8List? _captchaBytes;

  @override
  void initState() {
    super.initState();
    _sid.addListener(() => setState(() {}));
    _graphic.addListener(() => setState(() {}));
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
    final sid = _sid.text.trim();
    if (sid.isEmpty || _pwd.text.isEmpty) {
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
      await state.login(sid, _pwd.text);
      final p = await SharedPreferences.getInstance();
      if (_remember) {
        await p.setString('cas.user', sid);
      } else {
        await p.remove('cas.user');
      }
      // 保持登录：凭证进本机安全存储，之后各系统 SSO 免登录、重启自动续登
      if (_keepLogin) {
        await state.saveCredentials(sid, _pwd.text);
      } else {
        await state.clearCredentials();
      }
      if (!mounted) return;
      _toast('欢迎回来，${state.user.name}');
      _finish();
    } on SecondAuthRequired {
      // 新设备二次认证：切换到图形码 + 短信验证面板
      if (mounted) {
        setState(() {
          _secondAuth = true;
          _error = null;
        });
        _loadCaptcha();
      }
    } on PortalException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            '暂时无法连接门户服务。若当前处于 5G/4G 或校外网络，请连接校园 WebVPN 或切换至校园 WiFi。');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCaptcha() async {
    setState(() => _secondAuthError = null);
    final state = AppScope.of(context);
    try {
      await state.loadSecondAuthCaptcha();
      if (!mounted) return;
      setState(() => _captchaBytes = state.secondAuthCaptcha);
    } catch (e) {
      if (mounted) setState(() => _secondAuthError = e.toString());
    }
  }

  Future<void> _sendSms() async {
    if (_secondAuthLoading) return;
    setState(() {
      _secondAuthLoading = true;
      _secondAuthError = null;
    });
    final state = AppScope.of(context);
    try {
      await state.requestSecondAuthSMS(_graphic.text.trim());
      if (!mounted) return;
      setState(() => _smsRequested = true);
    } catch (e) {
      if (mounted) setState(() => _secondAuthError = e.toString());
      await _loadCaptcha();
    } finally {
      if (mounted) setState(() => _secondAuthLoading = false);
    }
  }

  Future<void> _verify() async {
    if (_secondAuthLoading) return;
    setState(() {
      _secondAuthLoading = true;
      _secondAuthError = null;
    });
    final state = AppScope.of(context);
    try {
      await state.completeSecondAuth(_sms.text.trim());
      final p = await SharedPreferences.getInstance();
      if (_remember) {
        await p.setString('cas.user', _sid.text.trim());
      } else {
        await p.remove('cas.user');
      }
      if (_keepLogin) {
        await state.saveCredentials(_sid.text.trim(), _pwd.text);
      } else {
        await state.clearCredentials();
      }
      if (!mounted) return;
      _toast('欢迎回来，${state.user.name}');
      _finish();
    } catch (e) {
      if (mounted) setState(() => _secondAuthError = e.toString());
      _sms.clear();
    } finally {
      if (mounted) setState(() => _secondAuthLoading = false);
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
    _graphic.dispose();
    _sms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final sidText = _sid.text.trim();
    final looksLikePhone = RegExp(r'^1[3-9]\d{9,10}$').hasMatch(sidText);

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
                      if (_secondAuth) ...[
                        _secondAuthPanel(scheme, text),
                      ] else ...[
                      Panel(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            _field(
                                controller: _sid,
                                label: '学号 / 工号',
                                hint: '本科生/研究生学号或8位工号',
                                autofillHints: const [AutofillHints.username],
                                action: TextInputAction.next),
                            if (looksLikePhone)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '⚠️ 统一身份认证账号为学号或8位工号，不支持手机号密码登录。手机号请点击下方“网页版认证”。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.error,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
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
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: scheme.error.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline,
                                  size: 18, color: scheme.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _error!,
                                      style: text.bodySmall?.copyWith(
                                        color: scheme.onErrorContainer,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (_error!.contains('WebVPN') ||
                                        _error!.contains('VPN') ||
                                        _error!.contains('5G')) ...[
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          visualDensity:
                                              VisualDensity.compact,
                                          foregroundColor: scheme.error,
                                        ),
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const WebViewPage(
                                                url:
                                                    'https://webvpn.neu.edu.cn',
                                                title: '东北大学 WebVPN',
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.vpn_lock,
                                            size: 16),
                                        label: const Text(
                                          '前往东北大学 WebVPN 认证',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
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
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const WebViewPage(
                                      url: kNeuCasLoginUrl,
                                      title: '统一身份认证',
                                      loginMode: true,
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.open_in_browser, size: 18),
                        label: const Text('通过网页版登录（支持短信/扫码）'),
                      ),
                      const SizedBox(height: 10),
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
                      Text(
                          '💡 提示：在校外或使用 5G/4G 蜂窝网络时，CAS 会限制公网直接鉴权；建议连接校园 WebVPN 或切换至校园 WiFi。\n教职工账号不足8位的请前置补0（如00007826）；秦皇岛分校前置加1补齐。',
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

  /// 新设备短信二次认证面板：图形码 → 发送短信 → 短信验证码 → 完成登录。
  Widget _secondAuthPanel(ColorScheme scheme, TextTheme text) {
    return Panel(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.shield_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text('新设备短信验证', style: text.titleMedium),
              ]),
              const SizedBox(height: 8),
              Text(
                '检测到新设备登录，需要完成短信二次认证：先输入图片中的图形码获取短信，再填入短信验证码。',
                style: text.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Row(children: [
                GestureDetector(
                  onTap: _secondAuthLoading ? null : _loadCaptcha,
                  child: Container(
                    width: 110,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _captchaBytes != null
                        ? Image.memory(_captchaBytes!, fit: BoxFit.contain)
                        : const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _graphic,
                    enabled: !_secondAuthLoading,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: '图形码'),
                    onSubmitted: (_) => _sendSms(),
                  ),
                ),
                IconButton(
                  tooltip: '刷新图形码',
                  onPressed: _secondAuthLoading ? null : _loadCaptcha,
                  icon: const Icon(Icons.refresh),
                ),
              ]),
              const SizedBox(height: 16),
              if (_smsRequested) ...[
                TextField(
                  controller: _sms,
                  enabled: !_secondAuthLoading,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '短信验证码'),
                ),
                const SizedBox(height: 16),
                AdaptiveFilledButton(
                  onPressed: _secondAuthLoading ? null : _verify,
                  child: _secondAuthLoading
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator.adaptive(
                                  strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('正在验证…'),
                        ])
                      : const Text('验证并登录'),
                ),
              ] else
                AdaptiveFilledButton(
                  onPressed: (_secondAuthLoading || _graphic.text.trim().isEmpty)
                      ? null
                      : _sendSms,
                  child: _secondAuthLoading
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator.adaptive(
                                  strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('正在发送短信…'),
                        ])
                      : const Text('发送短信验证码'),
                ),
              if (_secondAuthError != null) ...[
                const SizedBox(height: 12),
                Text(_secondAuthError!,
                    style: text.bodySmall?.copyWith(color: scheme.error)),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: _secondAuthLoading
                    ? null
                    : () => setState(() {
                          _secondAuth = false;
                          _smsRequested = false;
                          _secondAuthError = null;
                          _sms.clear();
                          _graphic.clear();
                          _captchaBytes = null;
                        }),
                child: const Text('返回重新登录'),
              ),
            ]));
  }

  Widget _field(
      {required TextEditingController controller,
      required String label,
      String? hint,
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
        Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            if (hint != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CupertinoColors.secondaryLabel,
                        fontSize: 12,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
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
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        suffixIcon: toggle,
      ),
      onSubmitted: (_) {
        if (password) _submit();
      },
    );
  }
}
