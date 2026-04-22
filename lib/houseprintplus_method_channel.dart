import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'houseprintplus_platform_interface.dart';
import 'src/houseprint_status.dart';

/// An implementation of [HouseprintplusPlatform] that uses method channels.
class MethodChannelHouseprintplus extends HouseprintplusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('houseprintplus');

  /// The event channel used to receive Bluetooth and print state changes.
  @visibleForTesting
  final eventChannel = const EventChannel('houseprintplus/status');

  Stream<HouseprintStatus>? _statusStream;

  @override
  Stream<HouseprintStatus> get statusStream {
    return _statusStream ??= eventChannel
        .receiveBroadcastStream()
        .map<HouseprintStatus>((dynamic event) {
      if (event is Map) {
        return HouseprintStatus.fromDynamic(event);
      }
      return HouseprintStatus(
        type: HouseprintStatusType.unknown,
        state: 'unknown',
        message: '',
        payload: <String, dynamic>{},
      );
    }).asBroadcastStream();
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<void> startBluetoothDiscovery({String? namePrefix}) {
    return methodChannel.invokeMethod<void>(
      'startBluetoothDiscovery',
      <String, dynamic>{'namePrefix': namePrefix},
    );
  }

  @override
  Future<void> stopBluetoothDiscovery() {
    return methodChannel.invokeMethod<void>('stopBluetoothDiscovery');
  }

  @override
  Future<void> connectBluetoothPrinter(String address) {
    return methodChannel.invokeMethod<void>(
      'connectBluetoothPrinter',
      <String, dynamic>{'address': address},
    );
  }

  @override
  Future<void> disconnectBluetoothPrinter() {
    return methodChannel.invokeMethod<void>('disconnectBluetoothPrinter');
  }

  @override
  Future<HouseprintStatus> getBluetoothState() async {
    final dynamic state = await methodChannel.invokeMethod<dynamic>(
      'getBluetoothState',
    );
    return HouseprintStatus.fromDynamic(state);
  }

  @override
  Future<HouseprintStatus> getPrintState() async {
    final dynamic state = await methodChannel.invokeMethod<dynamic>(
      'getPrintState',
    );
    return HouseprintStatus.fromDynamic(state);
  }

  @override
  Future<void> printQrLabel({
    required String qrContent,
    required String title,
    required String subtitle,
    double labelWidthMm = 50,
    double labelHeightMm = 30,
  }) {
    return methodChannel.invokeMethod<void>(
      'printQrLabel',
      <String, dynamic>{
        'qrContent': qrContent,
        'title': title,
        'subtitle': subtitle,
        'labelWidthMm': labelWidthMm,
        'labelHeightMm': labelHeightMm,
      },
    );
  }

  @override
  Future<bool> cancelPrintJob() async {
    return await methodChannel.invokeMethod<bool>('cancelPrintJob') ?? false;
  }
}
