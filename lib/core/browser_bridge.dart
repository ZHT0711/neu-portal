import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import 'portal_client.dart';

/// Each navigation invalidates pending results before another document can answer.
class BrowserBridge {
  BrowserBridge(this.controller);
  final WebViewController controller;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  int _sequence = 0;

  Future<void> install() => controller.addJavaScriptChannel(
    'NeuData',
    onMessageReceived: (message) {
      try {
        final envelope = jsonDecode(message.message) as Map;
        final completer = _pending.remove(envelope['token']);
        if (completer == null) return;
        if (envelope['error'] != null) {
          completer.completeError(PortalException('${envelope['error']}'));
        } else if (envelope['value'] is Map) {
          completer.complete(
            Map<String, dynamic>.from(envelope['value'] as Map),
          );
        } else {
          completer.completeError(PortalException('网页返回格式异常'));
        }
      } catch (_) {
        /* Ignore messages that do not belong to this bridge. */
      }
    },
  );

  Future<Map<String, dynamic>> run(
    String script,
    Map<String, Object?> arguments,
  ) async {
    final token = '${++_sequence}-${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[token] = completer;
    // Attach the error handler before JS execution, including navigation cancellation.
    final result = completer.future.timeout(const Duration(minutes: 3));
    unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    final declarations = arguments.entries
        .map((e) => 'const ${e.key} = ${jsonEncode(e.value)};')
        .join('\n');
    try {
      await controller.runJavaScript('''
        (async () => {
          const token = ${jsonEncode(token)};
          const requestController = new AbortController();
          const requests = window.__neuDataRequests ||= new Map();
          requests.set(token, requestController);
          const syncSignal = requestController.signal;
          try {
            const value = await (async () => { $declarations
              $script
            })();
            if (syncSignal.aborted) return;
            NeuData.postMessage(JSON.stringify({token, value}));
          } catch (e) {
            NeuData.postMessage(JSON.stringify({token, error: String(e.message || e)}));
          } finally { requests.delete(token); }
        })();
      ''');
      return await result;
    } finally {
      _pending.remove(token);
      unawaited(
        controller
            .runJavaScript(
              'window.__neuDataRequests?.get(${jsonEncode(token)})?.abort();',
            )
            .catchError((Object _) {}),
      );
    }
  }

  void cancel() {
    final pending = _pending.values.toList();
    _pending.clear();
    if (pending.isNotEmpty) {
      unawaited(
        controller
            .runJavaScript(
              'window.__neuDataRequests?.forEach(controller => controller.abort());',
            )
            .catchError((Object _) {}),
      );
    }
    for (final request in pending) {
      request.completeError(PortalException('页面已切换，请在当前页面重试同步'));
    }
  }
}
