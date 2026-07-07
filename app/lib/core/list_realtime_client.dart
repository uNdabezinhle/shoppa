/// Real-time list collaboration (SRS FR-3.2, API Specification §9:
/// ws /lists/{id}). Server -> client only: item.added, item.updated,
/// item.checked, item.removed, collaborator.joined, collaborator.removed.
/// The client's job on any of these is simply "refetch the list" (see
/// ListScreen) -- there's no incremental patching, which keeps this in
/// sync with whatever the REST detail response says is true.
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'token_store.dart';

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

  /// Returns null (rather than throwing) for anything that isn't a
  /// well-formed event frame, so one malformed message can't take down
  /// the whole socket listener.
  static ListRealtimeEvent? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded['event'] is String) {
        return ListRealtimeEvent.fromJson(decoded);
      }
    } catch (_) {
      // ignored -- malformed frame
    }
    return null;
  }
}

class ListRealtimeClient {
  ListRealtimeClient({required this.wsBaseUrl, required this.tokenStore});

  /// e.g. ws://localhost:8000 or wss://api.shoppa.app (no /v1 suffix --
  /// the real-time channels live at the ASGI root, not under the
  /// versioned REST path; see shoppa_api/asgi.py + apps/lists/routing.py).
  final String wsBaseUrl;
  final TokenStore tokenStore;

  WebSocketChannel? _channel;
  StreamController<ListRealtimeEvent>? _controller;

  /// Connects to ws /lists/{listId}/ and returns a broadcast stream of
  /// parsed events. Connection failures are swallowed -- real-time is an
  /// enhancement on top of the REST CRUD (pull-to-refresh still works),
  /// not a dependency of it.
  Stream<ListRealtimeEvent> connect(String listId) {
    unawaited(_teardown());
    final controller = StreamController<ListRealtimeEvent>.broadcast();
    _controller = controller;
    unawaited(_connectAsync(listId, controller));
    return controller.stream;
  }

  Future<void> _connectAsync(
    String listId,
    StreamController<ListRealtimeEvent> controller,
  ) async {
    try {
      final token = await tokenStore.accessToken;
      final uri = Uri.parse('$wsBaseUrl/ws/lists/$listId/').replace(
        queryParameters: token != null ? {'token': token} : null,
      );
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      channel.stream.listen(
        (message) {
          final event = ListRealtimeEvent.tryParse(message as String);
          if (event != null && !controller.isClosed) controller.add(event);
        },
        onError: (_) {},
        onDone: () {},
        cancelOnError: false,
      );
    } catch (_) {
      // best-effort connection; caller keeps working off REST polling
    }
  }

  Future<void> _teardown() async {
    await _channel?.sink.close();
    _channel = null;
    await _controller?.close();
    _controller = null;
  }

  void dispose() {
    unawaited(_teardown());
  }
}
