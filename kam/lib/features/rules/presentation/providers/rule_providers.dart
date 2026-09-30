import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/error/app_failure.dart';
import '../../../../core/firebase/firebase_error_mapper.dart';
import '../../../../core/firebase/firebase_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/result/result.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../pairing/presentation/providers/pairing_providers.dart';
import '../../data/repositories/firestore_rule_repository.dart';
import '../../data/repositories/in_memory_rule_repository.dart';
import '../../domain/models/rule.dart';
import '../../domain/repositories/rule_repository.dart';
import '../../domain/rule_draft.dart';
import '../../domain/rule_id_generator.dart';

/// The owner/pair scope a rule belongs to.
class RuleScope {
  const RuleScope({required this.ownerUserId, required this.pairId});

  /// The signed-in user who owns (and can read) the rules.
  final String ownerUserId;

  /// The active pair whose partner state the rules describe.
  final String pairId;

  @override
  bool operator ==(Object other) =>
      other is RuleScope &&
      other.ownerUserId == ownerUserId &&
      other.pairId == pairId;

  @override
  int get hashCode => Object.hash(ownerUserId, pairId);

  @override
  String toString() => 'RuleScope($pairId)';
}

/// The rule persistence boundary.
///
/// Selected once, so no widget ever constructs a repository or touches Firebase
/// directly (SRS FR-024 requirement: presentation must not reach Firestore).
final ruleRepositoryProvider = Provider<RuleRepository>((ref) {
  if (!ref.watch(firebaseAvailableProvider)) {
    // No account service: rules stay in memory for this session only, and the
    // UI says so rather than implying they were stored.
    return InMemoryRuleRepository();
  }
  return FirestoreRuleRepository(
    ref.watch(firebaseFirestoreProvider),
    ref.watch(loggerProvider),
  );
});

/// Opaque rule id generator.
final ruleIdGeneratorProvider = Provider<RuleIdGenerator>(
  (ref) => RuleIdGenerator(),
);

/// The active owner/pair scope, or `null` when the user has no active
/// connection.
///
/// Rules describe a partner's device, so a rule cannot be authored without an
/// active pair. This provider makes "not connected yet" an explicit, tappable
/// state instead of a form that cannot be saved.
final ruleScopeProvider = Provider<AsyncValue<RuleScope?>>((ref) {
  final uid = ref.watch(currentIdentityProvider)?.uid;
  if (uid == null) return const AsyncData<RuleScope?>(null);
  return ref.watch(partnerScopeProvider).whenData(
    (scope) =>
        scope == null ? null : RuleScope(ownerUserId: uid, pairId: scope.pairId),
  );
});

/// The signed-in user's rules for the active pair (SRS FR-033).
///
/// Loading is explicit and on demand: the rules list reads once when it opens
/// and after a save or delete, rather than installing a listener per rule
/// (SRS Task 24 cost control).
final rulesControllerProvider =
    AsyncNotifierProvider<RulesController, List<Rule>>(RulesController.new);

/// Owns the rule list and every write.
///
/// Widgets never call the repository: they build a [RuleDraft], this controller
/// validates it in the domain layer, and only a valid draft becomes a persisted
/// canonical [Rule] (widget → controller → repository → Firestore).
class RulesController extends AsyncNotifier<List<Rule>> {
  @override
  Future<List<Rule>> build() async {
    final scope = ref.watch(ruleScopeProvider).value;
    if (scope == null) return const <Rule>[];
    return ref
        .read(ruleRepositoryProvider)
        .getRules(ownerUserId: scope.ownerUserId, pairId: scope.pairId);
  }

  /// The currently loaded rules, or an empty list while loading/errored.
  List<Rule> get rules => state.value ?? const <Rule>[];

  /// The loaded rule with [id], or `null`.
  Rule? ruleById(String id) {
    for (final rule in rules) {
      if (rule.id == id) return rule;
    }
    return null;
  }

  /// Re-reads the rules after a failure.
  void retry() => ref.invalidateSelf();

  /// Validates [draft] and persists it atomically.
  ///
  /// Nothing is written incrementally: the whole rule is validated and saved in
  /// one operation, so a rule can never be stored half-edited (SRS FR-037).
  Future<Result<Rule>> saveDraft(RuleDraft draft) async {
    final scope = ref.read(ruleScopeProvider).value;
    if (scope == null) {
      return const Failure<Rule>(
        AuthenticationFailure(
          'Connect with someone before creating a rule.',
        ),
      );
    }

    // Domain validation, not a widget check: a malformed rule cannot reach the
    // repository even if a screen forgets to validate (SRS FR-033).
    final issues = draft.validate();
    if (issues.isNotEmpty) {
      return Failure<Rule>(ValidationFailure(issues.first.message));
    }

    final existing = rules;
    final signature = draft.behaviourSignature;
    for (final rule in existing) {
      if (rule.id == draft.ruleId) continue;
      if (RuleDraft.behaviourSignatureOf(rule) == signature) {
        return const Failure<Rule>(
          ValidationFailure(
            'You already have a rule with the same conditions and '
            'interpretation.',
          ),
        );
      }
    }

    final now = ref.read(clockProvider).nowUtc();
    final id = draft.ruleId ?? ref.read(ruleIdGeneratorProvider).generate();
    final rule = draft.toRule(id: id, nowUtc: now);
    final repository = ref.read(ruleRepositoryProvider);

    try {
      if (draft.isEditing) {
        await repository.updateRule(rule);
      } else {
        await repository.saveRule(rule);
      }
    } catch (error, stackTrace) {
      return Failure<Rule>(_log('saveRule', error, stackTrace));
    }

    final next = <Rule>[
      rule,
      ...existing.where((candidate) => candidate.id != rule.id),
    ];
    state = AsyncData<List<Rule>>(next);
    return Success<Rule>(rule);
  }

  /// Enables or disables [rule] without changing its definition version.
  Future<Result<Rule>> setEnabled(Rule rule, {required bool enabled}) async {
    if (rule.enabled == enabled) return Success<Rule>(rule);
    final updated = rule.copyWith(
      enabled: enabled,
      updatedAt: ref.read(clockProvider).nowUtc(),
    );
    try {
      await ref.read(ruleRepositoryProvider).updateRule(updated);
    } catch (error, stackTrace) {
      return Failure<Rule>(_log('setEnabled', error, stackTrace));
    }
    state = AsyncData<List<Rule>>([
      for (final candidate in rules)
        if (candidate.id == updated.id) updated else candidate,
    ]);
    return Success<Rule>(updated);
  }

  /// Deletes [rule]. Disabled rules are deliberately *not* auto-deleted; only an
  /// explicit delete removes a rule (SRS FR-038).
  Future<Result<void>> removeRule(Rule rule) async {
    try {
      await ref
          .read(ruleRepositoryProvider)
          .deleteRule(
            ownerUserId: rule.ownerUserId,
            pairId: rule.pairId,
            ruleId: rule.id,
          );
    } catch (error, stackTrace) {
      return Failure<void>(_log('deleteRule', error, stackTrace));
    }
    state = AsyncData<List<Rule>>([
      for (final candidate in rules)
        if (candidate.id != rule.id) candidate,
    ]);
    return const Success<void>(null);
  }

  AppFailure _log(String operation, Object error, StackTrace stackTrace) {
    final failure = FirebaseErrorMapper.toFailure(error, stackTrace);
    ref
        .read(loggerProvider)
        .warning(
          'Rule operation failed',
          context: {'operation': operation, 'failureType': failure.type.name},
        );
    return failure;
  }
}
