// LocationScreen — onde o user mora.
//
// Tela única que une (1) localização principal de trabalho e (2) onde mora.
// A primary city é usada pra match de vagas próximas + popula personal_info.
//
// 2 modos:
// - INITIAL: pin grande + 2 CTAs ("Inserir manualmente" | "Usar localização atual")
// - FORM: input CEP com auto-lookup via ViaCEP + botão GPS no canto pra
//   re-detectar. Cidade/estado aparecem resolvidos abaixo.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../../auth/auth_session.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../../utils/save_with_retry.dart';
import '../onboarding_scaffold.dart';
import 'work_locations_screen.dart';
import '../../../../core/theme/theme.dart';

const _kBorderColor = AppColors.border;
const _kLabelColor = AppColors.textTertiary;
const _kHintColor = AppColors.textDisabled;
const _kTextColor = AppColors.textPrimary;
const _kAccent = AppColors.primary;
const _kError = AppColors.error;
const _kCardBg = AppColors.surfaceVariant;

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  DateTime? _shownAt;
  // Modo: false = empty state (pin + 2 buttons); true = form com CEP
  bool _formMode = false;

  final _cep = TextEditingController();
  /// Usado pra levar o cursor ao CEP quando o GPS falha/estoura o prazo —
  /// a mensagem de erro aponta pra cá, então o foco vai junto.
  final _cepFocus = FocusNode();
  String? _resolvedCity;
  String? _resolvedState;

  Timer? _cepDebounce;
  bool _cepLoading = false;
  bool _gpsLoading = false;
  bool _saving = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _shownAt = DateTime.now();
    // ignore: unawaited_futures
    Analytics.shared.onboardingPrefStepShown(
      step: 2,
      stepName: 'location',
    );
    _cep.addListener(_onCepTyped);
    _hydrateFromPrefs();
  }

  /// Hidrata só se o user já passou por essa tela antes. O discriminador é
  /// o CEP: dados de extração do CV NÃO populam locationPostalCode, então
  /// se ele tá preenchido sabemos que veio daqui mesmo. Cobre os cenários
  /// "voltou uma tela" e "reabriu o app outro dia".
  Future<void> _hydrateFromPrefs() async {
    // Garante que personal_info tá carregado (pode rodar antes do load).
    final profileVm = context.read<ProfileEditorViewModel>();
    if (profileVm.personal == null) {
      await profileVm.load();
      if (!mounted) return;
    }
    final p = profileVm.personal;
    final cep = p?.locationPostalCode;
    if (cep == null || cep.isEmpty) return;
    setState(() {
      _cep.text = cep;
      _resolvedCity = p?.locationCity;
      _resolvedState = p?.locationState;
      _formMode = true;
    });
  }

  @override
  void dispose() {
    _cep.dispose();
    _cepFocus.dispose();
    _cepDebounce?.cancel();
    super.dispose();
  }

  // ── CEP lookup ──────────────────────────────────────────────────────

  void _onCepTyped() {
    final digits = _cep.text.replaceAll(RegExp(r'\D'), '');
    _cepDebounce?.cancel();
    if (digits.length == 8) {
      _cepDebounce = Timer(const Duration(milliseconds: 350), () => _lookupCep(digits));
    } else if (_resolvedCity != null || _hint != null) {
      setState(() {
        _resolvedCity = null;
        _resolvedState = null;
        _hint = null;
      });
    }
  }

  Future<void> _lookupCep(String cep) async {
    setState(() {
      _cepLoading = true;
      _hint = null;
    });
    try {
      final res = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        setState(() {
          _hint = 'Não consegui buscar o CEP. Tente de novo.';
          _cepLoading = false;
        });
        return;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['erro'] == true) {
        setState(() {
          _hint = 'CEP não encontrado';
          _resolvedCity = null;
          _resolvedState = null;
          _cepLoading = false;
        });
        return;
      }
      setState(() {
        _resolvedCity = json['localidade'] as String?;
        _resolvedState = json['uf'] as String?;
        _cepLoading = false;
      });
    } on TimeoutException {
      setState(() {
        _hint = 'Tempo esgotado. Verifique sua conexão.';
        _cepLoading = false;
      });
    } catch (_) {
      setState(() {
        _hint = 'Erro ao buscar CEP';
        _cepLoading = false;
      });
    }
  }

  // ── GPS ─────────────────────────────────────────────────────────────

  Future<void> _detectGps() async {
    setState(() {
      _formMode = true;
      _gpsLoading = true;
      _hint = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _hint = 'Localização desligada nas Configurações.';
          _gpsLoading = false;
        });
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _hint = 'Sem permissão. Digite o CEP manualmente.';
          _gpsLoading = false;
        });
        return;
      }
      // `timeLimit` é o que impede o spinner infinito: sem ele,
      // `getCurrentPosition` simplesmente NÃO retorna quando o device não
      // consegue fix (indoor, modo econômico, permissão só-quando-em-uso sem
      // sinal). Nem o try nem o catch completavam, `_gpsLoading` ficava preso
      // em true e a pessoa via um spinner girando pra sempre — sem erro, sem
      // saída, do lado de um campo de CEP que funciona.
      // Estourado o prazo, vira TimeoutException e cai no catch abaixo.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await geocoding.setLocaleIdentifier('pt_BR');
      // Reverse geocoding também é rede: mesmo tratamento.
      final placemarks = await geocoding
          .placemarkFromCoordinates(pos.latitude, pos.longitude)
          .timeout(const Duration(seconds: 8));
      if (placemarks.isEmpty) {
        setState(() {
          _hint = 'Não consegui identificar sua cidade.';
          _gpsLoading = false;
        });
        return;
      }
      final p = placemarks.first;
      final city = (p.subAdministrativeArea?.trim().isNotEmpty == true)
          ? p.subAdministrativeArea!
          : (p.locality ?? '');
      final state = _normalizeStateName(p.administrativeArea ?? '');
      final postal = (p.postalCode ?? '').replaceAll(RegExp(r'\D'), '');

      // Atualiza CEP no input (formato 12345-678). Listener vai validar +
      // re-bater no ViaCEP, sobrescrevendo cidade/estado se houver divergência.
      if (postal.length == 8) {
        _cep.text = '${postal.substring(0, 5)}-${postal.substring(5)}';
      }
      setState(() {
        _resolvedCity = city;
        _resolvedState = state;
        _gpsLoading = false;
      });
    } catch (_) {
      setState(() {
        // Mensagem com SAÍDA: o campo de CEP logo abaixo resolve em segundos e
        // é o caminho que de fato funciona. "Erro ao buscar localização"
        // sozinho não dizia o que fazer.
        _hint = 'Não consegui pegar sua localização. Digite seu CEP abaixo.';
        _gpsLoading = false;
      });
      // Leva o cursor pro campo que resolve, em vez de deixar a pessoa
      // procurar o próximo passo.
      if (mounted) FocusScope.of(context).requestFocus(_cepFocus);
    }
  }

  /// iOS retorna `administrativeArea` em formato variado ("São Paulo", "SP").
  /// Mapeia pros 2 caracteres oficiais quando reconhece.
  String _normalizeStateName(String raw) {
    final s = raw.trim();
    if (s.length == 2) return s.toUpperCase();
    const map = {
      'são paulo': 'SP', 'rio de janeiro': 'RJ', 'minas gerais': 'MG',
      'paraná': 'PR', 'rio grande do sul': 'RS', 'distrito federal': 'DF',
      'pernambuco': 'PE', 'bahia': 'BA', 'ceará': 'CE', 'santa catarina': 'SC',
      'goiás': 'GO', 'amazonas': 'AM', 'espírito santo': 'ES', 'pará': 'PA',
      'maranhão': 'MA', 'mato grosso': 'MT', 'mato grosso do sul': 'MS',
      'rio grande do norte': 'RN', 'paraíba': 'PB', 'alagoas': 'AL',
      'piauí': 'PI', 'sergipe': 'SE', 'rondônia': 'RO', 'tocantins': 'TO',
      'acre': 'AC', 'amapá': 'AP', 'roraima': 'RR',
    };
    return map[s.toLowerCase()] ?? s;
  }

  // ── Continue ────────────────────────────────────────────────────────

  bool get _canContinue => _resolvedCity != null && _resolvedCity!.isNotEmpty;

  Future<void> _continue() async {
    if (!_canContinue || _saving) return;
    final userId = currentUserIdOrNull();
    if (userId == null) {
      // ignore: unawaited_futures
      handleSessionLost(context);
      return;
    }
    final profileVm = context.read<ProfileEditorViewModel>();

    // Salva APENAS em profile_personal.location_*. A tela seguinte
    // (WorkLocationsScreen) lê essa cidade em memória pra pré-marcar como
    // chip — sem escrever em profile_other_locations aqui. Antes essa
    // tela já adicionava a residência em other_locations, e se o user
    // pulasse a próxima tela, ele ficava "preso" a aceitar vagas só na
    // cidade dele. Agora "onde mora" e "onde quer trabalhar" são fontes
    // separadas — só vão pra other_locations as cidades que o user
    // explicitamente confirmar na próxima tela.
    final base = profileVm.personal ?? PersonalInfo(userId: userId);
    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => profileVm.commitPersonal(base.copyWith(
        locationCity: _resolvedCity,
        locationState: _resolvedState,
        locationCountry: 'BR',
        // CEP é o marcador de "user passou por essa tela" — usado pra
        // hidratar na próxima visita.
        locationPostalCode: _cep.text.trim().isEmpty ? null : _cep.text.trim(),
      )),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;

    // ignore: unawaited_futures
    Analytics.shared.onboardingPrefStepAnswered(
      step: 2,
      stepName: 'location',
      valuesCount: 1,
      timeMs: _shownAt != null
          ? DateTime.now().difference(_shownAt!).inMilliseconds
          : 0,
    );
    Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkLocationsScreen()));
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Onde você mora?',
      subtitle: 'Vamos usar pra te mostrar vagas próximas.',
      progress: 0.75,
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: (_formMode && _canContinue && !_saving) ? _continue : null,
      customFooter: _formMode ? null : _buildInitialFooter(),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: _formMode ? _buildForm() : _buildInitialHero(),
      ),
    );
  }

  Widget _buildInitialHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: SizedBox(
          width: 240, height: 240,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Onda externa (mais transparente — sensação de pulse/GPS)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kAccent.withValues(alpha: 0.06),
                ),
              ),
              // Onda do meio
              Container(
                width: 180, height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kAccent.withValues(alpha: 0.11),
                ),
              ),
              // Disco central com glow verde
              Container(
                width: 130, height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Colors.white, AppColors.successSoft],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kAccent.withValues(alpha: 0.22),
                      blurRadius: 28,
                    ),
                  ],
                ),
              ),
              // Pin com sombra avermelhada (impressão de "está apontando aqui")
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Icon(
                  Icons.location_on,
                  size: 88,
                  color: _kError,
                  shadows: [
                    Shadow(
                      color: _kError.withValues(alpha: 0.4),
                      offset: const Offset(0, 6),
                      blurRadius: 14,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitialFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 56,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => setState(() => _formMode = true),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kAccent,
                side: const BorderSide(color: _kAccent, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: const Text('Inserir manualmente',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _detectGps,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: const Text('Usar localização atual',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Center(
          child: SizedBox(
            width: 140, height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kAccent.withValues(alpha: 0.08),
                  ),
                ),
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Colors.white, AppColors.successSoft],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _kAccent.withValues(alpha: 0.18),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Icon(
                    Icons.location_on,
                    size: 56,
                    color: _kError,
                    shadows: [
                      Shadow(
                        color: _kError.withValues(alpha: 0.35),
                        offset: const Offset(0, 4),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: _GpsIconButton(loading: _gpsLoading, onTap: _gpsLoading ? null : _detectGps),
        ),
        const SizedBox(height: 16),
        const Text(
          'CEP',
          style: TextStyle(fontSize: 13, color: _kLabelColor, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _cep,
          focusNode: _cepFocus,
          keyboardType: TextInputType.number,
          inputFormatters: [_CepFormatter()],
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _kTextColor),
          decoration: InputDecoration(
            hintText: '12345-678',
            hintStyle: const TextStyle(color: _kHintColor, fontWeight: FontWeight.w500, fontSize: 15),
            filled: true,
            fillColor: _kCardBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            suffixIcon: _cepLoading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
                    ),
                  )
                : (_cep.text.isEmpty
                    ? null
                    : GestureDetector(
                        onTap: () {
                          _cep.clear();
                          setState(() {
                            _resolvedCity = null;
                            _resolvedState = null;
                            _hint = null;
                          });
                        },
                        child: const Icon(Icons.cancel, color: _kHintColor, size: 20),
                      )),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kBorderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kBorderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kAccent, width: 1.5),
            ),
          ),
        ),
        if (_hint != null) ...[
          const SizedBox(height: 8),
          Text(_hint!, style: const TextStyle(fontSize: 12, color: _kError)),
        ],
        if (_resolvedCity != null && _resolvedCity!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 18, color: _kLabelColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [_resolvedCity, _resolvedState, 'Brasil']
                      .where((s) => s != null && s.isNotEmpty)
                      .join(', '),
                  style: const TextStyle(fontSize: 15, color: _kLabelColor, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _GpsIconButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _GpsIconButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Quadrado de 44pt sem texto: pro VoiceOver era um botão sem nome, e em
    // loading virava só um spinner solto encostado na margem direita, sem
    // dizer o que estava carregando. Semantics dá nome e estado.
    // O Semantics resolvia pro VoiceOver, mas quem ENXERGA continuava diante
    // de um quadrado de 44pt sem texto — e, durante os 8s de busca, de um
    // spinner solto encostado na margem direita, sem dizer o que carregava.
    // Rótulo visível resolve os dois de uma vez (achado P1-7).
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: loading ? 'Buscando sua localização' : 'Usar localização atual',
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: _kBorderColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kAccent),
                  )
                else
                  const Icon(Icons.my_location_rounded,
                      color: _kAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  loading ? 'Buscando…' : 'Usar minha localização',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _kAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Formata input do CEP como 12345-678. Garante max 8 dígitos.
class _CepFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final clipped = digits.length > 8 ? digits.substring(0, 8) : digits;
    final formatted = clipped.length > 5
        ? '${clipped.substring(0, 5)}-${clipped.substring(5)}'
        : clipped;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
