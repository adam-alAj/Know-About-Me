import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/ui/widgets/app_inline_message.dart';
import '../../domain/models/rule.dart';

/// Summarises rule validation problems in one accessible block (SRS FR-033).
///
/// Shows every issue at once so a user can fix them in one pass, and uses
/// [AppInlineMessage], which is a live region and pairs an icon with the text
/// rather than relying on colour (SRS NFR-028).
class RuleValidationMessage extends StatelessWidget {
  const RuleValidationMessage({super.key, required this.issues});

  final List<RuleValidationIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final lines = issues.map((issue) => '• ${issue.message}').join('\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppInlineMessage(
        tone: AppMessageTone.warning,
        title: issues.length == 1
            ? 'One thing to fix'
            : '${issues.length} things to fix',
        message: lines,
      ),
    );
  }
}
