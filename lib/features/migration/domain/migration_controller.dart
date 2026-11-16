import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/constants.dart';
import '../../../core/services/photo_service.dart';
import '../data/import_repository.dart';
import '../data/ocr_service.dart';
import '../data/table_reader.dart';
import 'column_mapping.dart';
import 'import_rows.dart';
import 'ocr_response.dart';

enum MigrationPhase { method, quick, mapping, confirm, done }

/// Why a step could not go on (the screen turns this into words).
enum MigrationProblem {
  fileUnsupported,
  fileEmpty,
  fileBroken,
  ocrOffline,
  ocrFailed,
  ocrNothing,
  saveFailed,
  barcodeTaken,
  nothingToSave,
}

class MigrationState {
  const MigrationState({
    this.phase = MigrationPhase.method,
    this.kind = ImportKind.customers,
    this.method = ImportMethod.quick,
    this.table = const [],
    this.fileName = '',
    this.hasHeader = true,
    this.mapping = const {},
    this.partyRows = const [],
    this.itemRows = const [],
    this.existingParties = const {},
    this.existingItemNames = const {},
    this.existingBarcodes = const {},
    this.nextRowId = 0,
    this.busy = false,
    this.problem,
    this.result,
    this.photoPath,
    this.undone = false,
  });

  final MigrationPhase phase;
  final String kind;
  final String method;

  // File import
  final List<List<String>> table;
  final String fileName;
  final bool hasHeader;
  final ColumnMapping mapping;

  // Confirm
  final List<PartyImportRow> partyRows;
  final List<ItemImportRow> itemRows;
  final Set<String> existingParties;
  final Set<String> existingItemNames;
  final Set<String> existingBarcodes;
  final int nextRowId;

  final bool busy;
  final MigrationProblem? problem;
  final ImportResult? result;
  final String? photoPath;
  final bool undone;

  bool get isItems => kind == ImportKind.items;

  /// 1, 2 or 3 of the progress bar.
  int get step => switch (phase) {
        MigrationPhase.method ||
        MigrationPhase.quick ||
        MigrationPhase.mapping =>
          1,
        MigrationPhase.confirm => 2,
        MigrationPhase.done => 3,
      };

  List<PartyAssessment> get partyAssessments =>
      assessAllParties(partyRows, existingKeys: existingParties);

  List<ItemAssessment> get itemAssessments => assessAllItems(itemRows,
      existingNames: existingItemNames, existingBarcodes: existingBarcodes);

  MigrationState copyWith({
    MigrationPhase? phase,
    String? kind,
    String? method,
    List<List<String>>? table,
    String? fileName,
    bool? hasHeader,
    ColumnMapping? mapping,
    List<PartyImportRow>? partyRows,
    List<ItemImportRow>? itemRows,
    Set<String>? existingParties,
    Set<String>? existingItemNames,
    Set<String>? existingBarcodes,
    int? nextRowId,
    bool? busy,
    MigrationProblem? problem,
    bool clearProblem = false,
    ImportResult? result,
    String? photoPath,
    bool? undone,
  }) =>
      MigrationState(
        phase: phase ?? this.phase,
        kind: kind ?? this.kind,
        method: method ?? this.method,
        table: table ?? this.table,
        fileName: fileName ?? this.fileName,
        hasHeader: hasHeader ?? this.hasHeader,
        mapping: mapping ?? this.mapping,
        partyRows: partyRows ?? this.partyRows,
        itemRows: itemRows ?? this.itemRows,
        existingParties: existingParties ?? this.existingParties,
        existingItemNames: existingItemNames ?? this.existingItemNames,
        existingBarcodes: existingBarcodes ?? this.existingBarcodes,
        nextRowId: nextRowId ?? this.nextRowId,
        busy: busy ?? this.busy,
        problem: clearProblem ? null : (problem ?? this.problem),
        result: result ?? this.result,
        photoPath: photoPath ?? this.photoPath,
        undone: undone ?? this.undone,
      );
}

class MigrationController extends Notifier<MigrationState> {
  @override
  MigrationState build() => const MigrationState();

