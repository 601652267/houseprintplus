import 'package:flutter_test/flutter_test.dart';
import 'package:houseprintplus/houseprintplus.dart';
import 'package:houseprintplus/houseprintplus_platform_interface.dart';
import 'package:houseprintplus/houseprintplus_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockHouseprintplusPlatform
    with MockPlatformInterfaceMixin
    implements HouseprintplusPlatform {
  @override
  // Keeping this non-const avoids reintroducing the compiler crash workaround we applied.
  // ignore: prefer_const_constructors
  Stream<HouseprintStatus> get statusStream => Stream<HouseprintStatus>.empty();

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<void> startBluetoothDiscovery({String? namePrefix}) async {}

  @override
  Future<void> stopBluetoothDiscovery() async {}

  @override
  Future<void> connectBluetoothPrinter(String address) async {}

  @override
  Future<void> disconnectBluetoothPrinter() async {}

  @override
  Future<HouseprintStatus> getBluetoothState() async {
    return HouseprintStatus(
      type: HouseprintStatusType.bluetooth,
      state: 'idle',
      message: '',
      payload: <String, dynamic>{},
    );
  }

  @override
  Future<HouseprintStatus> getPrintState() async {
    return HouseprintStatus(
      type: HouseprintStatusType.print,
      state: 'idle',
      message: '',
      payload: <String, dynamic>{},
    );
  }

  @override
  Future<void> printQrLabel({
    required String qrContent,
    required String title,
    required String subtitle,
    double labelWidthMm = 50,
    double labelHeightMm = 30,
    double? titleFontSizeMm,
    double? subtitleFontSizeMm,
  }) async {}

  @override
  Future<bool> cancelPrintJob() async => false;
}

void main() {
  final HouseprintplusPlatform initialPlatform =
      HouseprintplusPlatform.instance;

  test('$MethodChannelHouseprintplus is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelHouseprintplus>());
  });

  test('getPlatformVersion', () async {
    Houseprintplus houseprintplusPlugin = Houseprintplus();
    MockHouseprintplusPlatform fakePlatform = MockHouseprintplusPlatform();
    HouseprintplusPlatform.instance = fakePlatform;

    expect(await houseprintplusPlugin.getPlatformVersion(), '42');
  });
}
