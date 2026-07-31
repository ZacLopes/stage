// WorkLocationsScreen — cidades onde o user quer trabalhar.
//
// Lê a cidade-residência de profile_personal (NÃO de profile_other_locations)
// e pré-marca como chip. Lista também outras cidades já salvas (caso o user
// esteja re-abrindo a tela). User pode remover qualquer chip — só vai pro
// banco o que ele confirmar tocando Continuar.
//
// Antes, LocationScreen escrevia a residência em profile_other_locations
// direto. Causava bug: se o user pulasse essa tela, ficava "preso" a só
// aceitar vagas na cidade onde mora. Agora "onde mora" e "onde quer
// trabalhar" são fontes separadas — esta tela é o único caminho pra
// popular profile_other_locations.
//
// Busca usa API pública do IBGE (lista oficial de municípios brasileiros,
// ~5.570 entries). Carrega 1x na primeira abertura, cacheia em memória,
// filtra client-side conforme o user digita — instantâneo, sem chamadas
// extras à rede.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../../auth/auth_session.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/preferences_view_model.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../../utils/save_with_retry.dart';
import '../onboarding_scaffold.dart';
import 'work_mode_screen.dart';
import '../../../../core/theme/theme.dart';
import '../../domain/location_key.dart';

const _kBorderColor = AppColors.border;
const _kLabelColor = AppColors.textTertiary;
const _kHintColor = AppColors.textDisabled;
const _kTextColor = AppColors.textPrimary;
const _kAccent = AppColors.primary;
const _kError = AppColors.error;
const _kCardBg = AppColors.surfaceVariant;

class WorkLocationsScreen extends StatefulWidget {
  const WorkLocationsScreen({super.key});
  @override
  State<WorkLocationsScreen> createState() => _WorkLocationsScreenState();
}

class _WorkLocationsScreenState extends State<WorkLocationsScreen> {
  DateTime? _shownAt;
  final List<OtherLocation> _locations = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _shownAt = DateTime.now();
    // ignore: unawaited_futures
    Analytics.shared.onboardingPrefStepShown(
      step: 3,
      stepName: 'work_locations',
    );
    // 1) Seed com cidades-de-trabalho já salvas (re-abertura da tela).
    _locations.addAll(context.read<PreferencesViewModel>().otherLocations);

