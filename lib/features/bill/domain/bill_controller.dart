import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../data/sales_repository.dart';
import 'bill_math.dart';
import 'cart.dart';

/// Holds the bill being built. Every change is written to a local draft so a
/// killed app or dead battery loses nothing; the draft is cleared when the
/// bill is saved or discarded.
class BillController extends Notifier<BillState> {
  BillDraftStore get _drafts => ref.read(billDraftStoreProvider);

  @override
  BillState build() {
    unawaited(Future.microtask(_restore));
    return const BillState.loading();
  }

  Future<void> _restore() async {
    BillState restored = const BillState();
    try {
      final json = await _drafts.load();
      if (json != null) restored = BillState.fromJsonString(json);
    } catch (_) {
      // A broken draft must never stop billing.
    }
    // Only apply if nothing was added while we were reading.
    if (!state.loaded) state = restored;
  }

  void _commit(BillState next) {
    state = next;
    if (next.isEmpty && !next.hasRealCustomer) {
      unawaited(_drafts.clear());
    } else {
      unawaited(_drafts.save(next.toJsonString()));
    }
  }

  BillState get _s => state.loaded ? state : const BillState();

  /// Scanning or tapping the same item again adds [qty] more (default 1).
  void addItem(Item item, {int qty = 1000}) {
    final s = _s;
    final i = s.lines.indexWhere((l) => l.itemId == item.id);
    if (i >= 0) {
      final lines = [...s.lines];
      lines[i] = lines[i].copyWith(qty: lines[i].qty + qty);
      _commit(s.copyWith(lines: lines));
    } else {
      _commit(s.copyWith(lines: [
        ...s.lines,
        CartLine(
          itemId: item.id,
          name: item.name,
          unit: item.unit,
          photoPath: item.photoPath,
          qty: qty,
          unitPrice: item.salePrice,
          listPrice: item.salePrice,
        ),
      ]));
    }
  }

  /// Plus: one more unit.
  void increment(String itemId) => _change(itemId, 1000);

  /// Minus: one less unit; the row disappears when nothing is left.
  void decrement(String itemId) => _change(itemId, -1000);

  void _change(String itemId, int delta) {
    final s = _s;
    final i = s.lines.indexWhere((l) => l.itemId == itemId);
    if (i < 0) return;
    final qty = s.lines[i].qty + delta;
    if (qty <= 0) return remove(itemId);
    final lines = [...s.lines];
    lines[i] = lines[i].copyWith(qty: qty);
    _commit(s.copyWith(lines: lines));
  }

  /// Number pad entry, e.g. 2.5 kg. Zero or less removes the row.
  void setQty(String itemId, int qty) {
    final s = _s;
    final i = s.lines.indexWhere((l) => l.itemId == itemId);
    if (i < 0) return;
    if (qty <= 0) return remove(itemId);
    final lines = [...s.lines];
    lines[i] = lines[i].copyWith(qty: qty);
    _commit(s.copyWith(lines: lines));
  }

  /// Overrides the price for THIS bill only; the item's price is untouched.
  void setPrice(String itemId, int unitPrice) {
    if (unitPrice < 0) return;
    final s = _s;
    final i = s.lines.indexWhere((l) => l.itemId == itemId);
    if (i < 0) return;
    final lines = [...s.lines];
    lines[i] = lines[i].copyWith(unitPrice: unitPrice);
    _commit(s.copyWith(lines: lines));
  }

  void remove(String itemId) {
    final s = _s;
    _commit(
        s.copyWith(lines: [for (final l in s.lines) if (l.itemId != itemId) l]));
  }

  /// Flat bill discount; clamped to the subtotal when read.
  void setDiscount(int discount) {
    _commit(_s.copyWith(discount: discount < 0 ? 0 : discount));
  }

  void setCustomer(String? id, String? name) {
    final s = _s;
    if (id == null) {
      // Back to Naqad customer: udhaar is no longer allowed.
      _commit(s.copyWith(clearCustomer: true, credit: false, paidNow: 0));
    } else {
      _commit(s.copyWith(customerId: id, customerName: name));
    }
  }

  /// Switch Nakad / Udhaar. Udhaar is ignored without a real customer; the
  /// screen opens the customer picker first.
  void setCredit(bool credit) {
    final s = _s;
    if (credit && !s.hasRealCustomer) return;
    _commit(s.copyWith(credit: credit, paidNow: credit ? s.paidNow : 0));
  }

  /// "Abhi kitne diye" (paisa).
  void setPaidNow(int paid) {
    _commit(_s.copyWith(paidNow: paid < 0 ? 0 : paid));
  }

  /// After a successful save or when the shopkeeper throws the bill away.
  Future<void> clear() async {
    state = const BillState();
    await _drafts.clear();
  }

  /// The cart as input for the repository.
  BillInput toInput() {
    final s = state;
    return BillInput(
      lines: [
        for (final l in s.lines)
          BillLineInput(itemId: l.itemId, qty: l.qty, unitPrice: l.unitPrice),
      ],
      discount: s.effectiveDiscount,
      customerId: s.customerId,
      credit: s.credit,
      paidNow: s.paidNow,
    );
  }

  PaymentResolution get payment => state.payment;
}

final billProvider =
    NotifierProvider<BillController, BillState>(BillController.new);
