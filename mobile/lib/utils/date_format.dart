/// Formatea una fecha como tiempo relativo al momento actual.
///
/// Ejemplos: 'ahora', 'hace 5m', 'hace 2h', '3/6'
/// Consolidación de _fmt/_formatDate duplicados en los screens de chat.
String formatRelativeDate(DateTime dt) {
  final d = DateTime.now().difference(dt);
  if (d.inMinutes < 1) return 'ahora';
  if (d.inHours < 1) return 'hace ${d.inMinutes}m';
  if (d.inDays < 1) return 'hace ${d.inHours}h';
  return '${dt.day}/${dt.month}';
}
