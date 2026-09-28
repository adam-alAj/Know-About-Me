import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/error/app_failure.dart';
import '../../../../core/firebase/firebase_error_mapper.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/models/rule.dart';
import '../../domain/repositories/rule_repository.dart';
import '../rule_serialization.dart';

/// [RuleRepository] backed by the private rule documents defined in
/// `docs/architecture/FIRESTORE_DATA_MODEL.md` §5:
///
/// ```text
/// users/{ownerUserId}/rules/{ruleId}   owner-only, never partner-readable
/// ```
///
/// The partner never reads rule *definitions*; the partner sees the
/// interpretation a rule produces. The write path is authorized by
/// `firebase/firestore.rules`, not by anything this class does — the checks here
/// only keep the caller honest.
///
/// Only `users/{ownerUserId}/rules` is queried, so a rule lookup can never reach
/// another user's data even if a caller passes a foreign owner id: Firestore
/// denies it at the security-rule layer (SRS constraint: authorization is not a
/// client concern).
class FirestoreRuleRepository implements RuleRepository {
  FirestoreRuleRepository(this._firestore, this._logger);

  final FirebaseFirestore _firestore;
  final AppLogger _logger;

  CollectionReference<Map<String, dynamic>> _rules(String ownerUserId) =>
      _firestore.collection('users').doc(ownerUserId).collection('rules');

  @override
  Future<List<Rule>> getRules({
    required String ownerUserId,
    required String pairId,
  }) async {
    try {
      // A single equality filter uses Firestore's automatic index, so listing
      // rules costs exactly one read per rule and needs no composite index
      // (FIRESTORE_DATA_MODEL §8, §10).
      final snapshot = await _rules(
        ownerUserId,
      ).where('pairId', isEqualTo: pairId).get();
      final rules = <Rule>[];
      for (final document in snapshot.docs) {
        final rule = RuleSerialization.ruleFromMap(
          document.id,
          document.data(),
        );
        // A malformed stored rule is skipped rather than crashing the list; the
        // rule remains deletable from its own screen (SRS FR-048).
        if (rule != null) rules.add(rule);
      }
      // Newest first, computed locally so no ordered index is required.
      rules.sort((a, b) => _updatedAt(b).compareTo(_updatedAt(a)));
      return rules;
    } catch (error, stackTrace) {
      throw _classify('getRules', error, stackTrace);
    }
  }

  @override
  Future<Rule?> getRule({
    required String ownerUserId,
    required String pairId,
    required String ruleId,
  }) async {
    try {
      final snapshot = await _rules(ownerUserId).doc(ruleId).get();
      if (!snapshot.exists) return null;
      final rule = RuleSerialization.ruleFromMap(ruleId, snapshot.data()!);
      if (rule == null) {
        throw const ValidationFailure(
          'This rule could not be read and cannot be edited. You can delete it.',
        );
      }
      return rule;
    } catch (error, stackTrace) {
      throw _classify('getRule', error, stackTrace);
    }
  }

  @override
  Future<void> saveRule(Rule rule) async {
    try {
      await _rules(
        rule.ownerUserId,
      ).doc(rule.id).set(RuleSerialization.toMap(rule));
    } catch (error, stackTrace) {
      throw _classify('saveRule', error, stackTrace);
    }
  }

  @override
  Future<void> updateRule(Rule rule) async {
    try {
      // `update` (not `set`) so an edit can never resurrect a deleted rule.
      await _rules(
        rule.ownerUserId,
      ).doc(rule.id).update(RuleSerialization.toMap(rule, isUpdate: true));
    } catch (error, stackTrace) {
      throw _classify('updateRule', error, stackTrace);
    }
  }

  @override
  Future<void> deleteRule({
    required String ownerUserId,
    required String pairId,
    required String ruleId,
  }) async {
    try {
      final document = _rules(ownerUserId).doc(ruleId);
      final snapshot = await document.get();
      // Scoped delete: never remove a rule that belongs to a different pair
      // context than the caller believes they are operating in.
      if (!snapshot.exists) return;
      if (snapshot.data()?['pairId'] != pairId) {
        throw const ValidationFailure(
          'That rule belongs to a different connection.',
        );
      }
      await document.delete();
    } catch (error, stackTrace) {
      throw _classify('deleteRule', error, stackTrace);
    }
  }

  static DateTime _updatedAt(Rule rule) =>
      rule.updatedAt ?? rule.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  AppFailure _classify(String operation, Object error, StackTrace stackTrace) {
    final failure = FirebaseErrorMapper.toFailure(error, stackTrace);
    // Only non-identifying metadata reaches the log (NFR-045): never a rule
    // name, condition or owner id.
    _logger.warning(
      'Rule operation failed',
      context: {'operation': operation, 'failureType': failure.type.name},
    );
    return failure;
  }
}
