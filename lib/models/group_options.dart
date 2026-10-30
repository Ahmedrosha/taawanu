import '../l10n/gen/app_localizations.dart';

/// المصحف = ٢٤٠ ربع حزب.
const totalQuarters = 240;

/// قيم الورد المسموحة بالأرباع. كلها بتقسم ٢٤٠ بالتساوي (نفس القايمة اللي في السيرفر).
const wardOptions = [1, 2, 4, 8, 12, 16, 24, 40];

String wardLabel(AppLocalizations t, int quarters) {
  switch (quarters) {
    case 1:
      return t.wardQuarter;
    case 2:
      return t.wardHalfHizb;
    case 4:
      return t.wardHizb;
    case 8:
      return t.wardJuz;
    case 12:
      return t.wardJuzAndHalf;
    case 16:
      return t.wardTwoJuz;
    case 24:
      return t.wardThreeJuz;
    case 40:
      return t.wardFiveJuz;
    default:
      return '$quarters';
  }
}

enum CycleUnit { day, week, month }

String cycleUnitLabel(AppLocalizations t, CycleUnit unit) => switch (unit) {
      CycleUnit.day => t.unitDay,
      CycleUnit.week => t.unitWeek,
      CycleUnit.month => t.unitMonth,
    };

enum LatePolicy { ask, carry, distribute, volunteer }

String latePolicyLabel(AppLocalizations t, LatePolicy p) => switch (p) {
      LatePolicy.ask => t.lateAsk,
      LatePolicy.carry => t.lateCarry,
      LatePolicy.distribute => t.lateDistribute,
      LatePolicy.volunteer => t.lateVolunteer,
    };

String roleLabel(AppLocalizations t, String role) => switch (role) {
      'admin' => t.roleAdmin,
      'assistant' => t.roleAssistant,
      _ => t.roleMember,
    };
