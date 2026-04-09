import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../utils/ui_scale_extensions.dart';

class AppEmpty extends ConsumerWidget {
  final String? text;
  final String? subtext;
  final IconData? icon;
  const AppEmpty({super.key, this.text, this.subtext, this.icon});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(
                icon!,
                size: 64.0.scaled(context, ref),
                color: primaryColor.withValues(alpha: 0.4),
              ),
            if (icon != null) const SizedBox(height: 14),
            Text(text ?? AppLocalizations.of(context).commonEmpty,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (subtext != null) ...[
              const SizedBox(height: 6),
              Text(subtext!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
