import 'houseprintplus_platform_interface.dart';
import 'src/houseprint_status.dart';

export 'src/houseprint_status.dart';

class Houseprintplus {
  Stream<HouseprintStatus> get statusStream =>
      HouseprintplusPlatform.instance.statusStream;

  Future<String?> getPlatformVersion() {
    return HouseprintplusPlatform.instance.getPlatformVersion();
  }

  Future<void> startBluetoothDiscovery({String? namePrefix}) {
    return HouseprintplusPlatform.instance.startBluetoothDiscovery(
      namePrefix: namePrefix,
    );
  }

  Future<void> stopBluetoothDiscovery() {
    return HouseprintplusPlatform.instance.stopBluetoothDiscovery();
  }

  Future<void> connectBluetoothPrinter(String address) {
    return HouseprintplusPlatform.instance.connectBluetoothPrinter(address);
  }

  Future<void> disconnectBluetoothPrinter() {
    return HouseprintplusPlatform.instance.disconnectBluetoothPrinter();
  }

  Future<HouseprintStatus> getBluetoothState() {
    return HouseprintplusPlatform.instance.getBluetoothState();
  }

  Future<HouseprintStatus> getPrintState() {
    return HouseprintplusPlatform.instance.getPrintState();
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
    return HouseprintplusPlatform.instance.printQrLabel(
      qrContent: qrContent,
      title: title,
      subtitle: subtitle,
      labelWidthMm: labelWidthMm,
      labelHeightMm: labelHeightMm,
      titleFontSizeMm: titleFontSizeMm,
      subtitleFontSizeMm: subtitleFontSizeMm,
    );
  }

  Future<bool> cancelPrintJob() {
    return HouseprintplusPlatform.instance.cancelPrintJob();
  }
}
