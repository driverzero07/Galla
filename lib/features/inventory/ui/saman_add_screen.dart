import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/constants.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/services/photo_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/barcode_scanner_page.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/inventory_repository.dart';
import 'saman_screen.dart' show unitLabel;
import 'stock_fix_sheet.dart';

/// Naya Saman / Saman badlo. Pass [itemId] to edit an existing item.
class SamanAddScreen extends ConsumerStatefulWidget {
  const SamanAddScreen({super.key, this.itemId});

  final String? itemId;

  @override
  ConsumerState<SamanAddScreen> createState() => _SamanAddScreenState();
}

class _SamanAddScreenState extends ConsumerState<SamanAddScreen> {
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  final _cost = TextEditingController();
  final _sale = TextEditingController();
  final _stock = TextEditingController();
  final _low = TextEditingController();

  String _unit = ItemUnit.kg;
  String? _photoPath;
  Item? _existing;
  bool _loading = false;
  bool _saving = false;
  String? _nameError;
  String? _costError;
  String? _saleError;
  String? _stockError;
  String? _lowError;

  bool get _isEdit => widget.itemId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _barcode, _cost, _sale, _stock, _low]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final item =
        await ref.read(appDatabaseProvider).inventoryDao.itemById(widget.itemId!);
    if (!mounted) return;
    if (item == null) {
      context.pop();
      return;
    }
    setState(() {
      _existing = item;
      _name.text = item.name;
      _barcode.text = item.barcode ?? '';
      _cost.text = formatPaisaPlain(item.costPrice);
      _sale.text = formatPaisaPlain(item.salePrice);
      _low.text = formatQtyPlain(item.lowStockLevel);
      _unit = item.unit;
      _photoPath = item.photoPath;
      _loading = false;
    });
  }

  Future<void> _takePhoto() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await ref.read(photoServiceProvider).takePhoto();
      if (path != null && mounted) setState(() => _photoPath = path);
    } catch (e) {
      if (kDebugMode) debugPrint('photo error: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.itemPhotoFailed)));
    }
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code != null && mounted) setState(() => _barcode.text = code);
  }

  /// Empty means 0. Returns null for something that is not a number.
  int? _money(TextEditingController c) =>
      c.text.trim().isEmpty ? 0 : parseRupeesToPaisa(c.text);
  int? _qty(TextEditingController c) =>
      c.text.trim().isEmpty ? 0 : parseQtyToMilli(c.text);

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final cost = _money(_cost);
    final sale = _money(_sale);
    final low = _qty(_low);
    final stock = _isEdit ? 0 : _qty(_stock);
    setState(() {
      _nameError = _name.text.trim().isEmpty ? l10n.itemNameRequired : null;
      _costError = cost == null ? l10n.itemInvalidNumber : null;
      _saleError = sale == null ? l10n.itemInvalidNumber : null;
      _lowError = low == null ? l10n.itemInvalidNumber : null;
      _stockError = stock == null ? l10n.itemInvalidNumber : null;
    });
    if (_nameError != null ||
        cost == null ||
        sale == null ||
        low == null ||
        stock == null) {
      return;
    }

    final input = ItemInput(
      name: _name.text,
      photoPath: _photoPath,
      barcode: _barcode.text,
      unit: _unit,
      costPrice: cost,
      salePrice: sale,
      lowStockLevel: low,
    );
    final repo = ref.read(inventoryRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await repo.updateItem(widget.itemId!, input);
      } else {
        await repo.createItem(input, openingStock: stock);
      }
      if (!mounted) return;
      router.pop();
    } on DuplicateBarcodeException catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.itemDuplicateBarcode)));
      if (mounted) router.pushReplacement('/saman/add?id=${e.existingItemId}');
    } on ItemValidationException {
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      if (kDebugMode) debugPrint('save item error: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.itemSaveFailed)));
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _fixStock(int current) async {
    final result = await showStockFixSheet(context, currentStock: current);
    if (result == null) return;
    await ref
        .read(inventoryRepositoryProvider)
        .adjustStock(widget.itemId!, result.newCount, result.reason);
  }

  Future<void> _toggleHidden() async {
    final router = GoRouter.of(context);
    await ref
        .read(inventoryRepositoryProvider)
        .setArchived(widget.itemId!, !(_existing?.isArchived ?? false));
    if (mounted) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GallaHeader(
              title: _isEdit ? l10n.itemEditTitle : l10n.itemNewTitle,
              showBack: true,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          GallaSizes.screenPadding, 4, GallaSizes.screenPadding, 16),
                      children: [
                        _topRow(l10n),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _numberCard(
                                label: l10n.itemCostRate,
                                controller: _cost,
                                prefix: 'Rs ',
                                error: _costError,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _numberCard(
                                label: l10n.itemSellRate,
                                controller: _sale,
                                prefix: 'Rs ',
                                error: _saleError,
                                highlight: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _stockCard(l10n)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _numberCard(
                                label: l10n.itemLowStockLevel,
                                controller: _low,
                                error: _lowError,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _unitPicker(l10n),
                        if (_isEdit) ...[
                          const SizedBox(height: 16),
                          GallaOutlineButton(
                            label: (_existing?.isArchived ?? false)
                                ? l10n.itemUnhide
                                : l10n.itemHide,
                            icon: (_existing?.isArchived ?? false)
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            onPressed: _toggleHidden,
                          ),
                        ],
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  GallaSizes.screenPadding, 8, GallaSizes.screenPadding, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: GallaColors.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(l10n.itemNoDeleteNote,
                            style: GallaText.caption),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GallaPrimaryButton(
                    label: l10n.save,
                    onPressed: (_saving || _loading) ? null : _save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topRow(AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Photo tile
        SizedBox(
          width: 104,
          height: 104,
          child: Material(
            color: GallaColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: GallaRadius.card,
              side: const BorderSide(color: GallaColors.ink, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _takePhoto,
              child: _photoPath == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_camera_outlined, size: 30),
                        const SizedBox(height: 6),
                        Text(l10n.itemPhoto,
                            style: GallaText.label
                                .copyWith(color: GallaColors.ink)),
                      ],
                    )
                  : Image.file(
                      File(_photoPath!),
                      fit: BoxFit.cover,
                      cacheWidth: 312,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                style: GallaText.display.copyWith(fontSize: 18),
                decoration: InputDecoration(
                  hintText: l10n.itemNameHint,
                  errorText: _nameError,
                ),
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _barcode,
                decoration: InputDecoration(
                  hintText: l10n.itemBarcodeHint,
                  suffixIcon: IconButton(
                    tooltip: l10n.itemBarcodeScan,
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scan,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _numberCard({
    required String label,
    required TextEditingController controller,
    String? prefix,
    String? error,
    bool highlight = false,
  }) {
    return GallaCard(
      color: highlight ? GallaColors.chip : null,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GallaText.label),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: GallaText.display.copyWith(fontSize: 22),
            decoration: InputDecoration(
              prefixText: prefix,
              errorText: error,
              filled: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: '0',
            ),
          ),
        ],
      ),
    );
  }

  /// New item: opening stock field. Existing item: live stock + fix button.
  Widget _stockCard(AppLocalizations l10n) {
    if (!_isEdit) {
      return _numberCard(
        label: l10n.itemStockNow,
        controller: _stock,
        error: _stockError,
      );
    }
    final dao = ref.read(appDatabaseProvider).inventoryDao;
    return GallaCard(
      padding: const EdgeInsets.all(12),
      child: StreamBuilder<int>(
        stream: dao.watchStockOf(widget.itemId!),
        builder: (context, snap) {
          final stock = snap.data ?? 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.itemStockNow, style: GallaText.label),
              const SizedBox(height: 6),
              Text(
                '${formatQty(stock)} ${unitLabel(l10n, _unit)}',
                style: GallaText.display.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () => _fixStock(stock),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: GallaSizes.touch),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.itemFixStock,
                      style: GallaText.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _unitPicker(AppLocalizations l10n) {
    final labels = {
      ItemUnit.kg: l10n.unitKg,
      ItemUnit.pack: l10n.unitPack,
      ItemUnit.dozen: l10n.unitDozen,
      ItemUnit.piece: l10n.unitPiece,
    };
    return Row(
      children: [
        for (final u in ItemUnit.all) ...[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Material(
                color: _unit == u ? GallaColors.ink : GallaColors.chip,
                borderRadius: GallaRadius.card,
                child: InkWell(
                  borderRadius: GallaRadius.card,
                  onTap: () => setState(() => _unit = u),
                  child: SizedBox(
                    height: 48,
                    child: Center(
                      child: Text(
                        labels[u]!,
                        style: GallaText.display.copyWith(
                          fontSize: 16,
                          color: _unit == u
                              ? GallaColors.lime
                              : GallaColors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