    // 2) Pré-marca a cidade-residência (lendo de profile_personal — fonte
    //    de verdade) se ainda não está na lista. Sem isso, user que veio
    //    direto da LocationScreen veria a tela vazia. User pode remover o
    //    chip da residência se não quer trabalhar lá.
    final personal = context.read<ProfileEditorViewModel>().personal;
    final homeCity = personal?.locationCity?.trim() ?? '';
    if (homeCity.isNotEmpty) {
      final homeState = personal?.locationState ?? '';
      final alreadyInList = _locations.any((l) =>
          (l.city?.toLowerCase() ?? '') == homeCity.toLowerCase() &&
          (l.state ?? '') == homeState);
      if (!alreadyInList) {
        // P2-23 (2ª metade): o card precisa DIZER que foi o app que o pôs
        // ali. Sem isso a pessoa via uma cidade que não digitou e não tinha
        // como saber de onde veio — nem que podia tirar.
        _seededHomeKey = locationKey(homeCity, homeState);
        _locations.add(OtherLocation(
          id: '',
          // user_id é re-carimbado pelo repo no insert (replaceOtherLocations);
          // este valor é placeholder e o save é guardado por PreferencesViewModel.
          userId: currentUserIdOrNull() ?? '',
          city: homeCity,
          state: homeState.isEmpty ? null : homeState,
          country: personal?.locationCountry ?? 'BR',
        ));
      }
    }
  }

  /// Chave (cidade+uf) da cidade que ESTE código semeou a partir do perfil.
  /// Null quando a pessoa chegou aqui sem cidade de residência salva, ou
  /// quando ela mesma já tinha adicionado essa cidade antes.
  String? _seededHomeKey;

  Future<void> _addLocation() async {
    final result = await Navigator.of(context).push<_CitySelection>(
      MaterialPageRoute(builder: (_) => const _CitySearchScreen()),
    );
    if (result != null) {
      // Dedupe por nome+uf
      final exists = _locations.any((l) =>
          (l.city?.toLowerCase() ?? '') == result.city.toLowerCase() &&
          (l.state ?? '') == result.uf);
      if (!exists) {
        setState(() {
          _locations.add(OtherLocation(
            id: '',
            // user_id é re-carimbado pelo repo no insert (replaceOtherLocations);
            // este valor é placeholder e o save é guardado por PreferencesViewModel.
            userId: currentUserIdOrNull() ?? '',
            city: result.city,
            state: result.uf,
            country: 'BR',
          ));
        });
      }
    }
  }

  void _removeLocation(OtherLocation loc) {
    setState(() => _locations.remove(loc));
  }

  Future<void> _continue() async {
    if (_saving) return;
    final vm = context.read<PreferencesViewModel>();
    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => vm.replaceOtherLocations(_locations),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    // ignore: unawaited_futures
    Analytics.shared.onboardingPrefStepAnswered(
      step: 3,
      stepName: 'work_locations',
      valuesCount: _locations.length,
      timeMs: _shownAt != null
          ? DateTime.now().difference(_shownAt!).inMilliseconds
          : 0,
    );
    Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkModeScreen()));
  }

  Future<void> _skip() async {
    if (_saving) return;
    final vm = context.read<PreferencesViewModel>();
    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => vm.replaceOtherLocations([]),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    // ignore: unawaited_futures
    Analytics.shared.onboardingPrefStepSkipped(
      step: 3,
      stepName: 'work_locations',
    );
    Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkModeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Onde você quer trabalhar?',
      subtitle:
          'Adicione cidades específicas — ou toque em "Aceito qualquer lugar".',
      progress: 0.78,
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: (_locations.isEmpty || _saving) ? null : _continue,
      // O botão só aparecia com a lista VAZIA — e o app já adiciona a cidade
      // de residência automaticamente, então na prática ninguém via a saída
      // que o subtítulo prometia ("ou pule"). Pra "pular" era preciso primeiro
      // deletar uma cidade que a pessoa não tinha colocado, o que não é óbvio.
      // Consequência: todo mundo saía do onboarding com um filtro geográfico
      // que não escolheu, encolhendo o próprio feed em silêncio.
      //
      // `_skip` grava lista vazia (`replaceOtherLocations([])`), que é
      // exatamente "aceito qualquer lugar" — então oferecer sempre é correto,
      // e o rótulo agora diz o que a ação faz.
      // Revisão UX 28/07, achado P2-23.
      skipButton: _saving
          ? null
          : TextButton(
              onPressed: _skip,
              style: TextButton.styleFrom(foregroundColor: _kLabelColor),
              child: const Text('Aceito qualquer lugar'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._locations.map((loc) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LocationCard(
                  location: loc,
                  fromProfile:
                      locationKey(loc.city, loc.state) == _seededHomeKey,
                  onRemove: () => _removeLocation(loc),
                ),
              )),
          _AddButton(onTap: _addLocation),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final OtherLocation location;

  /// True quando foi o APP que colocou esta cidade na lista, a partir da
  /// residência informada duas telas antes — não a pessoa.
  final bool fromProfile;
  final VoidCallback onRemove;

  const _LocationCard({
    required this.location,
    required this.onRemove,
    this.fromProfile = false,
  });

  @override
  Widget build(BuildContext context) {
    final state = location.state ?? '';
    final country = location.country == 'BR' ? 'Brasil' : (location.country ?? '');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location.city ?? '',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _kTextColor),
                ),
                if (state.isNotEmpty || country.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [state, country].where((s) => s.isNotEmpty).join(', '),
                    style: const TextStyle(fontSize: 14, color: _kLabelColor),
                  ),
                ],
                // Revisão UX 28/07, achado P2-23: dado que o app inferiu tem
                // que se apresentar como tal. Quem não quiser trabalhar onde
                // mora precisa entender o que está apagando.
                if (fromProfile) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Onde você mora — remova se não quiser trabalhar aqui',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _kLabelColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: _kError, size: 22),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kAccent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kAccent, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28, height: 28,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: _kAccent),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Adicionar cidade',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _kAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Search screen
// ─────────────────────────────────────────────────────────────────────

