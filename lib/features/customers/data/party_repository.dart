import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/constants.dart';
import '../../../core/db/daos/khata_dao.dart';
import '../../../core/db/db_providers.dart';
import '../../../core/sync/outbox_writer.dart';
import '../../../core/utils/phone.dart';
import '../../auth/data/shop_repository.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/current_shop.dart';

enum PartyKind { customer, supplier }

class PartyValidationException implements Exception {
  const PartyValidationException();
}

/// The system "Naqad customer" cannot be edited or hidden.
class SystemCustomerException implements Exception {
  const SystemCustomerException();
}

/// Plain details of a customer or supplier for the edit form.
class PartyInfo {
  const PartyInfo(this.id, this.name, this.phone, this.isArchived);
  final String id;
  final String name;
  final String? phone;
  final bool isArchived;
}

/// Customers and suppliers behave the same in Part 2 (add, edit, hide,
/// opening balance), so the UI talks to this one interface.
abstract class PartyRepository {
  Stream<List<PartyRow>> watch({String query = '', bool includeArchived = false});
  Future<PartyInfo?> info(String id);

  /// [openingBalance] in paisa (>= 0): what the customer owes us / what we
  /// owe the supplier before using Galla. Written as an `opening` ledger row.
  Future<String> create({
    required String name,
    String? phone,
    int openingBalance = 0,
  });
  Future<void> update(String id, {required String name, String? phone});
  Future<void> setArchived(String id, bool archived);
}

String? _cleanPhone(String? input) {
  final t = input?.trim() ?? '';
  if (t.isEmpty) return null;
  return normalizePkPhone(t) ?? t;
}

class CustomerRepository implements PartyRepository {
  CustomerRepository(this._db, this._shopId, this._now);

  final AppDatabase _db;
  final String Function() _shopId;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  @override
  Stream<List<PartyRow>> watch(
      {String query = '', bool includeArchived = false}) {
    final shopId = _shopId();
    return _db.khataDao.watchCustomers(
      shopId,
      query: query,
      includeArchived: includeArchived,
      excludeId: naqadCustomerId(shopId),
    );
  }

  @override
  Future<PartyInfo?> info(String id) async {
    final c = await _db.khataDao.customerById(id);
    return c == null ? null : PartyInfo(c.id, c.name, c.phone, c.isArchived);
  }

  @override
  Future<String> create({
    required String name,
    String? phone,
    int openingBalance = 0,
  }) async {
    if (name.trim().isEmpty || openingBalance < 0) {
      throw const PartyValidationException();
    }
    final shopId = _shopId();
    final now = _now();
    final id = _uuid.v4();
    await writeWithOutbox(_db, (outbox) async {
      final c = await _db.into(_db.customers).insertReturning(
            CustomersCompanion.insert(
              id: id,
              shopId: shopId,
              name: name.trim(),
              phone: Value(_cleanPhone(phone)),
              createdAt: now,
              updatedAt: now,
            ),
          );
      outbox.record(
          table: 'customers',
          rowId: id,
          payload: c.toJson(),
          op: OutboxOp.insert);
      if (openingBalance > 0) {
        final l = await _db.into(_db.customerLedger).insertReturning(
              CustomerLedgerCompanion.insert(
                id: _uuid.v4(),
                shopId: shopId,
                customerId: id,
                type: CustomerLedgerType.opening,
                amount: openingBalance,
                date: now,
                createdAt: now,
                updatedAt: now,
              ),
            );
        outbox.record(
            table: 'customer_ledger',
            rowId: l.id,
            payload: l.toJson(),
            op: OutboxOp.insert);
      }
    }, now: () => now);
    return id;
  }

  void _guard(String id) {
    if (id == naqadCustomerId(_shopId())) throw const SystemCustomerException();
  }

  @override
  Future<void> update(String id, {required String name, String? phone}) async {
    _guard(id);
    if (name.trim().isEmpty) throw const PartyValidationException();
    final now = _now();
    await writeWithOutbox(_db, (outbox) async {
      await (_db.update(_db.customers)..where((t) => t.id.equals(id))).write(
        CustomersCompanion(
          name: Value(name.trim()),
          phone: Value(_cleanPhone(phone)),
          updatedAt: Value(now),
        ),
      );
      final c = await _db.khataDao.customerById(id);
      if (c != null) {
        outbox.record(table: 'customers', rowId: id, payload: c.toJson());
      }
    }, now: () => now);
  }

  @override
  Future<void> setArchived(String id, bool archived) async {
    _guard(id);
    final now = _now();
    await writeWithOutbox(_db, (outbox) async {
      await (_db.update(_db.customers)..where((t) => t.id.equals(id))).write(
        CustomersCompanion(isArchived: Value(archived), updatedAt: Value(now)),
      );
      final c = await _db.khataDao.customerById(id);
      if (c != null) {
        outbox.record(table: 'customers', rowId: id, payload: c.toJson());
      }
    }, now: () => now);
  }
}

