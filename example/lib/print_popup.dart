import 'package:flutter/material.dart';

import 'printManager.dart';

/// 打开打印弹窗。
Future<void> showPrintPopup(
  BuildContext context, {
  required String qrContent,
  required String title,
  required String subtitle,
  double? titleFontSizeMm,
  double? subtitleFontSizeMm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) {
      print("======================");
      print("titleFontSizeMm == " + titleFontSizeMm.toString());
      print("subtitleFontSizeMm == " + subtitleFontSizeMm.toString());

      return PrintPopup(
        qrContent: qrContent,
        title: title,
        subtitle: subtitle,
        titleFontSizeMm: titleFontSizeMm,
        subtitleFontSizeMm: subtitleFontSizeMm,
      );
    },
  );
}

/// 蓝牙连接和打印的弹窗页面。
///
/// 页面本身不直接处理原生状态，只监听 printManager 单例。
class PrintPopup extends StatefulWidget {
  const PrintPopup({
    super.key,
    required this.qrContent,
    required this.title,
    required this.subtitle,
    this.titleFontSizeMm,
    this.subtitleFontSizeMm,
  });

  final String qrContent;
  final String title;
  final String subtitle;
  final double? titleFontSizeMm;
  final double? subtitleFontSizeMm;

  @override
  State<PrintPopup> createState() => _PrintPopupState();
}

class _PrintPopupState extends State<PrintPopup> {
  final printManager _manager = printManager();

  @override
  void initState() {
    super.initState();
    _manager.setUp();
  }

  Widget _buildErrorCard() {
    if (_manager.latestErrorStatus == null) {
      return const SizedBox.shrink();
    }

    final error = _manager.latestErrorStatus!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '流程错误',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text('type: ${error.type}'),
          Text('message: ${error.message}'),
        ],
      ),
    );
  }

  Widget _buildConnectedCard() {
    final connectedDevice = _manager.connectedDevice;
    if (connectedDevice == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '当前已链接设备',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(connectedDevice['deviceName']?.toString() ?? '未知设备'),
          const SizedBox(height: 4),
          Text(connectedDevice['deviceAddress']?.toString() ?? '-'),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    if (_manager.deviceList.isEmpty) {
      if (_manager.isScanning) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        );
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('当前没有搜索到以 B1- 开头的蓝牙设备。'),
      );
    }

    return Column(
      children: _manager.deviceList.map((Map<String, dynamic> device) {
        final String address = device['deviceAddress']?.toString() ?? '';
        final bool isConnected = _manager.isConnectedDevice(address);
        final bool isConnecting = _manager.connectingDeviceAddress == address;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      device['deviceName']?.toString() ?? '未知设备',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(address.isEmpty ? '-' : address),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (isConnected)
                OutlinedButton(
                  onPressed: _manager.isPrinting
                      ? null
                      : () {
                          _manager.disconnectDevice();
                        },
                  child: const Text('断开链接'),
                )
              else
                ElevatedButton(
                  onPressed: _manager.hasConnectedDevice ||
                          _manager.isConnecting ||
                          _manager.isPrinting
                      ? null
                      : () {
                          _manager.connectDevice(address);
                        },
                  child: Text(isConnecting ? '链接中...' : '链接设备'),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionArea() {
    if (_manager.hasConnectedDevice) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _manager.isPrinting
              ? null
              : () {
                  _manager.printLabel(
                    qrContent: widget.qrContent,
                    title: widget.title,
                    subtitle: widget.subtitle,
                    titleFontSizeMm: widget.titleFontSizeMm,
                    subtitleFontSizeMm: widget.subtitleFontSizeMm,
                  );
                },
          child: Text(_manager.isPrinting ? '打印中...' : '打印按钮'),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _manager.isScanning || _manager.isConnecting
            ? null
            : () {
                _manager.searchBluetoothDevices();
              },
        child: Text(_manager.isScanning ? '搜索中...' : '搜索蓝牙'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _manager,
      builder: (BuildContext context, Widget? child) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            top: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '蓝牙打印',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text('蓝牙状态: ${_manager.bluetoothState}'),
                const SizedBox(height: 4),
                Text('打印状态: ${_manager.printState}'),
                const SizedBox(height: 12),
                _buildErrorCard(),
                _buildConnectedCard(),
                _buildDeviceList(),
                const SizedBox(height: 12),
                _buildActionArea(),
              ],
            ),
          ),
        );
      },
    );
  }
}
