import 'package:flutter/material.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/features/login/qingshuihepan_login_service.dart';
import 'package:river/core/widgets/river_snack_bar.dart';

Future<UserAccount?> showQingShuiHePanCredentialLoginSheet({
  required BuildContext context,
  required AppDependencies dependencies,
}) {
  return showModalBottomSheet<UserAccount>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _QingShuiHePanCredentialLoginSheet(dependencies: dependencies),
  );
}

class _QingShuiHePanCredentialLoginSheet extends StatelessWidget {
  const _QingShuiHePanCredentialLoginSheet({required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return Padding(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: _QingShuiHePanCredentialLoginSheetBody(
              dependencies: dependencies,
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }
}

class _QingShuiHePanCredentialLoginSheetBody extends StatefulWidget {
  const _QingShuiHePanCredentialLoginSheetBody({
    required this.dependencies,
    required this.onClose,
  });

  final AppDependencies dependencies;
  final VoidCallback onClose;

  @override
  State<_QingShuiHePanCredentialLoginSheetBody> createState() =>
      _QingShuiHePanCredentialLoginSheetBodyState();
}

class _QingShuiHePanCredentialLoginSheetBodyState
    extends State<_QingShuiHePanCredentialLoginSheetBody> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final QingShuiHePanLoginService _service = const QingShuiHePanLoginService();

  bool _submitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (_submitting) {
      return;
    }
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final result = await _service.login(
        username: _accountController.text.trim(),
        password: _passwordController.text,
      );

      await widget.dependencies.accountStore.upsertQingShuiHePanAccount(
        result.account,
      );
      await widget.dependencies.accountStore.upsertQingShuiHePanAuth(
        result.auth,
      );
      await widget.dependencies.accountStore.switchActiveQingShuiHePanAccount(
        result.account.username,
      );
      await widget.dependencies.accountStore.setGuestBrowsing(false);

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop<UserAccount>(result.account);
    } on QingShuiHePanLoginException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar('登录失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.9),
            theme.colorScheme.surface,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Image.asset(
                      'assets/images/hp.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.school_rounded,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '登录清水河畔',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '使用账号密码登录到清水河畔',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _accountController,
                      enabled: !_submitting,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '账号',
                        hintText: '请输入清水河畔账号',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入账号';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_submitting,
                      obscureText: _obscurePassword,
                      onFieldSubmitted: (_) => _submitLogin(),
                      decoration: InputDecoration(
                        labelText: '密码',
                        hintText: '请输入密码',
                        prefixIcon: const Icon(Icons.password_rounded),
                        suffixIcon: IconButton(
                          onPressed: _submitting
                              ? null
                              : () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入密码';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submitLogin,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: Text(_submitting ? '登录中...' : '登录并继续'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
