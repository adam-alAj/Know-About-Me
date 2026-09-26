import 'package:flutter/material.dart';

import '../../../core/ui/widgets/app_scaffold.dart';
import '../../../core/ui/widgets/empty_view.dart';

/// Placeholder for the rule engine (SRS FR-026 – FR-040).
///
/// Phase 2 establishes the route and layout only; rule creation, evaluation and
/// persistence arrive in a later phase (see
/// `docs/requirements/REQUIREMENT_MAPPING.md`).
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Rules',
      body: EmptyView(
        icon: Icons.rule_outlined,
        title: 'No rules yet',
        message:
            'Rules let you turn observed device state into your own '
            'interpretations, for example "charging for more than four hours '
            'may mean sleeping".\n\nRules are enabled in a later phase.',
      ),
    );
  }
}
