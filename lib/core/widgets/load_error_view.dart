import 'package:flutter/material.dart';

/// What a screen shows when its data fails to load: a plain sentence and a
/// Retry, never the exception text.
///
/// The error itself is logged once, when this first appears, so the detail
/// still reaches a debugging session without being shown to the user.
class LoadErrorView extends StatefulWidget {
  const LoadErrorView({
    required this.message,
    required this.error,
    required this.onRetry,
    this.stackTrace,
    this.compact = false,
    super.key,
  });

  /// What failed, from the user's side, e.g. "Couldn't load your garage".
  final String message;

  final Object error;
  final StackTrace? stackTrace;
  final VoidCallback onRetry;

  /// A single row for a section inside a screen, instead of a centred block
  /// that takes the whole body.
  final bool compact;

  @override
  State<LoadErrorView> createState() => _LoadErrorViewState();
}

class _LoadErrorViewState extends State<LoadErrorView> {
  @override
  void initState() {
    super.initState();
    debugPrint(
      '${widget.message}: ${widget.error}'
      '${widget.stackTrace == null ? '' : '\n${widget.stackTrace}'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.message, style: theme.textTheme.bodyMedium),
            ),
            TextButton(onPressed: widget.onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              widget.message,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Please try again. If it keeps happening, restart the app.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: widget.onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
