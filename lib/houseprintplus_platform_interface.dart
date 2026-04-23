import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'houseprintplus_method_channel.dart';
import 'src/houseprint_status.dart';

abstract class HouseprintplusPlatform extends PlatformInterface {
  /// Constructs a HouseprintplusPlatform.
  HouseprintplusPlatform() : super(token: _token);

  static final Object _token = Object();

  static HouseprintplusPlatform _instance = MethodChannelHouseprintplus();

  /// The default instance of [HouseprintplusPlatform] to use.
  ///
  /// Defaults to [MethodChannelHouseprintplus].
  static HouseprintplusPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [HouseprintplusPlatform] when
  /// they register themselves.
  static set instance(HouseprintplusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<HouseprintStatus> get statusStream {
    throw UnimplementedError('statusStream has not been implemented.');
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<void> startBluetoothDiscovery({String? namePrefix}) {
    throw UnimplementedError(
        'startBluetoothDiscovery() has not been implemented.');
  }

  Future<void> stopBluetoothDiscovery() {
    throw UnimplementedError(
        'stopBluetoothDiscovery() has not been implemented.');
  }

  Future<void> connectBluetoothPrinter(String address) {
    throw UnimplementedError(
        'connectBluetoothPrinter() has not been implemented.');
  }

  Future<void> disconnectBluetoothPrinter() {
    throw UnimplementedError(
        'disconnectBluetoothPrinter() has not been implemented.');
  }

  Future<HouseprintStatus> getBluetoothState() {
    throw UnimplementedError('getBluetoothState() has not been implemented.');
  }

  Future<HouseprintStatus> getPrintState() {
    throw UnimplementedError('getPrintState() has not been implemented.');
  }

  Future<void> printQrLabel({
    required String qrContent,
    required String title,
    required String subtitle,
    double labelWidthMm = 50,
    double labelHeightMm = 30,
    double? titleFontSizeMm,
    double? subtitleFontSizeMm,
  }) {
    throw UnimplementedError('printQrLabel() has not been implemented.');
  }

  Future<void> printQrTitleCenteredLabel({
    required String qrContent,
    required String title,
    double labelWidthMm = 50,
    double labelHeightMm = 30,
    double? titleFontSizeMm,
  }) {
    throw UnimplementedError(
      'printQrTitleCenteredLabel() has not been implemented.',
    );
  }

  Future<bool> cancelPrintJob() {
    throw UnimplementedError('cancelPrintJob() has not been implemented.');
  }
}
