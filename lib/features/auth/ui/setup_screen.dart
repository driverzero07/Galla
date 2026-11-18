import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_logo.dart';
import '../../../core/utils/money.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/otp_provider.dart';
import '../data/restore_service.dart';
import '../domain/auth_controller.dart';
import 'pin_field.dart';

enum _Step { phone, otp, shopName, openingCash, pin, pinConfirm }

/// First-time setup: phone + OTP (once), shop name, then a 4-digit PIN.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  _Step _step = _Step.phone;
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _shop = TextEditingController();
  final _cash = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();

  String? _phoneE164;
  String? _shopId;
  String? _firstPin;
  bool _restored = false;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_phone, _otp, _shop, _cash, _pin, _pinConfirm]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_phone, _otp, _shop, _cash, _pin, _pinConfirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action, String failMessage) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (kDebugMode) debugPrint('setup error: $e');
      if (mounted) setState(() => _error = failMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOtp() async {
    final l10n = AppLocalizations.of(context);
    final e164 = normalizePkPhone(_phone.text);
    if (e164 == null) {
      setState(() => _error = l10n.invalidPhone);
      return;
    }
    await _guard(() async {
      await ref.read(otpProviderProvider).sendOtp(e164);
      _phoneE164 = e164;
      if (mounted) setState(() => _step = _Step.otp);
    }, l10n.setupSendFailed);
  }

  Future<void> _verifyOtp() async {
    final l10n = AppLocalizations.of(context);
    _shopId = null;
    await _guard(() async {
      _shopId = await ref
          .read(otpProviderProvider)
          .verifyOtp(_phoneE164!, _otp.text.trim());
    }, l10n.setupWrongOtp);
    final shopId = _shopId;
    if (shopId == null) return;

    // A phone that logs in to an existing shop gets everything back from
    // the server; only a brand new shop asks for a name.
    await _guard(() async {
      final restored =
          await ref.read(restoreServiceProvider).restoreIfExists(shopId);
      if (!mounted) return;
      setState(() {
        _restored = restored;
        _step = restored ? _Step.pin : _Step.shopName;
      });
    }, l10n.setupRestoreFailed);
  }

  void _shopNameDone() {
    final l10n = AppLocalizations.of(context);
    if (_shop.text.trim().isEmpty) {
      setState(() => _error = l10n.setupShopNameRequired);
      return;
    }
    setState(() {
      _error = null;
      _step = _Step.openingCash;
    });
  }

  /// Cash in the drawer today; blank means nothing yet.
  int? get _openingCashPaisa {
    final t = _cash.text.trim();
    return t.isEmpty ? 0 : parseRupeesToPaisa(t);
  }

  void _openingCashDone() {
    final l10n = AppLocalizations.of(context);
    final v = _openingCashPaisa;
    if (v == null || v < 0) {
      setState(() => _error = l10n.setupCashInvalid);
      return;
    }
    setState(() {
      _error = null;
      _step = _Step.pin;
    });
  }

  void _pinEntered(String pin) {
    FocusScope.of(context).unfocus();
    setState(() {
      _firstPin = pin;
      _step = _Step.pinConfirm;
    });
  }

  Future<void> _pinConfirmed(String pin) async {
    final l10n = AppLocalizations.of(context);
    if (pin != _firstPin) {
      _pin.clear();
      _pinConfirm.clear();
      setState(() {
        _firstPin = null;
        _step = _Step.pin;
        _error = l10n.setupPinMismatch;
      });
      return;
    }
    await _guard(() async {
      final auth = ref.read(authControllerProvider.notifier);
      if (_restored) {
        await auth.completeRestore(
            shopId: _shopId!, phone: _phoneE164!, pin: pin);
      } else {
        await auth.completeSetup(
          shopId: _shopId!,
          phone: _phoneE164!,
          shopName: _shop.text.trim(),
          pin: pin,
          openingCash: _openingCashPaisa ?? 0,
        );
      }
      // Router redirects to Home once the controller unlocks.
    }, l10n.setupFailed);
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
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    const Center(child: GallaLogo(size: 80)),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(l10n.appName,
                          style: GallaText.display.copyWith(fontSize: 32)),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(l10n.tagline,
                          style: GallaText.body
                              .copyWith(color: GallaColors.muted)),
                    ),
                    const SizedBox(height: 32),
                    ..._stepBody(l10n),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: GallaText.bodyMedium
                            .copyWith(color: GallaColors.danger),
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(height: 24),
                    ..._stepButton(l10n),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _stepBody(AppLocalizations l10n) {
    switch (_step) {
      case _Step.phone:
        return [
          Text(l10n.phoneNumber, style: GallaText.label),
          const SizedBox(height: 8),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofocus: true,
            style: GallaText.display.copyWith(fontSize: 20),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
          Text(l10n.setupFirstTimeNote, style: GallaText.caption),
        ];
      case _Step.otp:
        return [
          Text(l10n.setupOtpSent(displayPkPhone(_phoneE164 ?? '')),
              style: GallaText.body),
          const SizedBox(height: 16),
          Text(l10n.setupOtpLabel, style: GallaText.label),
          const SizedBox(height: 8),
          TextField(
            controller: _otp,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: GallaText.display.copyWith(fontSize: 24, letterSpacing: 6),
            onChanged: (_) => setState(() => _error = null),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            Text(l10n.setupRestoring, style: GallaText.caption),
          ],
          if (kDebugMode &&
              ref.read(otpProviderProvider) is DebugOtpProvider) ...[
            const SizedBox(height: 8),
            // Debug builds only (fake OTP provider).
            const Text('Debug: code 123456', style: GallaText.caption),
          ],
        ];
      case _Step.shopName:
        return [
          Text(l10n.setupShopNameLabel, style: GallaText.label),
          const SizedBox(height: 8),
          TextField(
            controller: _shop,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: GallaText.display.copyWith(fontSize: 20),
            decoration: InputDecoration(hintText: l10n.setupShopNameHint),
            onChanged: (_) => setState(() => _error = null),
          ),
        ];
      case _Step.openingCash:
        return [
          Text(l10n.setupCashLabel, style: GallaText.label),
          const SizedBox(height: 8),
          TextField(
            controller: _cash,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GallaText.display.copyWith(fontSize: 20),
            decoration: InputDecoration(prefixText: 'Rs ', hintText: '0'),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 8),
          Text(l10n.setupCashHelp, style: GallaText.body),
        ];
      case _Step.pin:
        return [
          if (_restored) ...[
            Center(child: Text(l10n.setupRestored, style: GallaText.bodyMedium)),
            const SizedBox(height: 8),
          ],
          Center(child: Text(l10n.setupPinTitle, style: GallaText.label)),
          const SizedBox(height: 12),
          PinField(
            key: const ValueKey('setup-pin'),
            controller: _pin,
            autofocus: true,
            onCompleted: _pinEntered,
          ),
        ];
      case _Step.pinConfirm:
        return [
          Center(child: Text(l10n.setupPinConfirm, style: GallaText.label)),
          const SizedBox(height: 12),
          PinField(
            key: const ValueKey('setup-pin-confirm'),
            controller: _pinConfirm,
            autofocus: true,
            onCompleted: _pinConfirmed,
          ),
        ];
    }
  }

  List<Widget> _stepButton(AppLocalizations l10n) {
    switch (_step) {
      case _Step.phone:
        return [
          GallaPrimaryButton(
            label: l10n.setupSendOtp,
            onPressed: (!_busy && _phone.text.trim().isNotEmpty)
                ? _sendOtp
                : null,
          ),
        ];
      case _Step.otp:
        return [
          GallaPrimaryButton(
            label: l10n.setupOtpVerify,
            onPressed:
                (!_busy && _otp.text.trim().length >= 4) ? _verifyOtp : null,
          ),
        ];
      case _Step.shopName:
        return [
          GallaPrimaryButton(
            label: l10n.setupNext,
            onPressed: _busy ? null : _shopNameDone,
          ),
        ];
      case _Step.openingCash:
        return [
          GallaPrimaryButton(
            label: l10n.setupNext,
            onPressed: _busy ? null : _openingCashDone,
          ),
        ];
      case _Step.pin:
      case _Step.pinConfirm:
        return const []; // PIN steps advance automatically at 4 digits.
    }
  }
}
