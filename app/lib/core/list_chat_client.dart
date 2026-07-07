/// Per-list chat WebSocket client (SRS FR-3.4, API Specification §9:
/// ws /lists/{id}/chat). Receives message.created events pushed after
/// POST /lists/{id}/messages.
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'token_store.dart';

class ListChatEvent {
  ListChatEvent({required this.event, required this.payload});

  factory ListChatEvent.fromJson(Map<String, dynamic> json) => ListChatEvent(
        event: json['event'] as String,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );

  final String event;
  final Map<String, dynamic> payload;

  static ListChatEvent? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded['event'] is String) {
        return ListChatEvent.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }
}

class ListChatClient {
  ListChatClient({required this.wsBaseUrl, required this.tokenStore});

  final String wsBaseUrl;
  final TokenStore tokenStore;

  WebSocketChannel? _channel;
  StreamController<ListChatEvent>? _controller;
  String? _activeListId;
  bool _disposed = false;

  Stream<ListChatEvent> connect(String listId) {
    unawaited(_teardown());
    _activeListId = listId;
    _disposed = false;
    final controller = StreamController<ListChatEvent>.broadcast();
    _controller = controller;
    unawaited(_connectAsync(listId, controller, attempt: 0));
    return controller.stream;
  }

  Future<void> _connectAsync(
    String listId,
    StreamController<ListChatEvent> controller, {
    required int attempt,
  }) async {
    if (_disposed || _activeListId != listId) return;
    try {
      final token = await tokenStore.accessToken;
      final uri = Uri.parse('$wsBaseUrl/ws/lists/$listId/chat/').replace(
        queryParameters: token != null ? {'token': token} : null,
      );
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      channel.stream.listen(
        (message) {
          final event = ListChatEvent.tryParse(message as String);
          if (event != null && !controller.isClosed) controller.add(event);
        },
        onError: (_) => _scheduleReconnect(listId, controller, attempt),
        onDone: () => _scheduleReconnect(listId, controller, attempt),
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleReconnect(listId, controller, attempt);
    }
  }

  void _scheduleReconnect(
    String listId,
    StreamController<ListChatEvent> controller,
    int attempt,
  ) {
    if (_disposed || _activeListId != listId || controller.isClosed) return;
    final delay = Duration(milliseconds: 500 * (1 << attempt.clamp(0, 4)));
    Future.delayed(delay, () {
      if (!_disposed && _activeListId == listId && !controller.isClosed) {
        unawaited(_connectAsync(listId, controller, attempt: attempt + 1));
      }
    });
  }

  Future<void> _teardown() async {
    await _channel?.sink.close();
    _channel = null;
    await _controller?.close();
    _controller = null;
  }

  void dispose() {
    _disposed = true;
    _activeListId = null;
    unawaited(_teardown());
  }
}