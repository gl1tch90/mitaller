import '../models/ticket.dart';
import '../models/work_order.dart';

/// Normaliza para comparar: minúsculas y sin acentos.
String _norm(String s) {
  const withAccents = 'áàäâéèëêíìïîóòöôúùüûñç';
  const plain = 'aaaaeeeeiiiioooouuuunc';
  var r = s.toLowerCase();
  for (var i = 0; i < withAccents.length; i++) {
    r = r.replaceAll(withAccents[i], plain[i]);
  }
  return r;
}

bool _has(String haystack, String q) => _norm(haystack).contains(_norm(q));

/// ¿Coincide el ticket con la búsqueda? (folio, cliente, teléfono,
/// carro, placas, mecánico). Query vacía = todo coincide.
bool ticketMatches(Ticket t, String query) {
  final q = query.trim();
  if (q.isEmpty) return true;
  final v = t.vehicle;
  return _has(t.id, q) ||
      _has(t.customer.name, q) ||
      _has(t.customer.phone, q) ||
      _has(v.brand, q) ||
      _has(v.model, q) ||
      _has('${v.brand} ${v.model}', q) ||
      _has(v.plate, q) ||
      _has(t.mechanicName, q);
}

/// ¿Coincide la orden con la búsqueda? (folio, cliente, teléfono,
/// carro, placas, servicio o descripción).
bool orderMatches(WorkOrder o, String query) {
  final q = query.trim();
  if (q.isEmpty) return true;
  final v = o.vehicle;
  return _has(o.folio, q) ||
      _has(o.customer.name, q) ||
      _has(o.customer.phone, q) ||
      _has(v.brand, q) ||
      _has(v.model, q) ||
      _has('${v.brand} ${v.model}', q) ||
      _has(v.plate, q) ||
      o.lines.any((l) =>
          _has(l.name, q) || (l.note != null && _has(l.note!, q)));
}
