import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_logo.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/auth_controller.dart';
import '../domain/auth_state.dart';
import 'pin_field.dart';

/// Daily login: phone + 4-digit PIN. Works fully offline.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late final TextEditingController _phone;
  final _pin = TextEditingController();
  bool _error = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider);
    _phone = TextEditingController(
      text: auth is AuthLocked ? displayPkPhone(auth.phone) : '',
    );
    // Rebuild so the button enables as soon as 4 digits are typed.
    _pin.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .unlock(phoneInput: _phone.text, pin: _pin.text);
    if (!mounted) return;
    if (!ok) {
      _pin.clear();
      setState(() {
        _error = true;
        _busy = false;
      });
    }
    // On success the router redirects to Home.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    const Center(child: GallaLogo(size: 96)),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(l10n.appName,
                          style: GallaText.display.copyWith(fontSize: 36)),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(l10n.tagline,
                          style: GallaText.body
                              .copyWith(color: GallaColors.muted)),
                    ),
                    const SizedBox(height: 40),
                    Text(l10n.phoneNumber, style: GallaText.label),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      style: GallaText.display.copyWith(fontSize: 20),
                      onChanged: (_) => setState(() => _error = false),
                    ),
                    const SizedBox(height: 24),
                    Text(l10n.pinLabel, style: GallaText.label),
                    const SizedBox(height: 8),
                    Center(
                      child: PinField(
                        controller: _pin,
                        onCompleted: (_) => FocusScope.of(context).unfocus(),
                      ),
                    ),
                    if (_error) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          l10n.wrongPinOrPhone,
                          style: GallaText.bodyMedium
                              .copyWith(color: GallaColors.danger),
                        ),
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check,
                            size: 16, color: GallaColors.muted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(l10n.worksOffline,
                              style: GallaText.caption),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GallaPrimaryButton(
                      label: l10n.openShop,
                      onPressed:
                          (_pin.text.length == 4 && !_busy) ? _submit : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
