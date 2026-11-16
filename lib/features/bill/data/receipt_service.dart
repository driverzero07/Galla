import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/constants.dart';
import '../../../core/db/daos/sales_dao.dart';
import '../../../core/utils/money.dart';

/// Words printed on a receipt, taken from the ARB files by the UI.
class ReceiptLabels {
  const ReceiptLabels({
    required this.bill,
    required this.customer,
    required this.discount,
    required this.total,
    required this.paid,
    required this.balance,
    required this.cash,
    required this.udhaar,
    required this.partial,
    required this.cancelled,
    required this.thanks,
    required this.subtotal,
  });

  final String bill;
  final String customer;
  final String discount;
  final String total;
  final String paid;
  final String balance;
  final String cash;
  final String udhaar;
  final String partial;
  final String cancelled;
  final String thanks;
  final String subtotal;
}

class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.qty,
    required this.unit,
    required this.unitPrice,
    required this.total,
  });
  final String name;
  final int qty; // thousandths
  final String unit; // display word
  final int unitPrice;
  final int total;
}

class ReceiptData {
  const ReceiptData({
    required this.shopName,
    this.shopPhone,
    required this.billNo,
    required this.date,
    required this.customerName,
    required this.showCustomer,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paid,
    required this.mode,
    required this.cancelled,
  });

  final String shopName;
  final String? shopPhone;
  final String billNo;
  final DateTime date;
  final String customerName;

  /// False for the Naqad customer (no name printed).
  final bool showCustomer;
  final List<ReceiptLine> lines;
  final int subtotal;
  final int discount;
  final int total;
  final int paid;
  final String mode;
  final bool cancelled;

  int get unpaid => total - paid;

  String modeLabel(ReceiptLabels l) => switch (mode) {
        PaymentMode.udhaar => l.udhaar,
        PaymentMode.partial => l.partial,
        _ => l.cash,
      };

  factory ReceiptData.fromSale(
    SaleDetailData detail,
    Shop shop, {
    required String Function(String unit) unitLabel,
    required bool isNaqad,
  }) {
    final s = detail.sale;
    return ReceiptData(
      shopName: shop.name,
      shopPhone: shop.phone,
      billNo: s.billNo,
      date: s.createdAt,
      customerName: detail.customerName,
      showCustomer: !isNaqad,
      lines: [
        for (final l in detail.lines)
          ReceiptLine(
            name: l.nameSnapshot,
            qty: l.qty,
            unit: unitLabel(detail.unitOf(l.itemId)),
            unitPrice: l.unitPrice,
            total: l.lineTotal,
          ),
      ],
      subtotal: s.subtotal,
      discount: s.discount,
      total: s.total,
      paid: s.paidAmount,
      mode: s.paymentMode,
      cancelled: s.status == DocStatus.cancelled,
    );
  }
}

final _dateFormat = DateFormat('d MMM yyyy, h:mm a');

String _qtyText(ReceiptLine l) =>
    l.unit.isEmpty ? formatQty(l.qty) : '${formatQty(l.qty)} ${l.unit}';

/// WhatsApp-friendly plain text (bold with *stars*).
String buildWhatsAppText(ReceiptData d, ReceiptLabels l) {
  final b = StringBuffer()
    ..writeln('*${d.shopName}*')
    ..writeln('${l.bill} #${d.billNo} - ${_dateFormat.format(d.date)}');
  if (d.showCustomer && d.customerName.isNotEmpty) {
    b.writeln('${l.customer}: ${d.customerName}');
  }
  if (d.cancelled) b.writeln('*${l.cancelled}*');
  b.writeln('----------------');
  for (final line in d.lines) {
    b.writeln(
        '${line.name} x ${_qtyText(line)} = ${formatPaisa(line.total)}');
  }
  b.writeln('----------------');
  if (d.discount > 0) {
    b
      ..writeln('${l.subtotal}: ${formatPaisa(d.subtotal)}')
      ..writeln('${l.discount}: - ${formatPaisa(d.discount)}');
  }
  b.writeln('*${l.total}: ${formatPaisa(d.total)}*');
  b.writeln(d.modeLabel(l));
  if (d.unpaid > 0) {
    b
      ..writeln('${l.paid}: ${formatPaisa(d.paid)}')
      ..writeln('${l.balance}: ${formatPaisa(d.unpaid)}');
  }
  b.writeln(l.thanks);
  return b.toString().trimRight();
}

/// Narrow 80 mm style receipt as a PDF (A6-like roll, grows with content).
Future<Uint8List> buildReceiptPdf(ReceiptData d, ReceiptLabels l) async {
  final doc = pw.Document();
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  pw.Widget row(String left, String right, {pw.TextStyle? style}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(child: pw.Text(left, style: style)),
          pw.Text(right, style: style),
        ],
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80.copyWith(
        marginLeft: 12,
        marginRight: 12,
        marginTop: 12,
        marginBottom: 12,
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(d.shopName,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 16)),
          ),
          if (d.shopPhone != null && d.shopPhone!.isNotEmpty)
            pw.Center(child: pw.Text(d.shopPhone!)),
          pw.SizedBox(height: 6),
          row('${l.bill} #${d.billNo}', _dateFormat.format(d.date)),
          if (d.showCustomer && d.customerName.isNotEmpty)
            pw.Text('${l.customer}: ${d.customerName}'),
          if (d.cancelled)
            pw.Text(l.cancelled,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
          pw.Divider(),
          for (final line in d.lines) ...[
            pw.Text(line.name, style: bold),
            row('${_qtyText(line)} x ${formatPaisa(line.unitPrice)}',
                formatPaisa(line.total)),
            pw.SizedBox(height: 3),
          ],
          pw.Divider(),
          if (d.discount > 0) ...[
            row(l.subtotal, formatPaisa(d.subtotal)),
            row(l.discount, '- ${formatPaisa(d.discount)}'),
          ],
          row(l.total, formatPaisa(d.total),
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.Text(d.modeLabel(l)),
          if (d.unpaid > 0) ...[
            row(l.paid, formatPaisa(d.paid)),
            row(l.balance, formatPaisa(d.unpaid)),
          ],
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Text(l.thanks)),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Share (WhatsApp text + PDF) and print (system print dialog).
class ReceiptActions {
  Future<void> share(ReceiptData d, ReceiptLabels l) async {
    final bytes = await buildReceiptPdf(d, l);
    final dir = await getTemporaryDirectory();
    final safe = d.billNo.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_');
    final path = p.join(dir.path, 'bill_$safe.pdf');
    await File(path).writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/pdf')],
      text: buildWhatsAppText(d, l),
    );
  }

  Future<void> printReceipt(ReceiptData d, ReceiptLabels l) async {
    await Printing.layoutPdf(
      name: 'bill_${d.billNo}',
      onLayout: (_) => buildReceiptPdf(d, l),
    );
  }
}

final receiptActionsProvider = Provider<ReceiptActions>((ref) => ReceiptActions());
