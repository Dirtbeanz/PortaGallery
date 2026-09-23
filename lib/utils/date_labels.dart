const List<String> monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String monthYearLabel(int year, int month) {
  if (month < 1 || month > 12) return '$year-$month';
  return '${monthNames[month - 1]} $year';
}

String daySectionLabel(int year, int month, int day) {
  if (month < 1 || month > 12) return '$year-$month-$day';
  final padded = '$year-${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
  final date = DateTime.tryParse(padded);
  if (date == null) return padded;
  return '${weekdayNames[date.weekday - 1]}, '
      '${monthNames[month - 1]} $day, $year';
}

String formatDateTime(DateTime dt) {
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
