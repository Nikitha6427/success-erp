import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class LoadingListSkeleton extends StatelessWidget {
  final int itemCount;

  const LoadingListSkeleton({this.itemCount = 6, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerHigh;
    final shimmerColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerLow
        : theme.colorScheme.surfaceContainerLowest;

    return Shimmer.fromColors(
      baseColor: surfaceColor,
      highlightColor: shimmerColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: itemCount,
        itemBuilder: (_, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}
