import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/money.dart';

/// Words used on a statement, resolved from the ARB files by the UI.
class StatementLabels {
  const StatementLabels({
    required this.title,
    required this.balanceLabel,
    required this.advanceLabel,
    required this.date,
    required this.detail,
    required this.amount,
    required this.balance,
    required this.moreRows,
    required this.thanks,
  });

  /// "Khata statement" / "Supplier statement".
  final String title;

  /// Baqaya (customer) or Dena (supplier).
  final String balanceLabel;
  final String advanceLabel;
  final String date;
  final String detail;
  final String amount;
  final String balance;

  /// "Purane {n} entries chhupi hain" is passed already formatted.
  final String Function(int n) moreRows;
  final String thanks;
}

class StatementRow {
  const StatementRow({
    required this.date,
    required this.title,
    this.detail,
    required this.amount,
    required this.balance,
  });
  final DateTime date;

  /// "Bill #214", "Paisay mile"...
  final String title;
  final String? detail;

  /// Signed ledger amount (+ increases the baqaya).
  final int amount;

  /// Balance right after this row.
  final int balance;
}

class StatementData {
  const StatementData({
    required this.shopName,
    required this.partyName,
    this.partyPhone,
    required this.generatedAt,
    required this.rows,
    required this.balance,
  });

  final String shopName;
  final String partyName;
  final String? partyPhone;
  final DateTime generatedAt;

  /// Oldest first.
  final List<StatementRow> rows;
  final int balance;
}

final _dateFmt = DateFormat('d MMM y');

String _signed(int amount) =>
    '${amount < 0 ? '-' : '+'} ${formatPaisa(amount.abs())}';

String _balanceText(int balance, StatementLabels l) => balance < 0
    ? '${l.advanceLabel}: ${formatPaisa(balance.abs())}'
    : '${l.balanceLabel}: ${formatPaisa(balance)}';

/// WhatsApp text. Long histories keep the newest [maxRows] rows.
String buildStatementText(StatementData d, StatementLabels l,
    {int maxRows = 40}) {
  final b = StringBuffer()
    ..writeln('*${d.shopName}*')
    ..writeln('${l.title}: ${d.partyName}')
    ..writeln(_dateFmt.format(d.generatedAt))
    ..writeln('----------------');
  final skipped = d.rows.length > maxRows ? d.rows.length - maxRows : 0;
  if (skipped > 0) b.writeln(l.moreRows(skipped));
  for (final r in d.rows.skip(skipped)) {
    b.write('${_dateFmt.format(r.date)}  ${r.title}  ${_signed(r.amount)}');
    b.writeln('  (${formatPaisa(r.balance.abs())})');
    if (r.detail != null && r.detail!.isNotEmpty) b.writeln('   ${r.detail}');
  }
  b
    ..writeln('----------------')
    ..writeln('*${_balanceText(d.balance, l)}*')
    ..writeln(l.thanks);
  return b.toString().trimRight();
}

/// A4 statement, as many pages as needed.
Future<Uint8List> buildStatementPdf(StatementData d, StatementLabels l) async {
  final doc = pw.Document();
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  pw.Widget cell(String t,
          {bool right = false, pw.TextStyle? style, double pad = 4}) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: pad, horizontal: 4),
        child: pw.Text(t,
            style: style ?? const pw.TextStyle(fontSize: 10),
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
      );

  final head = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10);
  final rows = d.rows.reversed.toList(); // newest first, like the app

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (c) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(d.shopName,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
          pw.SizedBox(height: 2),
          pw.Text('${l.title}: ${d.partyName}'
              '${d.partyPhone == null ? '' : '  (${d.partyPhone})'}'),
          pw.Text(_dateFmt.format(d.generatedAt),
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 8),
        ],
      ),
      build: (c) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(_balanceText(d.balance, l),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          columnWidths: {
            0: const pw.FixedColumnWidth(70),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FixedColumnWidth(80),
            3: const pw.FixedColumnWidth(80),
          },
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(width: 0.3),
            bottom: pw.BorderSide(width: 0.3),
          ),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                cell(l.date, style: head),
                cell(l.detail, style: head),
                cell(l.amount, right: true, style: head),
                cell(l.balance, right: true, style: head),
              ],
            ),
            for (final r in rows)
              pw.TableRow(children: [
                cell(_dateFmt.format(r.date)),
                cell(r.detail == null || r.detail!.isEmpty
                    ? r.title
                    : '${r.title}\n${r.detail}'),
                cell(_signed(r.amount), right: true),
                cell(formatPaisa(r.balance), right: true),
              ]),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(l.thanks, style: bold),
      ],
    ),
  );
  return doc.save();
}

class StatementActions {
  Future<void> share(StatementData d, StatementLabels l) async {
    final bytes = await buildStatementPdf(d, l);
    final dir = await getTemporaryDirectory();
    final safe = d.partyName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final path = p.join(dir.path, 'statement_$safe.pdf');
    await File(path).writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/pdf')],
      text: buildStatementText(d, l),
    );
  }

  /// Text only, e.g. straight into a WhatsApp chat.
  Future<void> shareText(StatementData d, StatementLabels l) =>
      Share.share(buildStatementText(d, l));
}

final statementActionsProvider =
    Provider<StatementActions>((ref) => StatementActions());
