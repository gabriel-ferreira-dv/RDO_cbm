import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// Posição filtrada: onde o usuário provavelmente está, com que precisão e quando.
class PosicaoGps {
  final LatLng ponto;

  // Raio (m) dentro do qual a posição real provavelmente está.
  final double precisaoMetros;
  final DateTime quando;

  const PosicaoGps(this.ponto, this.precisaoMetros, this.quando);

  double get latitude => ponto.latitude;
  double get longitude => ponto.longitude;
}

// Filtro de Kalman simples: cada leitura pesa conforme a precisão informada,
// então leitura ruim mexe pouco no ponto. Tira a tremida, não o desvio de
// fundo (sinal refletido em estruturas).
class FiltroKalmanGps {
  // Velocidade mínima (m/s), a de quem anda; em veículo vale a do GPS.
  static const double velocidadeMinima = 1.5;

  // Precisão (m) assumida quando o aparelho não informa: conta como ruim.
  static const double precisaoDesconhecida = 20;

  double? _lat, _lng;
  double _variancia = -1; // m²; negativo = ainda sem leitura
  DateTime? _ultimaLeitura;

  // Raio de incerteza estimado (m) da posição filtrada.
  double get precisao => _variancia < 0 ? 0 : sqrt(_variancia);

  LatLng filtrar({
    required double latitude,
    required double longitude,
    required double precisao,
    required DateTime quando,
    double velocidade = 0,
  }) {
    final erro =
        precisao.isFinite && precisao > 0 ? precisao : precisaoDesconhecida;
    final anterior = _ultimaLeitura;
    if (_variancia < 0 || _lat == null || _lng == null || anterior == null) {
      _lat = latitude;
      _lng = longitude;
      _variancia = erro * erro;
    } else {
      // Mais tempo ou mais velocidade: a leitura nova pesa mais.
      final segundos = quando.difference(anterior).inMilliseconds / 1000;
      if (segundos > 0) {
        final v = velocidade.isFinite && velocidade > velocidadeMinima
            ? velocidade
            : velocidadeMinima;
        _variancia += segundos * v * v;
      }
      final ganho = _variancia / (_variancia + erro * erro);
      _lat = _lat! + ganho * (latitude - _lat!);
      _lng = _lng! + ganho * (longitude - _lng!);
      _variancia = (1 - ganho) * _variancia;
    }
    _ultimaLeitura = quando;
    return LatLng(_lat!, _lng!);
  }
}

// Se [posicao] serve para carimbar uma foto: recente e precisa o bastante.
bool posicaoServeParaCarimbo(PosicaoGps? posicao, DateTime agora) =>
    posicao != null &&
    agora.difference(posicao.quando) <= LocalizacaoService.idadeMaxima &&
    posicao.precisaoMetros <= LocalizacaoService.precisaoBoa;

// Localização única do app: mapa, minimapa, carimbo e sugestão usam esta.
class LocalizacaoService {
  LocalizacaoService._interno();
  static final LocalizacaoService instancia = LocalizacaoService._interno();

  // Uma posição serve para a foto se for mais nova que isto...
  static const Duration idadeMaxima = Duration(seconds: 3);

  // ... e se o raio de incerteza for menor que isto (m).
  static const double precisaoBoa = 10;

  // Null até a primeira leitura chegar.
  final ValueNotifier<PosicaoGps?> posicao = ValueNotifier(null);

  final FiltroKalmanGps _filtro = FiltroKalmanGps();
  StreamSubscription<Position>? _assinatura;
  Future<bool>? _iniciando;

  // Liga o GPS se preciso (pode chamar várias vezes); false sem GPS ou permissão.
  Future<bool> iniciar() {
    if (_assinatura != null) return Future.value(true);
    return _iniciando ??= _ligar().whenComplete(() => _iniciando = null);
  }

  Future<bool> _ligar() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }
    if (permissao == LocationPermission.denied ||
        permissao == LocationPermission.deniedForever) {
      return false;
    }

    _assinatura = Geolocator.getPositionStream(locationSettings: _configuracao())
        .listen(_aoReceber, onError: (Object erro) {
      debugPrint('GPS: o fluxo de posições parou: $erro');
      // Deixa religar na próxima chamada de iniciar().
      _assinatura?.cancel();
      _assinatura = null;
    });
    return true;
  }

  // Uma leitura por segundo.
  LocationSettings _configuracao() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
  }

  void _aoReceber(Position leitura) {
    final agora = DateTime.now();
    final ponto = _filtro.filtrar(
      latitude: leitura.latitude,
      longitude: leitura.longitude,
      precisao: leitura.accuracy,
      quando: agora,
      velocidade: leitura.speed,
    );
    // Para testar no escritório, troque por um ponto da obra:
    // final ponto = LatLng(-19.989739, -40.413614);
    posicao.value = PosicaoGps(ponto, _filtro.precisao, agora);
  }

  // Posição para carimbar ou sugerir a estaca. Se a atual estiver velha ou imprecisa, espera até [espera] por uma boa; depois, entrega a melhor.
  Future<PosicaoGps?> posicaoConfiavel({
    Duration espera = const Duration(seconds: 5),
  }) async {
    await iniciar();
    if (posicaoServeParaCarimbo(posicao.value, DateTime.now())) {
      return posicao.value;
    }

    final boa = Completer<PosicaoGps?>();
    void conferir() {
      if (!boa.isCompleted &&
          posicaoServeParaCarimbo(posicao.value, DateTime.now())) {
        boa.complete(posicao.value);
      }
    }

    posicao.addListener(conferir);
    try {
      final resultado =
          await boa.future.timeout(espera, onTimeout: () => posicao.value);
      return resultado ?? await _ultimaConhecida();
    } finally {
      posicao.removeListener(conferir);
    }
  }

  Future<PosicaoGps?> _ultimaConhecida() async {
    try {
      final ultima = await Geolocator.getLastKnownPosition();
      if (ultima == null) return null;
      return PosicaoGps(LatLng(ultima.latitude, ultima.longitude),
          ultima.accuracy, ultima.timestamp);
    } catch (e) {
      debugPrint('GPS: sem última posição conhecida: $e');
      return null;
    }
  }
}
