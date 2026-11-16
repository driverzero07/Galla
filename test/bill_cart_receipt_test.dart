import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/features/bill/data/receipt_service.dart';
import 'package:galla/features/bill/domain/cart.dart';

CartLine cl(String id, int qty, int price) => CartLine(
    itemId: id,
    name: 'Item $id',
    unit: 'kg',
    qty: qty,
    unitPrice: price,
    listPrice: price);

void main() {
  group('BillState', () {
    test('totals, clamped discount, payment', () {
      final s = BillState(
        lines: [cl('a', 2500, 18000), cl('b', 1000, 5000)],
        discount: 999999,
      );
      expect(s.subtotal, 50000);
      expect(s.effectiveDiscount, 50000);
      expect(s.total, 0);
    });

    test('override flag', () {
      expect(cl('a', 1000, 100).copyWith(unitPrice: 90).isOverridden, isTrue);
      expect(cl('a', 1000, 100).isOverridden, isFalse);
    });

    test('draft JSON round-trips', () {
      final s = BillState(
        lines: [cl('a', 2500, 18000).copyWith(unitPrice: 17000)],
        discount: 500,
        customerId: 'c1',
        customerName: 'Ali',
        credit: true,
        paidNow: 1000,
      );
      final back = BillState.fromJsonString(s.toJsonString());
      expect(back.lines.single.unitPrice, 17000);
      expect(back.lines.single.listPrice, 18000);
      expect(back.discount, 500);
      expect(back.customerId, 'c1');
      expect(back.credit, isTrue);
      expect(back.paidNow, 1000);
    });

    test('corrupt draft yields an empty bill', () {
      final s = BillState.fromJsonString('{not json');
      expect(s.lines, isEmpty);
    });
  });

  group('receipt', () {
    const labels = ReceiptLabels(
      bill: 'Bill',
      customer: 'Customer',
      discount: 'Discount',
      total: 'Total',
      paid: 'Paid',
      balance: 'Baqi',
      cash: 'Cash',
      udhaar: 'Udhaar',
      partial: 'Partial',
      cancelled: 'Cancel',
      thanks: 'Shukriya',
      subtotal: 'Subtotal',
    );
    final data = ReceiptData(
      shopName: 'Test Store',
      shopPhone: '+923001234567',
      billNo: 'ABC-7',
      date: DateTime(2026, 11, 14, 10),
      customerName: 'Ali',
      showCustomer: true,
      lines: const [
        ReceiptLine(
            name: 'Cheeni',
            qty: 2500,
            unit: 'kg',
            unitPrice: 18000,
            total: 45000),
      ],
      subtotal: 45000,
      discount: 0,
      total: 45000,
      paid: 20000,
      mode: PaymentMode.partial,
      cancelled: false,
    );

    test('WhatsApp text has shop, bill, line and total', () {
      final t = buildWhatsAppText(data, labels);
      expect(t, contains('Test Store'));
      expect(t, contains('ABC-7'));
      expect(t, contains('Cheeni'));
      expect(t, contains('450'));
    });

    test('PDF starts with the %PDF header', () async {
      final bytes = await buildReceiptPdf(data, labels);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}