  ImportRepository get _repo => ref.read(importRepositoryProvider);

  void setKind(String kind) {
    state = state.copyWith(kind: kind, clearProblem: true);
  }

  void clearProblem() => state = state.copyWith(clearProblem: true);

  /// Goes one step back; false when already at the very start (the screen
  /// then leaves).
  bool back() {
    switch (state.phase) {
      case MigrationPhase.method:
      case MigrationPhase.done:
        return false;
      case MigrationPhase.quick:
      case MigrationPhase.mapping:
        state = state.copyWith(
            phase: MigrationPhase.method, table: const [], clearProblem: true);
        return true;
      case MigrationPhase.confirm:
        state = state.copyWith(
          phase: state.method == ImportMethod.file
              ? MigrationPhase.mapping
              : state.method == ImportMethod.quick
                  ? MigrationPhase.quick
                  : MigrationPhase.method,
          clearProblem: true,
        );
        return true;
    }
  }

  void reset() => state = const MigrationState();

  // ------------------------------------------------------------- quick

  void startQuick() {
    state = state.copyWith(
        method: ImportMethod.quick,
        phase: MigrationPhase.quick,
        clearProblem: true);
  }

  /// Quick entry finished: (name, amount) pairs typed by hand.
  Future<void> finishQuick(List<({String name, String amount})> entries) async {
    final rows = <PartyImportRow>[];
    var id = 0;
    for (final e in entries) {
      final r = PartyImportRow(id: id, name: e.name, amount: e.amount);
      if (r.isBlank) continue;
      rows.add(r);
      id++;
    }
    if (rows.isEmpty) {
      state = state.copyWith(problem: MigrationProblem.nothingToSave);
      return;
    }
    await _toConfirm(rows: rows, itemRows: const [], nextId: id);
  }

  // -------------------------------------------------------------- file

  /// A file was picked. Reads it; on success goes to column matching.
  void loadFile(Uint8List bytes, String fileName) {
    try {
      final table = readTable(bytes, fileName);
      final header = looksLikeHeader(table, state.kind);
      state = state.copyWith(
        method: ImportMethod.file,
        phase: MigrationPhase.mapping,
        table: table,
        fileName: fileName,
        hasHeader: header,
        mapping: guessMapping(table, state.kind, hasHeader: header),
        clearProblem: true,
      );
    } on TableReadException catch (e) {
      state = state.copyWith(
        problem: switch (e.reason) {
          'unsupported' => MigrationProblem.fileUnsupported,
          'empty' => MigrationProblem.fileEmpty,
          _ => MigrationProblem.fileBroken,
        },
      );
    }
  }

  void setHasHeader(bool v) {
    state = state.copyWith(
      hasHeader: v,
      mapping: guessMapping(state.table, state.kind, hasHeader: v),
    );
  }

  /// Points [field] at column [col] (null = not in the file). A column feeds
  /// only one field, so it is taken from whichever field had it.
  void setMapping(ImportField field, int? col) {
    final m = {...state.mapping};
    if (col == null) {
      m.remove(field);
    } else {
      m.removeWhere((f, c) => c == col && f != field);
      m[field] = col;
    }
    state = state.copyWith(mapping: m);
  }

  Future<void> applyMapping() async {
    if (!state.mapping.containsKey(ImportField.name)) return;
    if (state.isItems) {
      final rows = itemRowsFromTable(state.table, state.mapping,
          hasHeader: state.hasHeader);
      if (rows.isEmpty) {
        state = state.copyWith(problem: MigrationProblem.fileEmpty);
        return;
      }
      await _toConfirm(
          rows: const [], itemRows: rows, nextId: rows.length);
    } else {
      final rows = partyRowsFromTable(state.table, state.mapping,
          hasHeader: state.hasHeader);
      if (rows.isEmpty) {
        state = state.copyWith(problem: MigrationProblem.fileEmpty);
        return;
      }
      await _toConfirm(rows: rows, itemRows: const [], nextId: rows.length);
    }
  }

  // --------------------------------------------------------------- ocr

