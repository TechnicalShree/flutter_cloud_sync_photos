import 'dart:async';

import 'package:battery_plus/battery_plus.dart';

class PowerStatus {
  const PowerStatus({
    required this.level,
    required this.state,
  });

  final int? level;
  final BatteryState state;

  bool get isCharging =>
      state == BatteryState.charging || state == BatteryState.full;
}

class PowerService {
  PowerService({Battery? battery}) : _battery = battery ?? Battery();

  final Battery _battery;

  Future<PowerStatus> currentStatus() async {
    final level = await _readBatteryLevel();
    final state = await _readBatteryState();
    return PowerStatus(level: level, state: state);
  }

  Stream<PowerStatus> get onStatusChanged {
    return _battery.onBatteryStateChanged.asyncMap((state) async {
      final level = await _readBatteryLevel();
      return PowerStatus(level: level, state: state);
    });
  }

  Future<int?> _readBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      return level;
    } catch (_) {
      return null;
    }
  }

  Future<BatteryState> _readBatteryState() async {
    try {
      return await _battery.batteryState;
    } catch (_) {
      return BatteryState.unknown;
    }
  }
}
