import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:namer_app/core/localizacao_service.dart';

// Coordenadas da obra; 0,00001° de latitude são cerca de 1,1 m.
const _lat = -19.98;
const _lng = -40.41;
const _umMetro = 0.000009;

void main() {
  final inicio = DateTime(2026, 9, 24, 8);
  DateTime depois(int segundos) => inicio.add(Duration(seconds: segundos));

  group('FiltroKalmanGps', () {
    test('a primeira leitura entra como veio, com a precisão dela', () {
      final filtro = FiltroKalmanGps();
      final ponto = filtro.filtrar(
          latitude: _lat, longitude: _lng, precisao: 8, quando: inicio);
      expect(ponto, const LatLng(_lat, _lng));
      expect(filtro.precisao, closeTo(8, 0.001));
    });

    // O corte de 3 m descartava quase tudo e congelava o ponto. Sem corte, o
    // ponto precisa sair de uma primeira leitura ruim assim que chega uma boa.
    test('sai logo de uma primeira leitura ruim', () {
      final filtro = FiltroKalmanGps();
      filtro.filtrar(
          latitude: _lat, longitude: _lng, precisao: 40, quando: inicio);
      final ponto = filtro.filtrar(
          latitude: _lat + 30 * _umMetro,
          longitude: _lng,
          precisao: 5,
          quando: depois(1));
      final andou = (ponto.latitude - _lat) / (30 * _umMetro);
      expect(andou, greaterThan(0.9),
          reason: 'leitura de 5 m tem que pesar muito mais que a de 40 m');
    });

    test('leitura ruim mal mexe numa posição boa', () {
      final filtro = FiltroKalmanGps();
      for (var s = 0; s < 5; s++) {
        filtro.filtrar(
            latitude: _lat, longitude: _lng, precisao: 4, quando: depois(s));
      }
      final ponto = filtro.filtrar(
          latitude: _lat + 50 * _umMetro,
          longitude: _lng,
          precisao: 50,
          quando: depois(5));
      final andou = (ponto.latitude - _lat) / _umMetro;
      expect(andou, lessThan(2), reason: 'um salto de 50 m com precisão 50 m');
    });

    test('parado, a tremida some e o círculo encolhe', () {
      final filtro = FiltroKalmanGps();
      var ponto = const LatLng(_lat, _lng);
      for (var s = 0; s < 20; s++) {
        // Leituras tremendo ±4 m em volta do mesmo ponto.
        final desvio = (s.isEven ? 4 : -4) * _umMetro;
        ponto = filtro.filtrar(
            latitude: _lat + desvio,
            longitude: _lng,
            precisao: 5,
            quando: depois(s));
      }
      expect(((ponto.latitude - _lat) / _umMetro).abs(), lessThan(2));
      expect(filtro.precisao, lessThan(5));
    });

    // Com a velocidade fixa de quem anda, o ponto ficava arrastando atrás do
    // carro. Informada a velocidade, ele tem que acompanhar.
    test('em veículo acompanha melhor do que a pé', () {
      double quantoAcompanha(double velocidade) {
        final filtro = FiltroKalmanGps();
        for (var s = 0; s < 5; s++) {
          filtro.filtrar(
              latitude: _lat, longitude: _lng, precisao: 5, quando: depois(s));
        }
        final ponto = filtro.filtrar(
            latitude: _lat + 11 * _umMetro,
            longitude: _lng,
            precisao: 5,
            quando: depois(5),
            velocidade: velocidade);
        return (ponto.latitude - _lat) / (11 * _umMetro);
      }

      expect(quantoAcompanha(11), greaterThan(quantoAcompanha(0)));
    });

    test('precisão ausente conta como ruim, nunca como perfeita', () {
      final filtro = FiltroKalmanGps();
      filtro.filtrar(latitude: _lat, longitude: _lng, precisao: 0, quando: inicio);
      expect(filtro.precisao, FiltroKalmanGps.precisaoDesconhecida);
    });
  });

  group('posicaoServeParaCarimbo', () {
    PosicaoGps posicao({double precisao = 5, int idadeSegundos = 0}) =>
        PosicaoGps(const LatLng(_lat, _lng), precisao,
            inicio.subtract(Duration(seconds: idadeSegundos)));

    test('recente e precisa serve', () {
      expect(posicaoServeParaCarimbo(posicao(), inicio), isTrue);
    });

    test('velha não serve', () {
      expect(posicaoServeParaCarimbo(posicao(idadeSegundos: 10), inicio),
          isFalse);
    });

    test('imprecisa não serve', () {
      expect(posicaoServeParaCarimbo(posicao(precisao: 25), inicio), isFalse);
    });

    test('sem posição não serve', () {
      expect(posicaoServeParaCarimbo(null, inicio), isFalse);
    });
  });
}
