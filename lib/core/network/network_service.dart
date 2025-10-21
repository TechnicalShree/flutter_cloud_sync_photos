import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const String _networkStateChannel = 'flutter_cloud_sync_photos/networkState';

class NetworkConditions {
  const NetworkConditions({
    required this.isOnline,
    required this.hasNetwork,
    required this.isWifi,
    required this.isMobile,
    this.isRoaming,
  });

  final bool isOnline;
  final bool hasNetwork;
  final bool isWifi;
  final bool isMobile;
  final bool? isRoaming;

  bool get isRoamingConnection => (isRoaming ?? false) && isMobile;
}

class NetworkService {
  NetworkService({Connectivity? connectivity, MethodChannel? methodChannel})
    : _connectivity = connectivity ?? Connectivity(),
      _methodChannel = kIsWeb
          ? null
          : (methodChannel ?? const MethodChannel(_networkStateChannel));

  final Connectivity _connectivity;
  final MethodChannel? _methodChannel;

  Future<bool> isOnline() async {
    final conditions = await currentConditions();
    return conditions.isOnline;
  }

  Future<NetworkConditions> currentConditions() async {
    final results = await _connectivity.checkConnectivity();
    return _buildConditions(results);
  }

  Stream<NetworkConditions> get onConditionsChanged {
    return _connectivity.onConnectivityChanged.asyncMap(_buildConditions);
  }

  Future<NetworkConditions> _buildConditions(
    List<ConnectivityResult> results,
  ) async {
    final hasNetwork = results.any(
      (result) => result != ConnectivityResult.none,
    );
    final isWifi = results.contains(ConnectivityResult.wifi);
    final isMobile = results.contains(ConnectivityResult.mobile);

    bool isOnline = false;
    if (hasNetwork) {
      isOnline = await _verifyInternet();
    }

    bool? roaming;
    if (isMobile) {
      roaming = await _queryRoaming();
    }

    return NetworkConditions(
      isOnline: hasNetwork ? isOnline : false,
      hasNetwork: hasNetwork,
      isWifi: isWifi,
      isMobile: isMobile,
      isRoaming: roaming,
    );
  }

  Future<bool> _verifyInternet() async {
    if (kIsWeb) {
      return true;
    }

    try {
      final lookup = await InternetAddress.lookup('example.com');
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  Future<bool?> _queryRoaming() async {
    final channel = _methodChannel;
    if (channel == null) {
      return false;
    }

    try {
      return await channel.invokeMethod<bool>('isRoaming');
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
