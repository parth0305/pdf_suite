import 'package:flutter/material.dart';
import 'package:folio/domain/editing/split_plan.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Asks how a document should be divided, previewing the result live.
///
/// Returns the chosen [SplitPlan], or null if dismissed.
Future<SplitPlan?> showSplitSheet(
  BuildContext context, {
  required int pageCount,
}) {
  return showModalBottomSheet<SplitPlan>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _SplitSheet(pageCount: pageCount),
  );
}

class _SplitSheet extends StatefulWidget {
  const _SplitSheet({required this.pageCount});

  final int pageCount;

  @override
  State<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<_SplitSheet> {
  final _field = TextEditingController();
  bool _everyPage = true;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  /// The live preview and the confirm button both derive from this, so an
  /// invalid range cannot be submitted.
  ({SplitPlan? plan, String? error}) get _current {
    if (_everyPage) {
      return (plan: SplitPlan.everyPage(widget.pageCount), error: null);
    }
    try {
      return (
        plan: SplitPlan.parse(_field.text, pageCount: widget.pageCount),
        error: null,
      );
    } on FormatException catch (e) {
      return (plan: null, error: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = _current;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.pagesSplit, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          RadioGroup<bool>(
            groupValue: _everyPage,
            onChanged: (v) => setState(() => _everyPage = v ?? true),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<bool>(
                  value: true,
                  title: Text(l10n.splitEveryPage),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<bool>(
                  value: false,
                  title: Text(l10n.splitByRanges),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          if (!_everyPage)
            TextField(
              controller: _field,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.splitRangeHint,
                border: const OutlineInputBorder(),
                errorText: current.error,
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          const SizedBox(height: 12),
          Text(
            current.plan == null
                ? ''
                : l10n.splitOutputCount(current.plan!.outputCount),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: current.plan == null
                ? null
                : () => Navigator.of(context).pop(current.plan),
            child: Text(l10n.splitConfirm),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
