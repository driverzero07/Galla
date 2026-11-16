import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'khata_dao.g.dart';

/// A customer or supplier with its derived balance (paisa).
class PartyRow {
  const PartyRow({
    required this.id,
    required this.name,
    required this.phone,
    required this.isArchived,
    required this.balance,
    this.lastActivity,
  });
  final String id;
  final String name;
  final String? phone;
  final bool isArchived;

  /// SUM of the ledger. Customers: + owes us. Suppliers: + we owe them.
  final int balance;

  /// Date of the newest ledger entry, null if there is none yet.
  final DateTime? lastActivity;
}

/// One ledger row, customer or supplier, in the shape history needs.
typedef RawLedger = ({
  String id,
  String type,
  int amount,
  DateTime date,
  DateTime createdAt,
  String? refId,
  String? note,
});

String _likePattern(String q) {
  final escaped = q
      .trim()
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}

@DriftAccessor(
    tables: [Customers, CustomerLedger, Suppliers, SupplierLedger])
class KhataDao extends DatabaseAccessor<AppDatabase> with _$KhataDaoMixin {
  KhataDao(super.db);

  /// Customer balance is always derived: SUM(customer_ledger.amount).
  /// Positive = customer owes us; negative = advance.
  Future<int> customerBalance(String customerId) async {
    final sum = customerLedger.amount.sum();
    final row = await (selectOnly(customerLedger)
          ..addColumns([sum])
          ..where(customerLedger.customerId.equals(customerId)))
        .getSingle();
    return row.read(sum) ?? 0;
  }

  /// Supplier balance: positive = we owe the supplier.
  Future<int> supplierBalance(String supplierId) async {
    final sum = supplierLedger.amount.sum();
    final row = await (selectOnly(supplierLedger)
          ..addColumns([sum])
          ..where(supplierLedger.supplierId.equals(supplierId)))
        .getSingle();
    return row.read(sum) ?? 0;
  }

  Future<Customer?> customerById(String id) =>
      (select(customers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Supplier?> supplierById(String id) =>
      (select(suppliers)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// [excludeId] hides the system Naqad customer from lists.
  Stream<List<PartyRow>> watchCustomers(
    String shopId, {
    String query = '',
    bool includeArchived = false,
    String? excludeId,
  }) =>
      _watchParties(
        table: 'customers',
        ledger: 'customer_ledger',
        fk: 'customer_id',
        reads: {customers, customerLedger},
        shopId: shopId,
        query: query,
        includeArchived: includeArchived,
        excludeId: excludeId,
      );

  Stream<List<PartyRow>> watchSuppliers(
    String shopId, {
    String query = '',
    bool includeArchived = false,
  }) =>
      _watchParties(
        table: 'suppliers',
        ledger: 'supplier_ledger',
        fk: 'supplier_id',
        reads: {suppliers, supplierLedger},
        shopId: shopId,
        query: query,
        includeArchived: includeArchived,
      );

  // Table names are fixed internal constants, never user input.
  Stream<List<PartyRow>> _watchParties({
    required String table,
    required String ledger,
    required String fk,
    required Set<TableInfo<Table, dynamic>> reads,
    required String shopId,
    required String query,
    required bool includeArchived,
    String? excludeId,
  }) {
    final vars = <Variable>[Variable.withString(shopId)];
    final sql = StringBuffer(
      'SELECT p.id, p.name, p.phone, p.is_archived, '
      'COALESCE((SELECT SUM(l.amount) FROM $ledger l WHERE l.$fk = p.id), 0) '
      'AS balance, '
      '(SELECT MAX(l.date) FROM $ledger l WHERE l.$fk = p.id) AS last_activity '
      'FROM $table p WHERE p.shop_id = ?1',
    );
    if (!includeArchived) sql.write(' AND p.is_archived = 0');
    if (excludeId != null) {
      vars.add(Variable.withString(excludeId));
      sql.write(' AND p.id <> ?${vars.length}');
    }
    if (query.trim().isNotEmpty) {
      vars.add(Variable.withString(_likePattern(query)));
      final n = vars.length;
      sql.write(" AND (p.name LIKE ?$n ESCAPE '\\' "
          "OR IFNULL(p.phone, '') LIKE ?$n ESCAPE '\\')");
    }
    sql.write(' ORDER BY p.name COLLATE NOCASE');
    return customSelect(sql.toString(), variables: vars, readsFrom: reads)
        .watch()
        .map((rows) => [
              for (final r in rows)
                PartyRow(
                  id: r.read<String>('id'),
                  name: r.read<String>('name'),
                  phone: r.readNullable<String>('phone'),
                  isArchived: r.read<bool>('is_archived'),
                  balance: r.read<int>('balance'),
                  lastActivity: r.readNullable<DateTime>('last_activity'),
                ),
            ]);
  }

  Stream<Customer?> watchCustomer(String id) =>
      (select(customers)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Stream<Supplier?> watchSupplier(String id) =>
      (select(suppliers)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Stream<List<RawLedger>> watchCustomerLedger(String customerId) =>
      (select(customerLedger)..where((t) => t.customerId.equals(customerId)))
          .watch()
          .map((rows) => [
                for (final r in rows)
                  (
                    id: r.id,
                    type: r.type,
                    amount: r.amount,
                    date: r.date,
                    createdAt: r.createdAt,
                    refId: r.refId,
                    note: r.note,
                  ),
              ]);

  Stream<List<RawLedger>> watchSupplierLedger(String supplierId) =>
      (select(supplierLedger)..where((t) => t.supplierId.equals(supplierId)))
          .watch()
          .map((rows) => [
                for (final r in rows)
                  (
                    id: r.id,
                    type: r.type,
                    amount: r.amount,
                    date: r.date,
                    createdAt: r.createdAt,
                    refId: r.refId,
                    note: r.note,
                  ),
              ]);

  /// Plain ledger rows of one customer.
  Future<List<RawLedger>> customerLedgerRows(String customerId) async {
    final rows = await (select(customerLedger)
          ..where((t) => t.customerId.equals(customerId))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();
    return [
      for (final r in rows)
        (
          id: r.id,
          type: r.type,
          amount: r.amount,
          date: r.date,
          createdAt: r.createdAt,
          refId: r.refId,
          note: r.note,
        ),
    ];
  }
}