class SupplierRepository implements PartyRepository {
  SupplierRepository(this._db, this._shopId, this._now);

  final AppDatabase _db;
  final String Function() _shopId;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  @override
  Stream<List<PartyRow>> watch(
          {String query = '', bool includeArchived = false}) =>
      _db.khataDao.watchSuppliers(_shopId(),
          query: query, includeArchived: includeArchived);

  @override
  Future<PartyInfo?> info(String id) async {
    final s = await _db.khataDao.supplierById(id);
    return s == null ? null : PartyInfo(s.id, s.name, s.phone, s.isArchived);
  }

  @override
  Future<String> create({
    required String name,
    String? phone,
    int openingBalance = 0,
  }) async {
    if (name.trim().isEmpty || openingBalance < 0) {
      throw const PartyValidationException();
    }
    final shopId = _shopId();
    final now = _now();
    final id = _uuid.v4();
    await writeWithOutbox(_db, (outbox) async {
      final s = await _db.into(_db.suppliers).insertReturning(
            SuppliersCompanion.insert(
              id: id,
              shopId: shopId,
              name: name.trim(),
              phone: Value(_cleanPhone(phone)),
              createdAt: now,
              updatedAt: now,
            ),
          );
      outbox.record(
          table: 'suppliers',
          rowId: id,
          payload: s.toJson(),
          op: OutboxOp.insert);
      if (openingBalance > 0) {
        final l = await _db.into(_db.supplierLedger).insertReturning(
              SupplierLedgerCompanion.insert(
                id: _uuid.v4(),
                shopId: shopId,
                supplierId: id,
                type: SupplierLedgerType.opening,
                amount: openingBalance,
                date: now,
                createdAt: now,
                updatedAt: now,
              ),
            );
        outbox.record(
            table: 'supplier_ledger',
            rowId: l.id,
            payload: l.toJson(),
            op: OutboxOp.insert);
      }
    }, now: () => now);
    return id;
  }

  @override
  Future<void> update(String id, {required String name, String? phone}) async {
    if (name.trim().isEmpty) throw const PartyValidationException();
    final now = _now();
    await writeWithOutbox(_db, (outbox) async {
      await (_db.update(_db.suppliers)..where((t) => t.id.equals(id))).write(
        SuppliersCompanion(
          name: Value(name.trim()),
          phone: Value(_cleanPhone(phone)),
          updatedAt: Value(now),
        ),
      );
      final s = await _db.khataDao.supplierById(id);
      if (s != null) {
        outbox.record(table: 'suppliers', rowId: id, payload: s.toJson());
      }
    }, now: () => now);
  }

  @override
  Future<void> setArchived(String id, bool archived) async {
    final now = _now();
    await writeWithOutbox(_db, (outbox) async {
      await (_db.update(_db.suppliers)..where((t) => t.id.equals(id))).write(
        SuppliersCompanion(isArchived: Value(archived), updatedAt: Value(now)),
      );
      final s = await _db.khataDao.supplierById(id);
      if (s != null) {
        outbox.record(table: 'suppliers', rowId: id, payload: s.toJson());
      }
    }, now: () => now);
  }
}

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(
    ref.watch(appDatabaseProvider),
    () => ref.read(shopIdProvider),
    ref.watch(clockProvider),
  );
});

final supplierRepositoryProvider = Provider<SupplierRepository>((ref) {
  return SupplierRepository(
    ref.watch(appDatabaseProvider),
    () => ref.read(shopIdProvider),
    ref.watch(clockProvider),
  );
});

PartyRepository partyRepositoryFor(Ref ref, PartyKind kind) =>
    kind == PartyKind.customer
        ? ref.read(customerRepositoryProvider)
        : ref.read(supplierRepositoryProvider);

typedef PartyQuery = ({PartyKind kind, String query, bool showHidden});

final partyListProvider = StreamProvider.autoDispose
    .family<List<PartyRow>, PartyQuery>((ref, q) {
  ref.watch(shopIdProvider); // restart when the shop changes
  return partyRepositoryFor(ref, q.kind)
      .watch(query: q.query, includeArchived: q.showHidden);
});

final customerCountProvider = StreamProvider.autoDispose<int>((ref) {
  ref.watch(shopIdProvider);
  return ref.read(customerRepositoryProvider).watch().map((l) => l.length);
});

final supplierCountProvider = StreamProvider.autoDispose<int>((ref) {
  ref.watch(shopIdProvider);
  return ref.read(supplierRepositoryProvider).watch().map((l) => l.length);
});
