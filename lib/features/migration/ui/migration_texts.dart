import '../../../core/db/constants.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/column_mapping.dart';
import '../domain/migration_controller.dart';

String problemText(AppLocalizations l10n, MigrationProblem p) => switch (p) {
      MigrationProblem.fileUnsupported => l10n.migrationErrUnsupported,
      MigrationProblem.fileEmpty => l10n.migrationErrEmpty,
      MigrationProblem.fileBroken => l10n.migrationErrBroken,
      MigrationProblem.ocrOffline => l10n.migrationErrOcrOffline,
      MigrationProblem.ocrFailed => l10n.migrationErrOcrFailed,
      MigrationProblem.ocrNothing => l10n.migrationErrOcrNothing,
      MigrationProblem.saveFailed => l10n.migrationErrSave,
      MigrationProblem.barcodeTaken => l10n.migrationErrBarcode,
      MigrationProblem.nothingToSave => l10n.migrationErrNothing,
    };

String kindLabel(AppLocalizations l10n, String kind) => switch (kind) {
      ImportKind.suppliers => l10n.migrationKindSuppliers,
      ImportKind.items => l10n.migrationKindItems,
      _ => l10n.migrationKindCustomers,
    };

String fieldLabel(AppLocalizations l10n, ImportField f) => switch (f) {
      ImportField.name => l10n.migrationName,
      ImportField.phone => l10n.migrationFieldPhone,
      ImportField.balance => l10n.migrationAmount,
      ImportField.unit => l10n.migrationFieldUnit,
      ImportField.cost => l10n.migrationFieldCost,
      ImportField.price => l10n.migrationFieldPrice,
      ImportField.stock => l10n.migrationFieldStock,
      ImportField.low => l10n.migrationFieldLow,
      ImportField.barcode => l10n.migrationFieldBarcode,
    };

String stepTitle(AppLocalizations l10n, MigrationState s) => switch (s.phase) {
      MigrationPhase.method => l10n.migrationStepMethod,
      MigrationPhase.quick => l10n.migrationStepQuick,
      MigrationPhase.mapping => l10n.migrationStepMapping,
      MigrationPhase.confirm => l10n.migrationStepConfirm,
      MigrationPhase.done => l10n.migrationStepDone,
    };
