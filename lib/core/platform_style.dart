/// Shared platform decisions and adaptive navigation chrome.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ios_glass.dart';

// Also follows Flutter's platform override, so both designs can be tested.
bool get isApple => defaultTargetPlatform == TargetPlatform.iOS;

class IosColors {
  IosColors._();
  static Color systemGroupedBackground(bool dark) =>
      dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
  static Color secondaryGroupedBackground(bool dark) =>
      dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
  static Color separator(bool dark) =>
      dark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8);
  static Color label(bool dark) => dark ? Colors.white : Colors.black;
  static Color secondaryLabel(bool dark) =>
      dark ? const Color(0x99EBEBF5) : const Color(0x993C3C43);
}

class PageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PageAppBar(
      {super.key, required this.title, this.actions = const [], this.leading});
  final String title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Size get preferredSize => Size.fromHeight(isApple ? 44 : 64);

  @override
  Widget build(BuildContext context) {
    if (!isApple) {
      return AppBar(title: Text(title), actions: actions, leading: leading);
    }
    return IosGlassSurface(
        radius: 0,
        child: CupertinoNavigationBar(
          middle: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          leading: leading,
          backgroundColor: Colors.transparent,
          enableBackgroundFilterBlur: false,
          border: null,
          // Pages share one Navigator; avoid duplicate transition tags in tab views.
          transitionBetweenRoutes: false,
          trailing: actions.isEmpty
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: actions),
        ));
  }
}

class AdaptiveSearchField extends StatelessWidget {
  const AdaptiveSearchField(
      {super.key, required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (isApple) {
      return IosGlassSurface(
          radius: 16,
          child: CupertinoSearchTextField(
            controller: controller,
            placeholder: '搜索应用与服务',
            backgroundColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            onChanged: onChanged,
            onSuffixTap: () {
              controller.clear();
              onChanged('');
            },
          ));
    }
    return SearchBar(
      controller: controller,
      hintText: '搜索应用与服务',
      leading: const Icon(Icons.search),
      elevation: const WidgetStatePropertyAll(0),
      onChanged: onChanged,
      trailing: [
        if (controller.text.isNotEmpty)
          IconButton(
            tooltip: '清除搜索',
            icon: const Icon(Icons.close),
            onPressed: () {
              controller.clear();
              onChanged('');
            },
          ),
      ],
    );
  }
}

class AdaptiveSegments<T extends Object> extends StatelessWidget {
  const AdaptiveSegments(
      {super.key,
      required this.values,
      required this.selected,
      required this.onChanged});
  final Map<T, String> values;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    if (isApple) {
      return CupertinoSlidingSegmentedControl<T>(
        groupValue: selected,
        children: {
          for (final e in values.entries)
            e.key: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(e.value),
            )
        },
        onValueChanged: (value) {
          if (value != null) onChanged(value);
        },
      );
    }
    return SegmentedButton<T>(
      segments: [
        for (final e in values.entries)
          ButtonSegment(value: e.key, label: Text(e.value))
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

Future<void> hapticSelect() => HapticFeedback.selectionClick();

/// A primary action with the platform's feedback and shape.
class AdaptiveFilledButton extends StatelessWidget {
  const AdaptiveFilledButton(
      {super.key, required this.onPressed, required this.child});
  final VoidCallback? onPressed;
  final Widget child;
  @override
  Widget build(BuildContext context) => isApple
      ? CupertinoButton.filled(onPressed: onPressed, child: child)
      : FilledButton(onPressed: onPressed, child: child);
}

Future<DateTime?> pickPlatformDate(BuildContext context, DateTime initial) {
  if (!isApple) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2025, 9, 1),
      lastDate: DateTime(2028, 8, 31),
      helpText: '选择日期',
    );
  }
  return _cupertinoPicker(context, initial, CupertinoDatePickerMode.date);
}

Future<TimeOfDay?> pickPlatformTime(
    BuildContext context, TimeOfDay initial) async {
  if (!isApple) {
    return showTimePicker(context: context, initialTime: initial);
  }
  final date = await _cupertinoPicker(
      context,
      DateTime(2026, 1, 1, initial.hour, initial.minute),
      CupertinoDatePickerMode.time);
  return date == null ? null : TimeOfDay.fromDateTime(date);
}

Future<DateTime?> _cupertinoPicker(
    BuildContext context, DateTime initial, CupertinoDatePickerMode mode) {
  var value = initial;
  FocusScope.of(context).unfocus();
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (ctx) => Container(
      color: CupertinoColors.systemBackground.resolveFrom(ctx),
      child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              CupertinoButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              CupertinoButton(
                  onPressed: () => Navigator.pop(ctx, value),
                  child: const Text('完成')),
            ]),
            SizedBox(
                height: 216,
                child: CupertinoDatePicker(
                  mode: mode,
                  initialDateTime: initial,
                  use24hFormat: true,
                  minimumDate: mode == CupertinoDatePickerMode.date
                      ? DateTime(2025, 9, 1)
                      : null,
                  maximumDate: mode == CupertinoDatePickerMode.date
                      ? DateTime(2028, 8, 31)
                      : null,
                  onDateTimeChanged: (date) => value = date,
                )),
          ])),
    ),
  );
}
