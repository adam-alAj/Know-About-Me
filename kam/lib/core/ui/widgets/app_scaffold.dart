import 'package:flutter/material.dart';

/// Consistent page structure so every screen has the same app-bar behaviour and
/// body padding (SRS Task 12, Task 14).
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.padBody = true,
    this.leading,
  });

  /// App-bar title.
  final String title;

  /// Page content.
  final Widget body;

  /// App-bar actions.
  final List<Widget>? actions;

  /// Optional floating action button.
  final Widget? floatingActionButton;

  /// Whether to apply the standard page padding around [body].
  final bool padBody;

  /// Optional leading widget.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions, leading: leading),
      body: padBody
          ? SafeArea(
              child: Padding(padding: const EdgeInsets.all(16), child: body),
            )
          : SafeArea(child: body),
      floatingActionButton: floatingActionButton,
    );
  }
}
