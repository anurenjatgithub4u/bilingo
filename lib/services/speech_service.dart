import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Something the recogniser reported while listening.
sealed class SpeechEvent {
  const SpeechEvent();
}

/// Words heard in the current listen session. Each result replaces the
/// previous one of the same session; [isFinal] closes the session's text.
class SpeechWords extends SpeechEvent {
  const SpeechWords(this.words, {required this.isFinal});

  final String words;
  final bool isFinal;
}

/// Microphone input level, roughly 0 (quiet) to 1 (loud).
class SpeechLevel extends SpeechEvent {
  const SpeechLevel(this.level);

  final double level;
}

/// The listen session ended and every result has been delivered.
class SpeechDone extends SpeechEvent {
  const SpeechDone();
}

/// The recogniser failed; [code] is one of the `error_*` values below.
class SpeechFailure extends SpeechEvent {
  const SpeechFailure(this.code, {this.permanent = false});

  final String code;
  final bool permanent;

  /// Silence or nothing understood: just listen again.
  bool get isSilence =>
      code == 'error_speech_timeout' || code == 'error_no_match';
  bool get isBusy => code == 'error_busy' || code == 'error_client';
  bool get isNetwork =>
      code == 'error_network' ||
      code == 'error_network_timeout' ||
      code == 'error_server' ||
      code == 'error_server_disconnected' ||
      code == 'error_too_many_requests';
  bool get isPermission => code == 'error_permission';
  bool get isAudio => code == 'error_audio_error';
  bool get isLanguage =>
      code == 'error_language_not_supported' ||
      code == 'error_language_unavailable';
}

enum SpeechAvailability { ready, denied, unavailable }

/// The device speech recogniser, behind an interface so the reading session
/// can be tested with scripted results.
abstract class SpeechEngine {
  Stream<SpeechEvent> get events;

  /// Sets the recogniser up, asking for the microphone permission if needed.
  Future<SpeechAvailability> prepare();

  /// Starts one listen session. Mobile recognisers end a session on their
  /// own after a pause or time limit; the caller starts another.
  Future<void> listen({List<String> hints = const []});

  /// Ends the session, delivering a final result.
  Future<void> stop();

  /// Ends the session and drops any pending result.
  Future<void> cancel();
}

/// [SpeechEngine] backed by the `speech_to_text` plugin (Android
/// SpeechRecognizer / iOS SFSpeechRecognizer). Audio stays with the platform
/// recogniser; only the text comes back to the app.
class DeviceSpeechEngine implements SpeechEngine {
  DeviceSpeechEngine._();

  static final DeviceSpeechEngine instance = DeviceSpeechEngine._();

  final _speech = SpeechToText();
  final _events = StreamController<SpeechEvent>.broadcast();
  bool _ready = false;
  String? _localeId;
  String _language = 'en';

  /// The language to listen for, 'en' or 'de'; takes effect on the next listen.
  set language(String code) {
    if (code == _language) return;
    _language = code;
    _localeId = null;
  }

  // Android reports the RMS level in dB, roughly -2 (quiet) to 10 (loud).
  static const _minLevel = -2.0;
  static const _maxLevel = 10.0;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<SpeechAvailability> prepare() async {
    if (_ready) {
      _localeId ??= await _localeFor(_language);
      return SpeechAvailability.ready;
    }
    try {
      _ready = await _speech.initialize(
        onError: _onError,
        onStatus: _onStatus,
        // The plugin otherwise waits 2 s for a final result after "done".
        finalTimeout: const Duration(milliseconds: 800),
      );
    } catch (_) {
      _ready = false;
    }
    if (!_ready) {
      bool granted;
      try {
        granted = await _speech.hasPermission;
      } catch (_) {
        granted = false;
      }
      return granted
          ? SpeechAvailability.unavailable
          : SpeechAvailability.denied;
    }
    _localeId = await _localeFor(_language);
    return SpeechAvailability.ready;
  }

  /// The device's locale for [lang], preferring the system one if it matches.
  Future<String?> _localeFor(String lang) async {
    final preferred = lang == 'de'
        ? const ['de_DE', 'de-DE', 'de_AT', 'de-AT', 'de_CH', 'de-CH']
        : const ['en_US', 'en-US', 'en_GB', 'en-GB'];
    try {
      final system = await _speech.systemLocale();
      if (system != null && system.localeId.toLowerCase().startsWith(lang)) {
        return system.localeId;
      }
      final locales = await _speech.locales();
      for (final p in preferred) {
        if (locales.any((l) => l.localeId == p)) return p;
      }
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith(lang)) return l.localeId;
      }
    } catch (_) {}
    return preferred.first;
  }

  @override
  Future<void> listen({List<String> hints = const []}) async {
    if (_speech.isListening) throw StateError('Already listening');
    await _speech.listen(
      onResult: _onResult,
      onSoundLevelChange: _onLevel,
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
        // Longest the platforms allow; Android still ends sooner after silence.
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 6),
        localeId: _localeId,
        // Used on iOS to bias recognition towards the passage's words.
        contextualPhrases: hints,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();

  void _onResult(SpeechRecognitionResult r) {
    _events.add(SpeechWords(r.recognizedWords, isFinal: r.finalResult));
  }

  void _onLevel(double level) {
    final t = ((level - _minLevel) / (_maxLevel - _minLevel)).clamp(0.0, 1.0);
    _events.add(SpeechLevel(t));
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus) _events.add(const SpeechDone());
  }

  void _onError(SpeechRecognitionError e) {
    _events.add(SpeechFailure(e.errorMsg, permanent: e.permanent));
  }
}
