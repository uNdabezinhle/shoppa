/// Real-time list collaboration (SRS FR-3.2, API Specification §9:
/// ws /lists/{id}). Server -> client only: item.*, list.scaled,
/// collaborator.*, presence.joined, presence.left.
///
/// Item and scale events are applied incrementally via
/// [applyListRealtimeEvent]; collaborator events still trigger a full
/// REST detail refetch. Presence updates the live-editing banner.
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'token_store.dart';

enum RealtimeConnectionState { connecting, connected, reconnecting }

class ListRealtimeEvent {
  ListRealtimeEvent({required this.event, required this.payload});

  factory ListRealtimeEvent.fromJson(Map<String, dynamic> json) =>
      ListRealtimeEvent(
        event: json['event'] as String,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );

  final String event;
  final Map<String, dynamic> payload;

  static ListRealtimeEvent? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded['event'] is String) {
        return ListRealtimeEvent.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }
}

class ListRealtimeClient {
  ListRealtimeClient({required this.wsBaseUrl, required this.tokenStore});

  final String wsBaseUrl;
  final TokenStore tokenStore;

  WebSocketChannel? _channel;
  StreamController<ListRealtimeEvent>? _controller;
  final _connectionState = StreamController<RealtimeConnectionState>.broadcast();
  String? _activeListId;
  bool _disposed = false;

  Stream<RealtimeConnectionState> get connectionState =>
      _connectionState.stream;

  Stream<ListRealtimeEvent> connect(String listId) {
    unawaited(_teardown());
    _activeListId = listId;
    _disposed = false;
    final controller = StreamController<ListRealtimeEvent>.broadcast();
    _controller = controller;
    _emitState(RealtimeConnectionState.connecting);
    unawaited(_connectAsync(listId, controller, attempt: 0));
    return controller.stream;
  }

  void _emitState(RealtimeConnectionState state) {
    if (!_connectionState.isClosed) {
      _connectionState.add(state);
    }
  }

  Future<void> _connectAsync(
    String listId,
    StreamController<ListRealtimeEvent> controller, {
    required int attempt,
  }) async {
    if (_disposed || _activeListId != listId) return;
    if (attempt > 0) _emitState(RealtimeConnectionState.reconnecting);
    try {
      final token = await tokenStore.accessToken;
      final uri = Uri.parse('$wsBaseUrl/ws/lists/$listId/').replace(
        queryParameters: token != null ? {'token': token} : null,
      );
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _emitState(RealtimeConnectionState.connected);
      channel.stream.listen(
        (message) {
          final event = ListRealtimeEvent.tryParse(message as String);
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
    StreamController<ListRealtimeEvent> controller,
    int attempt,
  ) {
    if (_disposed || _activeListId != listId || controller.isClosed) return;
    _emitState(RealtimeConnectionState.reconnecting);
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
    unawaited(_connectionState.close());
  }
}