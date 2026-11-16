import 'dart:convert';

import 'bill_math.dart';

/// One row of the unsaved bill.
class CartLine {
  const CartLine({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.qty,
    required this.unitPrice,
    required this.listPrice,
    this.photoPath,
  });

  final String itemId;
  final String name;
  final String unit;
  final String? photoPath;

  /// Thousandths.
  final int qty;

  /// Price used on this bill (paisa). May be overridden for this bill only.
  final int unitPrice;

  /// The item's normal sale price when it was added.
  final int listPrice;

  bool get isOverridden => unitPrice != listPrice;
  int get total => lineTotal(qty, unitPrice);

  CartLine copyWith({int? qty, int? unitPrice}) => CartLine(
        itemId: itemId,
        name: name,
        unit: unit,
        photoPath: photoPath,
        qty: qty ?? this.qty,
        unitPrice: unitPrice ?? this.unitPrice,
        listPrice: listPrice,
      );

  Map<String, Object?> toJson() => {
        'itemId': itemId,
        'name': name,
        'unit': unit,
        'photoPath': photoPath,
        'qty': qty,
        'unitPrice': unitPrice,
        'listPrice': listPrice,
      };

  factory CartLine.fromJson(Map<String, Object?> j) => CartLine(
        itemId: j['itemId']! as String,
        name: j['name']! as String,
        unit: j['unit']! as String,
        photoPath: j['photoPath'] as String?,
        qty: j['qty']! as int,
        unitPrice: j['unitPrice']! as int,
        listPrice: j['listPrice']! as int,
      );
}

/// The whole unsaved bill. Immutable; saved as a local draft after every
/// change so a killed app or dead battery loses nothing.
class BillState {
  const BillState({
    this.lines = const [],
    this.discount = 0,
    this.customerId,
    this.customerName,
    this.credit = false,
    this.paidNow = 0,
    this.loaded = true,
  });

  /// Before the draft has been read from disk.
  const BillState.loading() : this(loaded: false);

  final List<CartLine> lines;

  /// Requested discount; use [effectiveDiscount].
  final int discount;

  /// null = Naqad customer.
  final String? customerId;
  final String? customerName;

  /// Udhaar selected (needs a real customer).
  final bool credit;

  /// "Abhi kitne diye": paid now when [credit].
  final int paidNow;
  final bool loaded;

  bool get isEmpty => lines.isEmpty;
  bool get hasRealCustomer => customerId != null;

  int get subtotal => lines.fold(0, (s, l) => s + l.total);
  int get effectiveDiscount => clampDiscount(discount, subtotal);
  int get total => subtotal - effectiveDiscount;

  PaymentResolution get payment =>
      resolvePayment(total: total, credit: credit, paidNow: paidNow);

  BillState copyWith({
    List<CartLine>? lines,
    int? discount,
    bool? credit,
    int? paidNow,
    String? customerId,
    String? customerName,
    bool clearCustomer = false,
  }) =>
      BillState(
        lines: lines ?? this.lines,
        discount: discount ?? this.discount,
        customerId: clearCustomer ? null : (customerId ?? this.customerId),
        customerName: clearCustomer ? null : (customerName ?? this.customerName),
        credit: credit ?? this.credit,
        paidNow: paidNow ?? this.paidNow,
      );

  String toJsonString() => jsonEncode({
        'v': 1,
        'lines': [for (final l in lines) l.toJson()],
        'discount': discount,
        'customerId': customerId,
        'customerName': customerName,
        'credit': credit,
        'paidNow': paidNow,
      });

  /// Returns an empty bill if [source] is damaged, never throws: a corrupt
  /// draft must not stop the shop from billing.
  static BillState fromJsonString(String source) {
    try {
      final j = jsonDecode(source) as Map<String, Object?>;
      return BillState(
        lines: [
          for (final l in (j['lines'] as List).cast<Map<String, Object?>>())
            CartLine.fromJson(l),
        ],
        discount: j['discount'] as int? ?? 0,
        customerId: j['customerId'] as String?,
        customerName: j['customerName'] as String?,
        credit: (j['credit'] as bool? ?? false) && j['customerId'] != null,
        paidNow: j['paidNow'] as int? ?? 0,
      );
    } catch (_) {
      return const BillState();
    }
  }
}
