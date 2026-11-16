import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_buttons.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/party_repository.dart';

/// Opens the add form ([partyId] null) or the edit form for a customer or
/// supplier. Resolves to the saved party's id, or null if dismissed.
Future<String?> showPartyForm(
  BuildContext context, {
  required PartyKind kind,
  String? partyId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PartyForm(kind: kind, partyId: partyId),
  );
}

class _PartyForm extends ConsumerStatefulWidget {
  const _PartyForm({required this.kind, this.partyId});

  final PartyKind kind;
  final String? partyId;

  @override
  ConsumerState<_PartyForm> createState() => _PartyFormState();
}

class _PartyFormState extends ConsumerState<_PartyForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _opening = TextEditingController();
  String? _nameError;
  String? _openingError;
  bool _loading = false;
  bool _saving = false;
  bool _archived = false;

  bool get _isEdit => widget.partyId != null;
  bool get _isCustomer => widget.kind == PartyKind.customer;

  PartyRepository get _repo => _isCustomer
      ? ref.read(customerRepositoryProvider)
      : ref.read(supplierRepositoryProvider);

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
    _name.dispose();
    _phone.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final info = await _repo.info(widget.partyId!);
    if (!mounted) return;
    if (info == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _name.text = info.name;
      _phone.text = info.phone ?? '';
      _archived = info.isArchived;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final opening =
        _opening.text.trim().isEmpty ? 0 : parseRupeesToPaisa(_opening.text);
    setState(() {
      _nameError = _name.text.trim().isEmpty ? l10n.partyNameRequired : null;
      _openingError = opening == null ? l10n.itemInvalidNumber : null;
    });
    if (_nameError != null || opening == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final String id;
      if (_isEdit) {
        await _repo.update(widget.partyId!,
            name: _name.text, phone: _phone.text);
        id = widget.partyId!;
      } else {
        id = await _repo.create(
            name: _name.text, phone: _phone.text, openingBalance: opening);
      }
      if (mounted) nav.pop(id);
    } catch (e) {
      if (kDebugMode) debugPrint('save party error: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.partySaveFailed)));
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleHidden() async {
    final nav = Navigator.of(context);
    await _repo.setArchived(widget.partyId!, !_archived);
    if (mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = _isCustomer
        ? (_isEdit ? l10n.customerEditTitle : l10n.customerNewTitle)
        : (_isEdit ? l10n.supplierEditTitle : l10n.supplierNewTitle);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        GallaSizes.screenPadding,
        0,
        GallaSizes.screenPadding,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: _loading
          ? const SizedBox(
              height: 160, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: GallaText.heading),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _name,
                    autofocus: !_isEdit,
                    textCapitalization: TextCapitalization.words,
                    style: GallaText.display.copyWith(fontSize: 18),
                    decoration: InputDecoration(
                      labelText: l10n.partyNameLabel,
                      errorText: _nameError,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration:
                        InputDecoration(labelText: l10n.partyPhoneLabel),
                  ),
                  if (!_isEdit) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _opening,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: InputDecoration(
                        labelText: _isCustomer
                            ? l10n.partyOpeningCustomer
                            : l10n.partyOpeningSupplier,
                        prefixText: 'Rs ',
                        errorText: _openingError,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  GallaPrimaryButton(
                    label: l10n.save,
                    onPressed: _saving ? null : _save,
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 10),
                    GallaOutlineButton(
                      label: _archived ? l10n.partyUnhide : l10n.partyHide,
                      icon: _archived
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      onPressed: _toggleHidden,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