  /// Photo of the paper copy. Only reachable when FeatureFlags.ocrImport.
  Future<void> startOcr() async {
    if (state.busy) return;
    final path = await ref.read(photoServiceProvider).takePhoto();
    if (path == null) return;
    state = state.copyWith(busy: true, clearProblem: true);
    try {
      final entries = await ref.read(ocrServiceProvider).read(path);
      final rows = rowsFromOcr(entries);
      state = state.copyWith(method: ImportMethod.ocr, photoPath: path);
      await _toConfirm(rows: rows, itemRows: const [], nextId: rows.length);
    } on OcrException catch (e) {
      state = state.copyWith(
        busy: false,
        problem: switch (e.reason) {
          'offline' => MigrationProblem.ocrOffline,
          'nothing' => MigrationProblem.ocrNothing,
          _ => MigrationProblem.ocrFailed,
        },
      );
    }
  }

  // ----------------------------------------------------------- confirm

  Future<void> _toConfirm({
    required List<PartyImportRow> rows,
    required List<ItemImportRow> itemRows,
    required int nextId,
  }) async {
    var parties = rows;
    var items = itemRows;
    var existingParties = <String>{};
    var names = <String>{};
    var barcodes = <String>{};
    if (state.isItems) {
      final k = await _repo.existingItemKeys();
      names = k.names;
      barcodes = k.barcodes;
      // Duplicates start switched off; the owner can turn them back on.
      final a = assessAllItems(items,
          existingNames: names, existingBarcodes: barcodes);
      items = [
        for (var i = 0; i < items.length; i++)
          items[i].copyWith(
              include: !(a[i].isDuplicate && !a[i].hasError)),
      ];
    } else {
      existingParties = await _repo.existingPartyKeys(state.kind);
      final a = assessAllParties(parties, existingKeys: existingParties);
      parties = [
        for (var i = 0; i < parties.length; i++)
          parties[i].copyWith(include: !a[i].isDuplicate),
      ];
    }
    state = state.copyWith(
      phase: MigrationPhase.confirm,
      partyRows: parties,
      itemRows: items,
      existingParties: existingParties,
      existingItemNames: names,
      existingBarcodes: barcodes,
      nextRowId: nextId,
      busy: false,
      clearProblem: true,
    );
  }

  void updateParty(int id, {String? name, String? phone, String? amount}) {
    state = state.copyWith(partyRows: [
      for (final r in state.partyRows)
        if (r.id == id)
          r.copyWith(
            name: name,
            phone: phone,
            amount: amount,
            // Editing means the owner has looked at it.
            sourceUncertain: false,
          )
        else
          r,
    ]);
  }

  void setPartyIncluded(int id, bool include) {
    state = state.copyWith(partyRows: [
      for (final r in state.partyRows)
        if (r.id == id) r.copyWith(include: include) else r,
    ]);
  }

  void removeParty(int id) {
    state = state.copyWith(
        partyRows: [for (final r in state.partyRows) if (r.id != id) r]);
  }

  void addPartyRow() {
    state = state.copyWith(
      partyRows: [...state.partyRows, PartyImportRow(id: state.nextRowId)],
      nextRowId: state.nextRowId + 1,
    );
  }

  void updateItem(
    int id, {
    String? name,
    String? unit,
    String? cost,
    String? price,
    String? stock,
    String? low,
    String? barcode,
  }) {
    state = state.copyWith(itemRows: [
      for (final r in state.itemRows)
        if (r.id == id)
          r.copyWith(
              name: name,
              unit: unit,
              cost: cost,
              price: price,
              stock: stock,
              low: low,
              barcode: barcode)
        else
          r,
    ]);
  }

  void setItemIncluded(int id, bool include) {
    state = state.copyWith(itemRows: [
      for (final r in state.itemRows)
        if (r.id == id) r.copyWith(include: include) else r,
    ]);
  }

  void removeItem(int id) {
    state = state.copyWith(
        itemRows: [for (final r in state.itemRows) if (r.id != id) r]);
  }

  // Counts for the confirm screen -----------------------------------

