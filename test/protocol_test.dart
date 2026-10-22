import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mibandapp/core/crypto/crc32.dart';
import 'package:mibandapp/core/crypto/huami_crypto.dart';
import 'package:mibandapp/protocol/huami_chunked_encoder.dart';
import 'package:mibandapp/protocol/huami_weather_encoder.dart';
import 'package:mibandapp/models/weather_data.dart';

void main() {
  group('Huami Protocol & Crypto Tests', () {
    test('CRC32 computation matches standard', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final crc = Crc32.compute(data);
      expect(crc, isNonZero);
    });

    test('AES-128 ECB encryption and decryption roundtrip', () {
      final key = Uint8List.fromList(List.generate(16, (i) => i));
      final plaintext = Uint8List.fromList(List.generate(32, (i) => i * 2));

      final encrypted = HuamiCryptoService.encryptAesEcb(plaintext, key);
      expect(encrypted.length, equals(32));
      expect(encrypted, isNot(equals(plaintext)));

      final decrypted = HuamiCryptoService.decryptAesEcb(encrypted, key);
      expect(decrypted, equals(plaintext));
    });

    test('Huami 2021 Session Key derivation', () {
      final authKey = Uint8List.fromList(List.generate(16, (i) => 0xAA));
      final sharedSecret = Uint8List.fromList(List.generate(48, (i) => i));

      final sessionKey = HuamiCryptoService.deriveSessionKey(sharedSecret, authKey);
      expect(sessionKey.length, equals(16));
      for (int i = 0; i < 16; i++) {
        expect(sessionKey[i], equals(sharedSecret[i + 8] ^ authKey[i]));
      }
    });

    test('HuamiWeatherEncoder maps conditions to expected icon codes', () {
      expect(HuamiWeatherEncoder.mapToHuamiWeatherCode(0, 'Ensolarado'), equals(0));
      expect(HuamiWeatherEncoder.mapToHuamiWeatherCode(1, 'Parcialmente Nublado'), equals(1));
      expect(HuamiWeatherEncoder.mapToHuamiWeatherCode(3, 'Nublado'), equals(2));
      expect(HuamiWeatherEncoder.mapToHuamiWeatherCode(61, 'Chuva'), equals(8));
      expect(HuamiWeatherEncoder.mapToHuamiWeatherCode(95, 'Tempestade com Raios'), equals(4));
    });

    test('HuamiWeatherEncoder generates 6 weather packets', () {
      final weather = WeatherData(
        temp: 26,
        condition: 'Ensolarado',
        code: 0,
        city: 'São Paulo',
        humidity: 60,
        windSpeed: 15,
        dailyForecast: [
          DailyForecastItem(day: 'Hoje', tempMax: 28, tempMin: 19, condition: 'Ensolarado', code: 0),
          DailyForecastItem(day: 'Amanhã', tempMax: 29, tempMin: 20, condition: 'Parcialmente Nublado', code: 1),
        ],
      );

      final packets = HuamiWeatherEncoder.generateWeatherPackets(weather);
      expect(packets.length, equals(6));
      expect(packets.map((p) => p.name).toList(), containsAll([
        'Current', 'AirQuality', 'Forecast', 'Location', 'WindHumidity', 'SunriseSunset'
      ]));
    });

    test('HuamiChunkedEncoder slices packets into MTU 23 chunks', () {
      final payload = Uint8List.fromList(List.generate(50, (i) => i));
      final res = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: 144,
        data: payload,
        handle: 1,
      );

      expect(res.chunks, isNotEmpty);
      for (final chunk in res.chunks) {
        expect(chunk[0], equals(0x03)); // Header tag
        expect(chunk.length, lessThanOrEqualTo(23));
      }
    });
  });
}
