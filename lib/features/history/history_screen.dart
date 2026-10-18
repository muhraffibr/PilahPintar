import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/waste_category.dart';
import '../../models/waste_sorting.dart';
import '../../state/monitoring_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';
import 'history_aggregation.dart';
import 'history_detail_screen.dart';
import 'widgets/history_widgets.dart';
import 'widgets/volume_line_chart.dart';

/// Riwayat pemilahan: filter periode → grafik → daftar aktivitas (PRD §6).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _pageSize = 60;

  HistoryPeriod _period = HistoryPeriod.today;
  DateTimeRange? _customRange;
  final Set<WasteCategory> _selected = {...WasteCategory.values};
  List<WasteSorting>? _fetched;
  bool _loading = false;
  String? _error;
  int _visible = _pageSize;
  int _requestId = 0;

  Future<void> _load() async {
    _visible = _pageSize;
    if (_period == HistoryPeriod.today) {
      setState(() {
        _fetched = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    final id = ++_requestId;
    final range = _period.range(DateTime.now(), customRange: _customRange);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context
          .read<MonitoringController>()
          .fetchHistory(range.start, range.end);
      if (!mounted || id != _requestId) return;
      setState(() {
        _fetched = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = 'Gagal memuat riwayat: $e';
        _loading = false;
      });
    }
  }

  Future<void> _selectPeriod(HistoryPeriod period) async {
    if (period == HistoryPeriod.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 1, now.month, now.day),
        lastDate: now,
        initialDateRange: _customRange ??
            DateTimeRange(start: now.subtract(const Duration(days: 2)), end: now),
        helpText: 'Pilih rentang tanggal',
        saveText: 'Terapkan',
      );
      if (picked == null || !mounted) return;
      _customRange = picked;
    }
    _period = period;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonitoringController>();
    final theme = Theme.of(context);
    final now = DateTime.now();
    final range = _period.range(now, customRange: _customRange);
    final isToday = _period == HistoryPeriod.today;
    final source = isToday ? c.todaySortings : (_fetched ?? const <WasteSorting>[]);
    final aggregate = HistoryAggregate.build(source, range);
    final selected = [
      for (final cat in WasteCategory.values)
        if (_selected.contains(cat)) cat,
    ];
    final filtered = [
      for (final s in source)
        if (_selected.contains(s.category)) s,
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final listItems = buildHistoryList(filtered, _visible);
    final showSpinner = !isToday && _loading;
    final hasData = source.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('Riwayat'),
        actions: [
          if (!isToday)
            IconButton(
              tooltip: 'Muat ulang',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: ResponsiveBody(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PeriodFilter(
                        period: _period,
                        customRange: _customRange,
                        onSelected: _selectPeriod,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${Fmt.range(range.start, range.end)} · '
                        '${aggregate.granularity == Granularity.hour ? 'per jam' : 'per hari'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        AppCard(
                          child: EmptyState(
                            compact: true,
                            icon: Icons.sync_problem_rounded,
                            title: 'Riwayat tidak dapat dimuat',
                            message: _error,
                            action: TextButton(
                              onPressed: _load,
                              child: const Text('Coba lagi'),
                            ),
                          ),
                        ),
                      ] else if (showSpinner) ...[
                        const SizedBox(height: 120),
                        const LoadingView(message: 'Memuat riwayat…'),
                      ] else if (!hasData) ...[
                        const SizedBox(height: 12),
                        const AppCard(
                          child: EmptyState(
                            icon: Icons.inbox_outlined,
                            title: 'Belum ada data pemilahan.',
                            message: 'Coba pilih periode lain.',
                          ),
                        ),
                      ] else ...[
                        const SectionHeader(title: 'Ringkasan'),
                        HistorySummaryCard(aggregate: aggregate),
                        const SectionHeader(
                          title: 'Volume dari waktu ke waktu',
                          subtitle: 'Ketuk grafik untuk melihat angka',
                        ),
                        _CategoryFilter(
                          selected: _selected,
                          onChanged: (cat, value) => setState(() {
                            if (value) {
                              _selected.add(cat);
                            } else if (_selected.length > 1) {
                              _selected.remove(cat);
                            }
                          }),
                        ),
                        const SizedBox(height: 10),
                        AppCard(
                          child: VolumeLineChart(
                            aggregate: aggregate,
                            categories: selected,
                          ),
                        ),
                        SectionHeader(
                          title: 'Aktivitas pemilahan',
                          subtitle: '${Fmt.number(filtered.length)} catatan · '
                              'ketuk tanggal untuk detail',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (_error == null && !showSpinner && hasData)
              SliverList.builder(
                itemCount: listItems.length,
                itemBuilder: (context, i) => ResponsiveBody(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildListItem(context, listItems[i], source),
                  ),
                ),
              ),
            if (_error == null && !showSpinner && filtered.length > _visible)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _visible += _pageSize),
                      child: Text(
                        'Tampilkan lebih banyak '
                        '(${Fmt.number(filtered.length - _visible)} lagi)',
                      ),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildListItem(
    BuildContext context,
    HistoryListItem item,
    List<WasteSorting> source,
  ) {
    final p = context.palette;
    return switch (item) {
      final DayHeaderItem header => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: DayHeaderTile(
              item: header,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => HistoryDetailScreen(
                  day: header.day,
                  items: [
                    for (final s in source)
                      if (isSameDay(s.timestamp, header.day)) s,
                  ],
                ),
              )),
            ),
          ),
        ),
      SortingItem(:final sorting) => Material(
          color: p.surface,
          child: SortingRow(
            sorting: sorting,
            onTap: () => showSortingRecordSheet(context, sorting),
          ),
        ),
    };
  }
}

class _PeriodFilter extends StatelessWidget {
  const _PeriodFilter({
    required this.period,
    required this.customRange,
    required this.onSelected,
  });

  final HistoryPeriod period;
  final DateTimeRange? customRange;
  final ValueChanged<HistoryPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in HistoryPeriod.values)
          ChoiceChip(
            label: Text(
              p == HistoryPeriod.custom && customRange != null &&
                      period == HistoryPeriod.custom
                  ? Fmt.range(customRange!.start, customRange!.end)
                  : p.label,
            ),
            avatar: p == HistoryPeriod.custom
                ? const Icon(Icons.date_range_rounded, size: 18)
                : null,
            selected: p == period,
            onSelected: (_) => onSelected(p),
          ),
      ],
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({required this.selected, required this.onChanged});

  final Set<WasteCategory> selected;
  final void Function(WasteCategory category, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in WasteCategory.values)
          FilterChip(
            avatar: LegendSwatch(color: p.category(c)),
            label: Text(c.label),
            selected: selected.contains(c),
            onSelected: (v) => onChanged(c, v),
          ),
      ],
    );
  }
}
