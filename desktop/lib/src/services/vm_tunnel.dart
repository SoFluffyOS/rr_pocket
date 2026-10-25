import 'dart:async';
import 'dart:io';

import 'package:rr_pocket/src/services/pinned_tls.dart';

/// The phone's VM relay speaks TLS, which Flutter and DDS don't expect of a
/// VM service. This listens on this computer only, and carries each
/// connection to the relay inside TLS pinned to the phone's certificate.
/// The VM service's auth code still guards what comes through.
class VmTunnel {
  VmTunnel._(this._server, this._host, this._port, this._trusts) {
    _server.listen((local) => unawaited(_carry(local)));
  }

  static Future<VmTunnel> start({
    required String host,
    required int port,
    required bool Function(X509Certificate certificate) trusts,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return VmTunnel._(server, host, port, trusts);
  }

  final ServerSocket _server;
  final String _host;
  final int _port;
  final bool Function(X509Certificate certificate) _trusts;
  final _open = <Socket>{};

  /// Where Flutter connects, on 127.0.0.1.
  int get port => _server.port;

  Future<void> close() async {
    await _server.close();
    for (final socket in _open.toList()) {
      socket.destroy();
    }
  }

  Future<void> _carry(Socket local) async {
    // A write to a socket the other side reset fails there; unhandled, it
    // would end `pocket run`, and with it the session.
    local.done.ignore();
    _open.add(local);
    final SecureSocket remote;
    try {
      remote = await SecureSocket.connect(
        _host,
        _port,
        context: pinnedContext(),
        onBadCertificate: _trusts,
        timeout: const Duration(seconds: 10),
      );
    } catch (_) {
      _open.remove(local);
      local.destroy();
      return;
    }
    remote.done.ignore();
    _open.add(remote);
    void end() {
      _open
        ..remove(local)
        ..remove(remote);
      local.destroy();
      remote.destroy();
    }

    local.listen(remote.add, onDone: end, onError: (Object _) => end());
    remote.listen(local.add, onDone: end, onError: (Object _) => end());
  }
}
