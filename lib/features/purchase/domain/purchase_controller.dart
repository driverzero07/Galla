import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../bill/domain/bill_math.dart';
import '../data/purchase_repository.dart';

class PurchaseLineState {
  const PurchaseLineState({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.qty,
    required this.unitCost,
    this.photoPath,
  });

  final String itemId;
  final String name;
  final String unit;
  final int qty;
  final int unitCost;
  final String? photoPath;

  int get total => lineTotal(qty, unitCost);

  PurchaseLineState copyWith({int? qty, int? unitCost}) => PurchaseLineState(
        itemId: itemId,
        name: name,
        unit: unit,
        qty: qty ?? this.qty,
        unitCost: unitCost ?? this.unitCost,
        photoPath: photoPath,
      );
}

/// The purchase being typed. Kept in memory (it survives switching tabs, not
/// closing the app). Totals are always computed, never typed.
class PurchaseDraft {
  const PurchaseDraft({
    this.supplierId,
    this.supplierName,
    this.lines = const [],
    this.paidNow = 0,
    this.invoicePath,
  });

  final String? supplierId;
  final String? supplierName;
  final List<PurchaseLineState> lines;
  final int paidNow;
  final String? invoicePath;

  int get total => lines.fold<int>(0, (s, l) => s + l.total);
  int get effectivePaid => paidNow > total ? total : paidNow;

  /// What this purchase adds to what we owe the supplier.
  int get unpaid => total - effectivePaid;

  bool get isEmpty =>
      lines.isEmpty && supplierId == null && invoicePath == null && paidNow == 0;

  PurchaseDraft copyWith({
    String? supplierId,
    String? supplierName,
    List<PurchaseLineState>? lines,
    int? paidNow,
    String? invoicePath,
    bool clearInvoice = false,
  }) =>
      PurchaseDraft(
        supplierId: supplierId ?? this.supplierId,
        supplierName: supplierName ?? this.supplierName,
        lines: lines ?? this.lines,
        paidNow: paidNow ?? this.paidNow,
        invoicePath: clearInvoice ? null : (invoicePath ?? this.invoicePath),
      );

  PurchaseInput toInput() => PurchaseInput(
        supplierId: supplierId!,
        lines: [
          for (final l in lines)
            PurchaseLineInput(
                itemId: l.itemId, qty: l.qty, unitCost: l.unitCost),
        ],
        paidNow: effectivePaid,
        invoiceImagePath: invoicePath,
      );
}

class PurchaseController extends Notifier<PurchaseDraft> {
  @override
  PurchaseDraft build() => const PurchaseDraft();

  void setSupplier(String id, String name) =>
      state = state.copyWith(supplierId: id, supplierName: name);

  /// Adds the item with its last cost, or increases the quantity by one unit
  /// when it is already on the list.
  void addItem(Item item, {int qty = 1000}) {
    final i = state.lines.indexWhere((l) => l.itemId == item.id);
    if (i >= 0) {
      final lines = [...state.lines];
      lines[i] = lines[i].copyWith(qty: lines[i].qty + qty);
      state = state.copyWith(lines: lines);
      return;
    }
    state = state.copyWith(lines: [
      ...state.lines,
      PurchaseLineState(
        itemId: item.id,
        name: item.name,
        unit: item.unit,
        qty: qty,
        unitCost: item.costPrice,
        photoPath: item.photoPath,
      ),
    ]);
  }

  void setQty(String itemId, int qty) {
    if (qty <= 0) return remove(itemId);
    state = state.copyWith(lines: [
      for (final l in state.lines)
        if (l.itemId == itemId) l.copyWith(qty: qty) else l,
    ]);
  }

  void setCost(String itemId, int cost) {
    if (cost < 0) return;
    state = state.copyWith(lines: [
      for (final l in state.lines)
        if (l.itemId == itemId) l.copyWith(unitCost: cost) else l,
    ]);
  }

  void remove(String itemId) => state = state.copyWith(
      lines: [for (final l in state.lines) if (l.itemId != itemId) l]);

  void setPaidNow(int paid) => state = state.copyWith(paidNow: paid < 0 ? 0 : paid);

  void setInvoice(String? path) => state = path == null
      ? state.copyWith(clearInvoice: true)
      : state.copyWith(invoicePath: path);

  void clear() => state = const PurchaseDraft();
}

final purchaseControllerProvider =
    NotifierProvider<PurchaseController, PurchaseDraft>(PurchaseController.new);
