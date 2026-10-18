import 'package:intl/intl.dart';

/// Format tanggal/waktu/angka berbahasa Indonesia.
///
/// Membutuhkan `initializeDateFormatting('id_ID')` (dipanggil di `main`).
abstract final class Fmt {
  static final _hm = DateFormat('HH:mm');
  static final _hms = DateFormat('HH:mm:ss');
  static final _dayLong = DateFormat('EEEE, d MMMM yyyy', 'id_ID');
  static final _dayShort = DateFormat('d MMM', 'id_ID');
  static final _dayShortYear = DateFormat('d MMM yyyy', 'id_ID');
  static final _dayNumeric = DateFormat('d/M');
  static final _dayMonthTime = DateFormat('d MMM, HH:mm', 'id_ID');
  static final _dayMonthTimeSec = DateFormat('d MMM, HH:mm:ss', 'id_ID');
  static final _full = DateFormat('EEEE, d MMMM yyyy · HH:mm:ss', 'id_ID');
  static final _number = NumberFormat.decimalPattern('id_ID');

  static String time(DateTime t) => _hm.format(t);
  static String timeSeconds(DateTime t) => _hms.format(t);
  static String dayLong(DateTime t) => _dayLong.format(t);
  static String dayShort(DateTime t) => _dayShort.format(t);
  static String dayShortYear(DateTime t) => _dayShortYear.format(t);
  static String dayNumeric(DateTime t) => _dayNumeric.format(t);
  static String full(DateTime t) => _full.format(t);
  static String number(num n) => _number.format(n);

  /// "94,3" — desimal dengan koma sesuai format Indonesia.
  static String decimal(num n, int digits) => NumberFormat.decimalPatternDigits(
        locale: 'id_ID',
        decimalDigits: digits,
      ).format(n);
  static String percent(num n) => '${n.round()}%';

  /// "12:43:21" bila hari ini, "3 Okt, 12:43:21" bila hari lain,
  /// "Data unavailable" bila belum pernah ada data.
  static String lastUpdate(DateTime? t, {DateTime? now}) {
    if (t == null) return 'Data unavailable';
    final ref = now ?? DateTime.now();
    return isSameDay(t, ref) ? _hms.format(t) : _dayMonthTimeSec.format(t);
  }

  static String relative(DateTime t, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final diff = ref.difference(t);
    if (diff.inSeconds < 60) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (isSameDay(t, ref)) return '${diff.inHours} jam lalu';
    if (isSameDay(t, ref.subtract(const Duration(days: 1)))) {
      return 'Kemarin, ${_hm.format(t)}';
    }
    return _dayMonthTime.format(t);
  }

  static String range(DateTime start, DateTime end) {
    if (isSameDay(start, end)) return _dayShortYear.format(start);
    if (start.year == end.year) {
      return '${_dayShort.format(start)} – ${_dayShortYear.format(end)}';
    }
    return '${_dayShortYear.format(start)} – ${_dayShortYear.format(end)}';
  }
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

DateTime endOfDay(DateTime t) =>
    DateTime(t.year, t.month, t.day + 1).subtract(const Duration(milliseconds: 1));

int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;
