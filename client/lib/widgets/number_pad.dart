/// The in-app number pad, and the field editing that goes with it.
///
/// iOS's system number pad has no return key, so a form of several numeric
/// fields can only be filled by tapping into each one. Both places in this app
/// that take a column of numbers — the workout logger's sets and the
/// measurement session sheet — drive read-only fields from this pad instead,
/// where Enter advances to the next field and the last field's Enter finishes.
///
/// Fields using it are `readOnly: true, showCursor: true` with an `onTap` that
/// requests focus: read-only keeps the system keyboard away while the field
/// still holds focus and shows a caret.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Inserts [key] at the field's selection, honouring the decimal rule.
///
/// A second '.' is refused rather than producing an unparseable number, and so
/// is any '.' when [decimal] is false (reps are whole).
void typeIntoField(TextEditingController ctrl, bool decimal, String key) {
  final text = ctrl.text;
  final sel = ctrl.selection;
  var start = sel.start;
  var end = sel.end;
  if (start < 0 || end < 0) {
    start = text.length;
    end = text.length;
  }
  final candidate = text.replaceRange(start, end, key);
  if (key == '.' && (!decimal || '.'.allMatches(candidate).length > 1)) {
    return;
  }
  ctrl.value = TextEditingValue(
    text: candidate,
    selection: TextSelection.collapsed(offset: start + key.length),
  );
}

/// Deletes the selection, or the character before the caret when there is none.
void backspaceInField(TextEditingController ctrl) {
  final text = ctrl.text;
  final sel = ctrl.selection;
  var start = sel.start;
  var end = sel.end;
  if (start < 0 || end < 0) {
    start = text.length;
    end = text.length;
  }
  if (start == end) {
    if (start == 0) return;
    ctrl.value = TextEditingValue(
      text: text.replaceRange(start - 1, start, ''),
      selection: TextSelection.collapsed(offset: start - 1),
    );
  } else {
    ctrl.value = TextEditingValue(
      text: text.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
  }
}

class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    required this.onKey,
    required this.onBackspace,
    required this.onEnter,
    required this.onCollapse,
    required this.decimalEnabled,
    required this.isLastField,
  });

  final void Function(String) onKey;
  final VoidCallback onBackspace;
  final VoidCallback onEnter;

  /// Dismisses the pad by dropping focus from the active field. Lets the user
  /// reach content the pad would otherwise cover without leaving the screen.
  final VoidCallback onCollapse;

  /// Reps are whole numbers, so the decimal key is disabled for them.
  final bool decimalEnabled;

  /// The Enter key reads "Done" on the final field, since there is nothing
  /// after it to advance to.
  final bool isLastField;

  @override
  Widget build(BuildContext context) {
    // Keep the pad out of the focus tree so tapping keys never pulls focus off
    // the active field. Stretch so the tall Enter key fills the pad height.
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Material(
        color: AppColors.darkBlue,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CollapseBar(onTap: onCollapse),
                SizedBox(
                  height: 240,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            _row(['1', '2', '3']),
                            _row(['4', '5', '6']),
                            _row(['7', '8', '9']),
                            Expanded(
                              child: Row(
                                children: [
                                  _key(
                                    label: '.',
                                    onTap: decimalEnabled
                                        ? () => onKey('.')
                                        : null,
                                  ),
                                  _key(label: '0', onTap: () => onKey('0')),
                                  _key(
                                    onTap: onBackspace,
                                    child: const Icon(Icons.backspace_outlined),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _button(
                          onTap: onEnter,
                          background: AppColors.primary,
                          foreground: AppColors.onPrimary,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.keyboard_return),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                isLastField ? 'Done' : 'Next',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One row of the digit grid; each key shares the width equally.
  Widget _row(List<String> labels) => Expanded(
    child: Row(
      children: [for (final l in labels) _key(label: l, onTap: () => onKey(l))],
    ),
  );

  /// A key sized to share its row's width equally.
  Widget _key({String? label, Widget? child, VoidCallback? onTap}) =>
      Expanded(child: _button(label: label, child: child, onTap: onTap));

  /// The visual key itself, filling whatever box it is given.
  Widget _button({
    String? label,
    Widget? child,
    VoidCallback? onTap,
    Color? background,
    Color? foreground,
  }) {
    final fg = onTap == null
        ? AppColors.mutedOnDark
        : (foreground ?? AppColors.onDark);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: background ?? AppColors.cta,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          onTap: onTap,
          child: Center(
            child: IconTheme(
              data: IconThemeData(color: fg),
              child:
                  child ??
                  Text(
                    label ?? '',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dismiss affordance across the top of the number pad: a centered grab
/// handle with a chevron, the whole bar tappable to collapse the pad.
class _CollapseBar extends StatelessWidget {
  const _CollapseBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      child: SizedBox(
        height: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cta,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: AppSpacing.sm),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 22,
                  color: AppColors.mutedOnDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
