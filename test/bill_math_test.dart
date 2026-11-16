import 'package:flutter_test/flutter_test.dart';
import 'package:galla/core/db/constants.dart';
import 'package:galla/features/bill/domain/bill_math.dart';

void main() {
  group('lineTotal', () {
    test('whole and fractional quantities', () {
      expect(lineTotal(1000, 18000), 18000);
      expect(lineTotal(2500, 18000), 45000); // 2.5 kg x Rs 180
      expect(lineTotal(500, 18000), 9000);
    });
    test('rounds half up to whole paisa', () {
      expect(lineTotal(1, 500), 1); // 0.5 paisa -> 1
      expect(lineTotal(1, 499), 0);
      expect(lineTotal(333, 1000), 333);
      expect(lineTotal(333, 1501), 500); // 499.833 -> 500
    });
  });

  group('discount', () {
    test('clamped between 0 and subtotal', () {
      expect(clampDiscount(-5, 1000), 0);
      expect(clampDiscount(500, 1000), 500);
      expect(clampDiscount(5000, 1000), 1000);
    });
    test('round off to Rs 10 / 50 / 100', () {
      expect(roundOffDiscount(184300, 1000), 300);
      expect(roundOffDiscount(184300, 5000), 4300);
      expect(roundOffDiscount(184300, 10000), 4300);
      expect(roundOffDiscount(184000, 1000), 0);
    });
    test('never makes a small bill free', () {
      expect(roundOffDiscount(700, 1000), 0);
      expect(roundOffDiscount(0, 1000), 0);
    });
    test('computeTotals clamps and sums', () {
      final t = computeTotals([
        (qty: 2500, unitPrice: 18000),
        (qty: 1000, unitPrice: 5000),
      ], 999999);
      expect(t.subtotal, 50000);
      expect(t.discount, 50000);
      expect(t.total, 0);
      final u = computeTotals([(qty: 1000, unitPrice: 10000)], 1500);
      expect(u.total, 8500);
    });
  });

  group('resolvePayment', () {
    test('cash is paid in full', () {
      final p = resolvePayment(total: 10000, credit: false, paidNow: 5);
      expect((p.paid, p.unpaid, p.mode), (10000, 0, PaymentMode.cash));
    });
    test('udhaar with nothing paid', () {
      final p = resolvePayment(total: 10000, credit: true);
      expect((p.paid, p.unpaid, p.mode), (0, 10000, PaymentMode.udhaar));
    });
    test('partial payment', () {
      final p = resolvePayment(total: 10000, credit: true, paidNow: 4000);
      expect((p.paid, p.unpaid, p.mode), (4000, 6000, PaymentMode.partial));
    });
    test('paying everything or more under udhaar is a cash bill', () {
      for (final paid in [10000, 20000]) {
        final p = resolvePayment(total: 10000, credit: true, paidNow: paid);
        expect((p.paid, p.unpaid, p.mode), (10000, 0, PaymentMode.cash));
      }
    });
    test('negative paid treated as zero', () {
      final p = resolvePayment(total: 10000, credit: true, paidNow: -1);
      expect(p.mode, PaymentMode.udhaar);
    });
  });

  group('returns', () {
    test('no discount: price x qty', () {
      expect(
          returnAmount(
              returnQty: 1000,
              unitPrice: 18000,
              billSubtotal: 36000,
              billDiscount: 0),
          18000);
    });
    test('discount shared proportionally', () {
      // Rs 360 bill, Rs 36 discount (10%): returning Rs 180 of goods = Rs 162.
      expect(
          returnAmount(
              returnQty: 1000,
              unitPrice: 18000,
              billSubtotal: 36000,
              billDiscount: 3600),
          16200);
    });
    test('returning every line gives back exactly the total', () {
      final lines = [
        (qty: 1000, unitPrice: 3333),
        (qty: 1000, unitPrice: 3333),
        (qty: 1000, unitPrice: 3334),
      ];
      final plan = planReturn(
        lines: lines,
        billSubtotal: 10000,
        billDiscount: 1000,
        billTotal: 9000,
        billPaid: 9000,
      );
      expect(plan.total, 9000);
    });
    test('splitReturn: cash bill refunds all in cash', () {
      final s = splitReturn(
          returnAmount: 5000,
          billTotal: 10000,
          billPaid: 10000,
          priorLedgerCredits: 0);
      expect((s.ledgerCredit, s.cashRefund), (0, 5000));
    });
    test('splitReturn: udhaar bill reduces khata first', () {
      final s = splitReturn(
          returnAmount: 5000,
          billTotal: 10000,
          billPaid: 0,
          priorLedgerCredits: 0);
      expect((s.ledgerCredit, s.cashRefund), (5000, 0));
    });
    test('splitReturn: partial bill, return bigger than still owed', () {
      final s = splitReturn(
          returnAmount: 8000,
          billTotal: 10000,
          billPaid: 4000,
          priorLedgerCredits: 0);
      expect((s.ledgerCredit, s.cashRefund), (6000, 2000));
    });
    test('splitReturn: earlier credits use up the owed amount', () {
      final s = splitReturn(
          returnAmount: 3000,
          billTotal: 10000,
          billPaid: 0,
          priorLedgerCredits: 9000);
      expect((s.ledgerCredit, s.cashRefund), (1000, 2000));
    });
    test('planReturn caps total to what is left on the bill', () {
      final plan = planReturn(
        lines: [(qty: 1000, unitPrice: 10000)],
        billSubtotal: 10000,
        billDiscount: 0,
        billTotal: 10000,
        billPaid: 10000,
        priorValue: 7000,
      );
      expect(plan.total, 3000);
      expect(plan.lineAmounts.single, 3000);
    });
  });
}
