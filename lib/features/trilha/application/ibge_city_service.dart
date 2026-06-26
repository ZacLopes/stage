// Busca de cidades brasileiras no catálogo oficial do IBGE (PLANO-FASE-6 —
// canonização). Espelha a lógica que o onboarding já usa (work_locations), mas
// como SERVIÇO reutilizável pela trilha. Fetch único por instância (cache em
// memória) + filtro local tolerante a acento. Failure-safe: sem rede ⇒ lista
// vazia (a UI cai no texto livre, nunca trava).

import 'dart:convert';

import 'package:http/http.dart' as http;

class IbgeCity {
  final String name;
  final String uf;
  const IbgeCity({required this.name, required this.uf});
}

class IbgeCityService {
  List<IbgeCity>? _cache;
  Future<List<IbgeCity>>? _loading;

  Future<List<IbgeCity>> _ensure() {
    final c = _cache;
    if (c != null) return Future.value(c);
    return _loading ??= _fetch();
  }

  Future<List<IbgeCity>> _fetch() async {
    try {
      final res = await http
          .get(Uri.parse(
              'https://servicodados.ibge.gov.br/api/v1/localidades/municipios?orderBy=nome'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        _loading = null;
        return const [];
      }
      final list = jsonDecode(res.body) as List;
      return _cache = list.map((j) {
        final m = j as Map<String, dynamic>;
        final uf =
            (m['microrregiao']?['mesorregiao']?['UF']?['sigla'] as String?) ?? '';
        return IbgeCity(name: m['nome'] as String, uf: uf);
      }).toList();
    } catch (_) {
      _loading = null; // permite re-tentar numa próxima busca
      return const [];
    }
  }

  /// Busca por prefixo (e "contém" como fallback), tolerante a acento. Até 30.
  Future<List<IbgeCity>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final cache = await _ensure();
    final norm = stripAccents(q);

    final byPrefix = <IbgeCity>[];
    for (final c in cache) {
      final cn = stripAccents(c.name.toLowerCase());
      if (cn.startsWith(norm) || cn.contains(' $norm')) {
        byPrefix.add(c);
        if (byPrefix.length >= 30) break;
      }
    }
    if (byPrefix.isNotEmpty) return byPrefix;

    final byContains = <IbgeCity>[];
    for (final c in cache) {
      if (stripAccents(c.name.toLowerCase()).contains(norm)) {
        byContains.add(c);
        if (byContains.length >= 30) break;
      }
    }
    return byContains;
  }

  static String stripAccents(String input) {
    const accents = 'áàâãäåéèêëíìîïóòôõöúùûüçÁÀÂÃÄÅÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const repl = 'aaaaaaeeeeiiiiooooouuuucAAAAAAEEEEIIIIOOOOOUUUUC';
    final buf = StringBuffer();
    for (final ch in input.split('')) {
      final i = accents.indexOf(ch);
      buf.write(i >= 0 ? repl[i] : ch);
    }
    return buf.toString();
  }
}