  /// Rows that will be saved.
  int get willImport {
    if (state.isItems) {
      final a = state.itemAssessments;
      var n = 0;
      for (var i = 0; i < a.length; i++) {
        if (state.itemRows[i].include && !a[i].hasError) n++;
      }
      return n;
    }
    final a = state.partyAssessments;
    var n = 0;
    for (var i = 0; i < a.length; i++) {
      if (state.partyRows[i].include && !a[i].hasError) n++;
    }
    return n;
  }

  /// Included rows that cannot be saved yet (they block the button).
  int get blockingErrors {
    if (state.isItems) {
      final a = state.itemAssessments;
      return [
        for (var i = 0; i < a.length; i++)
          if (state.itemRows[i].include && a[i].hasError) 1
      ].length;
    }
    final a = state.partyAssessments;
    return [
      for (var i = 0; i < a.length; i++)
        if (state.partyRows[i].include && a[i].hasError) 1
    ].length;
  }

  /// Included rows still marked "Pakka nahi, check karo".
  int get uncertainLeft {
    if (state.isItems) {
      final a = state.itemAssessments;
      return [
        for (var i = 0; i < a.length; i++)
          if (state.itemRows[i].include && a[i].isUncertain) 1
      ].length;
    }
    final a = state.partyAssessments;
    return [
      for (var i = 0; i < a.length; i++)
        if (state.partyRows[i].include && a[i].isUncertain) 1
    ].length;
  }

  /// Sum of the opening balances that will be saved (paisa).
  int get willImportTotal {
    if (state.isItems) return 0;
    final a = state.partyAssessments;
    var t = 0;
    for (var i = 0; i < a.length; i++) {
      if (state.partyRows[i].include && !a[i].hasError) t += a[i].paisa;
    }
    return t;
  }

  // ------------------------------------------------------------ commit

  Future<void> commit() async {
    if (state.busy) return;
    if (blockingErrors > 0) return;
    state = state.copyWith(busy: true, clearProblem: true);
    try {
      final ImportResult res;
      if (state.isItems) {
        final a = state.itemAssessments;
        final inputs = <ImportItemInput>[
          for (var i = 0; i < a.length; i++)
            if (state.itemRows[i].include && !a[i].hasError)
              ImportItemInput(
                name: state.itemRows[i].name.trim(),
                unit: a[i].unit,
                cost: a[i].cost,
                price: a[i].price,
                stock: a[i].stock,
                low: a[i].low,
                barcode: a[i].barcode,
              ),
        ];
        res = await _repo.commitItems(rows: inputs, method: state.method);
      } else {
        final a = state.partyAssessments;
        final inputs = <ImportPartyInput>[
          for (var i = 0; i < a.length; i++)
            if (state.partyRows[i].include && !a[i].hasError)
              ImportPartyInput(
                name: state.partyRows[i].name.trim(),
                phone: a[i].phone,
                paisa: a[i].paisa,
              ),
        ];
        res = await _repo.commitParties(
          kind: state.kind,
          rows: inputs,
          method: state.method,
          photoPath: state.photoPath,
        );
      }
      state = state.copyWith(
          busy: false, phase: MigrationPhase.done, result: res, undone: false);
    } on ImportException catch (e) {
      state = state.copyWith(
        busy: false,
        problem: switch (e.error) {
          ImportError.empty => MigrationProblem.nothingToSave,
          ImportError.barcodeTaken => MigrationProblem.barcodeTaken,
          _ => MigrationProblem.saveFailed,
        },
      );
    } catch (_) {
      state = state.copyWith(busy: false, problem: MigrationProblem.saveFailed);
    }
  }

  /// Undo the batch just saved. Returns null on success, or the exception.
  Future<ImportException?> undoCurrent() async {
    final id = state.result?.batchId;
    if (id == null) return null;
    try {
      await _repo.undoBatch(id);
      state = state.copyWith(undone: true);
      return null;
    } on ImportException catch (e) {
      return e;
    }
  }
}

final migrationControllerProvider =
    NotifierProvider<MigrationController, MigrationState>(
        MigrationController.new);
