import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:badminton_v2_mobile/main.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';

class _MockHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  int? maxConnectionsPerHost;

  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _MockHttpClientRequest();

  @override
  void close({bool force = false}) {}
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = 0;

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  static const _transparentPixel = [
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
    0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 100, 248, 207, 80, 15,
    0, 3, 134, 1, 128, 90, 52, 125, 107, 0, 0, 0, 0, 73, 69, 78, 68,
    174, 66, 96, 130
  ];

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentPixel.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.value(_transparentPixel).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _MockHttpOverrides();
  });

  final testSizes = [
    const Size(360, 640),   // Small Phone Portrait
    const Size(640, 360),   // Small Phone Landscape
    const Size(800, 1280),  // Tablet Portrait
    const Size(1280, 800),  // Web/Desktop & Tablet Landscape
  ];

  final allScreens = [
    'S01', 'S02', 'S03', 'S04', 'S05',
    'S06', 'S07', 'S08', 'S09', 'S10',
    'S11', 'S12', 'S13', 'S14',
    'S15', 'S16', 'S17', 'S18',
    'S19', 'S20', 'S21', 'S22',
    'S23', 'S24', 'S25', 'S26',
    'S27', 'S28', 'S29', 'S30',
  ];

  for (final size in testSizes) {
    testWidgets('Verify zero overflow at ${size.width.toInt()}x${size.height.toInt()} across all 29 screens',
        (WidgetTester tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final appState = AppState();
      await tester.pumpWidget(
        BadmintonV2App(appState: appState),
      );
      await tester.pump();

      for (final screen in allScreens) {
        appState.goTo(screen);
        await tester.pump();
        // Verify no FlutterError or overflow occurred during layout
        expect(tester.takeException(), isNull,
            reason: 'Overflow or layout exception on screen $screen at ${size.width.toInt()}x${size.height.toInt()}');
      }
    });
  }
}
