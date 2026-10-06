import 'package:speech_to_text/speech_to_text.dart';

// Controla o ciclo de vida do reconhecimento de voz (ditado da descrição)
// usado na Home.
class SpeechController {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  bool get isListening => _speech.isListening;

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (error) => print('Speech error: ${error.errorMsg}'),
    );
    return _initialized;
  }

  Future<void> startListening({
    required void Function(String text) onResult,
    void Function()? onDone,
  }) async {
    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords);
        if (result.finalResult) onDone?.call();
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        localeId: 'pt_BR',
      ),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  void cancel() {
    _speech.cancel();
  }
}
