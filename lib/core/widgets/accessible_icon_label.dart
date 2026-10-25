import 'package:flutter/material.dart';

/// Icon plus text so status is never conveyed by color alone.
class AccessibleIconLabel extends StatelessWidget {
  const AccessibleIconLabel({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = color ?? theme.colorScheme.onSurface;
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 18 : 22, color: resolved),
          SizedBox(width: dense ? 4 : 8),
          Flexible(
            child: Text(
              label,
              style: (dense
                      ? theme.textTheme.labelMedium
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                color: resolved,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