class _CitySelection {
  final String city;
  final String uf;
  const _CitySelection({required this.city, required this.uf});
}

class _IbgeCity {
  final String name;
  final String uf;
  const _IbgeCity({required this.name, required this.uf});
}

/// Cache em memória da lista de municípios IBGE. ~5.570 entries (~250kb),
/// fetch único por sessão do app.
List<_IbgeCity>? _ibgeCache;

class _CitySearchScreen extends StatefulWidget {
  const _CitySearchScreen();
  @override
  State<_CitySearchScreen> createState() => _CitySearchScreenState();
}

class _CitySearchScreenState extends State<_CitySearchScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();

  List<_IbgeCity> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQueryChanged);
    _ensureCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _ensureCache() async {
    if (_ibgeCache != null) return;
    setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse('https://servicodados.ibge.gov.br/api/v1/localidades/municipios?orderBy=nome'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Não consegui carregar a lista de cidades';
          _loading = false;
        });
        return;
      }
      final list = jsonDecode(res.body) as List;
      _ibgeCache = list.map((j) {
        final m = j as Map<String, dynamic>;
        final uf = (m['microrregiao']?['mesorregiao']?['UF']?['sigla'] as String?) ?? '';
        return _IbgeCity(name: m['nome'] as String, uf: uf);
      }).toList();
      setState(() => _loading = false);
    } catch (_) {
      setState(() {
        _error = 'Erro de conexão. Tente novamente.';
        _loading = false;
      });
    }
  }

  void _onQueryChanged() {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    final cache = _ibgeCache;
    if (cache == null) return;
    // Normaliza acentos pra match tolerante: "sao paulo" pega "São Paulo"
    final normalized = _stripAccents(q);
    final matches = <_IbgeCity>[];
    for (final c in cache) {
      final cityNorm = _stripAccents(c.name.toLowerCase());
      if (cityNorm.startsWith(normalized) || cityNorm.contains(' $normalized')) {
        matches.add(c);
        if (matches.length >= 30) break;
      }
    }
    // Se não achou pelo prefixo, tenta contains genérico
    if (matches.isEmpty) {
      for (final c in cache) {
        final cityNorm = _stripAccents(c.name.toLowerCase());
        if (cityNorm.contains(normalized)) {
          matches.add(c);
          if (matches.length >= 30) break;
        }
      }
    }
    setState(() => _results = matches);
  }

  String _stripAccents(String input) {
    const accents = 'áàâãäåéèêëíìîïóòôõöúùûüçÁÀÂÃÄÅÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const replacements = 'aaaaaaeeeeiiiiooooouuuucAAAAAAEEEEIIIIOOOOOUUUUC';
    final buffer = StringBuffer();
    for (final char in input.split('')) {
      final i = accents.indexOf(char);
      buffer.write(i >= 0 ? replacements[i] : char);
    }
    return buffer.toString();
  }

  void _select(_IbgeCity city) {
    Navigator.pop(context, _CitySelection(city: city.name, uf: city.uf));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: _kTextColor),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: _kCardBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _query,
                focusNode: _focus,
                style: const TextStyle(fontSize: 17, color: _kTextColor),
                decoration: const InputDecoration(
                  hintText: 'Digite uma cidade',
                  hintStyle: TextStyle(color: _kHintColor, fontWeight: FontWeight.w500),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _ibgeCache == null) {
      return const Center(
        child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2.5),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, color: _kHintColor, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kLabelColor, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() => _error = null);
                  _ensureCache();
                },
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }
    if (_query.text.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.search_rounded, color: _kHintColor, size: 56),
              SizedBox(height: 12),
              Text(
                'Comece a digitar pra buscar',
                style: TextStyle(color: _kLabelColor, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'Nenhuma cidade encontrada',
            style: TextStyle(color: _kLabelColor.withValues(alpha: 0.9), fontSize: 14),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: _kBorderColor),
      itemBuilder: (_, i) {
        final c = _results[i];
        return InkWell(
          onTap: () => _select(c),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _kTextColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${c.uf}, Brasil',
                        style: const TextStyle(fontSize: 14, color: _kLabelColor),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.near_me_outlined, color: _kHintColor, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
