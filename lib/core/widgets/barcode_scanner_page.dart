import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/gen/app_localizations.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import 'galla_header.dart';

/// Full-screen camera scanner. Pops with the first barcode read, or null if
/// the user goes back. Part 3 reuses this for scanning items into a bill.
class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final value = b.rawValue;
      if (value != null && value.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  GallaSizes.screenPadding, 12, GallaSizes.screenPadding, 8),
              child: Row(
                children: [
                  // Plain Navigator pop: this route is pushed imperatively.
                  GallaBackButton(
                      onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Text(l10n.scanTitle, style: GallaText.heading),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(GallaSizes.screenPadding),
                child: ClipRRect(
                  borderRadius: GallaRadius.card,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                          controller: _controller, onDetect: _onDetect),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          color: GallaColors.ink.withValues(alpha: 0.7),
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            l10n.scanHint,
                            textAlign: TextAlign.center,
                            style: GallaText.bodyMedium
                                .copyWith(color: GallaColors.lime),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the scanner and returns the scanned code (or null).
Future<String?> scanBarcode(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
  );
}
