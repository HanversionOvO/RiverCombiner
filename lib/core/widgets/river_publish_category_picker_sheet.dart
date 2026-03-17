import 'package:flutter/material.dart';
import 'package:river/core/network/riverside_topic_models.dart';

class RiverPublishCategoryPickerTab {
  const RiverPublishCategoryPickerTab({
    required this.id,
    required this.label,
  });

  final int id;
  final String label;
}

class RiverPublishCategoryPickerSection {
  const RiverPublishCategoryPickerSection({
    required this.title,
    required this.categories,
  });

  final String title;
  final List<RiverSideCategoryOption> categories;
}

class RiverPublishCategoryPickerPayload {
  const RiverPublishCategoryPickerPayload({
    required this.tabs,
    required this.sectionsByTab,
  });

  final List<RiverPublishCategoryPickerTab> tabs;
  final Map<int, List<RiverPublishCategoryPickerSection>> sectionsByTab;
}

class RiverPublishCategoryPickerSheet extends StatefulWidget {
  const RiverPublishCategoryPickerSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.payload,
    required this.selectedCategoryId,
    required this.onRefresh,
    required this.onSelected,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final RiverPublishCategoryPickerPayload payload;
  final int? selectedCategoryId;
  final Future<RiverPublishCategoryPickerPayload> Function() onRefresh;
  final ValueChanged<RiverSideCategoryOption> onSelected;

  @override
  State<RiverPublishCategoryPickerSheet> createState() =>
      _RiverPublishCategoryPickerSheetState();
}

class _RiverPublishCategoryPickerSheetState
    extends State<RiverPublishCategoryPickerSheet> {
  late RiverPublishCategoryPickerPayload _payload;
  late int _activeTabId;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _payload = widget.payload;
    _activeTabId = _resolveInitialTabId(widget.selectedCategoryId);
  }

  int _resolveInitialTabId(int? selectedCategoryId) {
    if (selectedCategoryId != null) {
      for (final entry in _payload.sectionsByTab.entries) {
        for (final section in entry.value) {
          if (section.categories.any((item) => item.id == selectedCategoryId)) {
            return entry.key;
          }
        }
      }
    }
    if (_payload.tabs.isNotEmpty) {
      return _payload.tabs.first.id;
    }
    return 0;
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      final payload = await widget.onRefresh();
      if (!mounted) {
        return;
      }
      setState(() {
        _payload = payload;
        _activeTabId = _resolveInitialTabId(widget.selectedCategoryId);
      });
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sections = _payload.sectionsByTab[_activeTabId] ??
        const <RiverPublishCategoryPickerSection>[];
    final maxHeight = MediaQuery.sizeOf(context).height * 0.76;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 16, 14),
              child: Row(
                children: [
                  Icon(widget.icon, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _refreshing ? null : _refresh,
                    tooltip: '刷新板块',
                    icon: _refreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (_payload.tabs.length > 1)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _payload.tabs.map((tab) {
                          final selected = tab.id == _activeTabId;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(tab.label),
                              selected: selected,
                              onSelected: (_) {
                                setState(() {
                                  _activeTabId = tab.id;
                                });
                              },
                              showCheckmark: false,
                              labelStyle: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                              selectedColor: colorScheme.primaryContainer,
                              backgroundColor: colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.4),
                              side: BorderSide.none,
                            ),
                          );
                        }).toList(growable: false),
                      ),
                    ),
                  if (_payload.tabs.length > 1) const SizedBox(height: 16),
                  if (sections.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Text(
                          '暂无可选板块',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    ...sections.map((section) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _RiverPublishCategorySectionCard(
                          title: section.title,
                          categories: section.categories,
                          selectedCategoryId: widget.selectedCategoryId,
                          onSelected: widget.onSelected,
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiverPublishCategorySectionCard extends StatelessWidget {
  const _RiverPublishCategorySectionCard({
    required this.title,
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
  });

  final String title;
  final List<RiverSideCategoryOption> categories;
  final int? selectedCategoryId;
  final ValueChanged<RiverSideCategoryOption> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories.map((category) {
              final selected = selectedCategoryId == category.id;
              return FilterChip(
                label: Text(category.name),
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => onSelected(category),
                side: BorderSide.none,
                backgroundColor: colorScheme.surface,
                selectedColor: colorScheme.primaryContainer,
                labelStyle: TextStyle(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }
}
