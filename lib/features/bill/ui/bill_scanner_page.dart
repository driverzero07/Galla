import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/db/db_providers.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/domain/current_shop.dart';
import '../domain/bill_controller.dart';

/// Continuous barcode scanner for the bill. It stays open: every scan adds
/// the item to the cart, scanning the same item again adds one more.
class BillScannerPage extends ConsumerStatefulWidget {
  const BillScannerPage({super.key});

  @override
  ConsumerState<BillScannerPage> createState() => _BillScannerPageState();
}

class _BillScannerPageState extends ConsumerState<BillScannerPage> {
  final _controller = MobileScannerController();

  /// The same code is ignored for this long so one physical scan (which the
  /// camera sees many times a second) adds exactly one unit.
  static const _cooldown = Duration(milliseconds: 1500);

  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _message;
  bool _messageIsError = false;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .firstOrNull;
    if (code == null) return;
    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt) < _cooldown) return;
    _lastCode = code;
    _lastAt = now;

    _busy = true;
    final l10n = AppLocalizations.of(context);
    try {
      final shopId = ref.read(shopIdProvider);
      final item = await ref
          .read(appDatabaseProvider)
          .inventoryDao
          .itemByBarcode(shopId, code);
      if (!mounted) return;
      if (item == null || item.isArchived) {
        // Hidden items leave pickers (Part 0 rule 4).
        HapticFeedback.heavyImpact();
        setState(() {
          _message = l10n.billScanUnknown;
          _messageIsError = true;
        });
      } else {
        ref.read(billProvider.notifier).addItem(item);
        HapticFeedback.lightImpact();
        setState(() {
          _message = l10n.billScanAdded(item.name);
          _messageIsError = false;
        });
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(billProvider).lines.length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(GallaSizes.screenPadding, 12,
                  GallaSizes.screenPadding, 8),
              child: Row(
                children: [
                  // Imperative route: pop the Navigator directly.
                  GallaBackButton(
                      onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Expanded(
                    child:
                        Text(l10n.scanTitle, style: GallaText.heading),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: GallaSizes.screenPadding),
                child: ClipRRect(
                  borderRadius: GallaRadius.card,
                  child: MobileScanner(
                      controller: _controller, onDetect: _onDetect),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(GallaSizes.screenPadding),
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _messageIsError
                          ? GallaColors.dangerBg
                          : GallaColors.chip,
                      borderRadius: GallaRadius.card,
                    ),
                    child: Text(
                      _message ?? l10n.scanHint,
                      textAlign: TextAlign.center,
                      style: GallaText.bodyMedium.copyWith(
                          color: _messageIsError
                              ? GallaColors.danger
                              : GallaColors.ink),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.billScanCount(count), style: GallaText.caption),
                  const SizedBox(height: 8),
                  GallaPrimaryButton(
                    label: l10n.billScanDone,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
