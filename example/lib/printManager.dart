// ignore_for_file: camel_case_types, file_names

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:houseprintplus/houseprintplus.dart';

/// 单例打印管理器。
///
/// 这里把蓝牙扫描、连接、断开、打印以及错误状态都集中管理，
/// 弹窗页面只需要监听这个对象即可刷新界面。
class printManager extends ChangeNotifier {
  static final printManager manager = printManager._internal();

  // 保留用户当前已有的拼写，避免外部代码引用失效。
  static final printManager mananger = manager;

  factory printManager() {
    return manager;
  }

  printManager._internal();

  final Houseprintplus _printer = Houseprintplus();
  final Map<String, Map<String, dynamic>> _foundDevices =
      <String, Map<String, dynamic>>{};

  StreamSubscription<HouseprintStatus>? _statusSubscription;

  final List<Map<String, dynamic>> _deviceList = <Map<String, dynamic>>[];

  bool _didSetup = false;
  bool _isSettingUp = false;
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isPrinting = false;
  bool _canPrint = false;
  bool _canUse = false;

  String _bluetoothState = 'idle';
  String _bluetoothMessage = '等待蓝牙操作';
  String _printState = 'idle';
  String _printMessage = '等待打印操作';
  String? _connectingDeviceAddress;

  Map<String, dynamic>? _connectedDevice;
  HouseprintStatus? _latestBluetoothStatus;
  HouseprintStatus? _latestPrintStatus;
  HouseprintStatus? _latestErrorStatus;

  bool get canUse => _canUse;

  bool get isScanning => _isScanning;

  bool get isConnecting => _isConnecting;

  bool get isPrinting => _isPrinting;

  bool get canPrint => _canPrint;

  bool get hasConnectedDevice => _connectedDevice != null;

  String get bluetoothState => _bluetoothState;

  String get bluetoothMessage => _bluetoothMessage;

  String get printState => _printState;

  String get printMessage => _printMessage;

  String? get connectingDeviceAddress => _connectingDeviceAddress;

  Map<String, dynamic>? get connectedDevice => _connectedDevice == null
      ? null
      : Map<String, dynamic>.from(_connectedDevice!);

  List<Map<String, dynamic>> get deviceList =>
      List<Map<String, dynamic>>.unmodifiable(_deviceList);

  HouseprintStatus? get latestBluetoothStatus => _latestBluetoothStatus;

  HouseprintStatus? get latestPrintStatus => _latestPrintStatus;

  HouseprintStatus? get latestErrorStatus => _latestErrorStatus;

  String? get latestErrorMessage => _latestErrorStatus?.message;

  /// 初始化插件监听。
  ///
  /// 这个方法做成幂等的，页面多次进入弹窗也只会建立一份状态监听。
  Future<void> setUp() async {
    if (_didSetup || _isSettingUp) {
      return;
    }

    _isSettingUp = true;
    _canUse = Platform.isAndroid;

    if (!_canUse) {
      _latestErrorStatus = HouseprintStatus(
        type: HouseprintStatusType.unknown,
        state: 'error',
        message: '当前平台不支持蓝牙打印。',
        payload: <String, dynamic>{},
      );
      _isSettingUp = false;
      _didSetup = true;
      notifyListeners();
      return;
    }

    _statusSubscription = _printer.statusStream.listen(
      _applyStatus,
      onError: (Object error, StackTrace stackTrace) {
        _recordError(
          type: HouseprintStatusType.unknown,
          message: error.toString(),
          payload: <String, dynamic>{'stackTrace': stackTrace.toString()},
        );
      },
    );

    await _loadInitialStates();

    _didSetup = true;
    _isSettingUp = false;
    notifyListeners();
  }

  /// 主动清空上一次错误，避免旧错误一直停留在页面上。
  void clearError() {
    _latestErrorStatus = null;
    notifyListeners();
  }

  /// 开始搜索蓝牙设备。
  Future<void> searchBluetoothDevices() async {
    await setUp();

    if (!_canUse || hasConnectedDevice) {
      return;
    }

    clearError();
    _foundDevices.clear();
    _deviceList.clear();
    notifyListeners();

    try {
      await _printer.startBluetoothDiscovery();
    } on PlatformException catch (error) {
      _recordError(
        type: HouseprintStatusType.bluetooth,
        message: error.message ?? '启动蓝牙搜索失败。',
        payload: <String, dynamic>{},
      );
    }
  }

  /// 停止搜索蓝牙设备。
  Future<void> stopBluetoothDiscovery() async {
    if (!_canUse) {
      return;
    }

    try {
      await _printer.stopBluetoothDiscovery();
    } on PlatformException catch (error) {
      _recordError(
        type: HouseprintStatusType.bluetooth,
        message: error.message ?? '停止蓝牙搜索失败。',
        payload: <String, dynamic>{},
      );
    }
  }

  /// 连接指定蓝牙设备。
  Future<void> connectDevice(String address) async {
    await setUp();

    if (!_canUse) {
      return;
    }

    if (hasConnectedDevice &&
        _connectedDevice?['deviceAddress']?.toString() != address) {
      _recordError(
        type: HouseprintStatusType.bluetooth,
        message: '当前只能连接一个蓝牙设备，请先断开已连接设备。',
        payload: <String, dynamic>{
          'connectedDeviceAddress': _connectedDevice?['deviceAddress'],
        },
      );
      return;
    }

    clearError();
    _connectingDeviceAddress = address;
    _isConnecting = true;
    notifyListeners();

    try {
      await _printer.connectBluetoothPrinter(address);
    } on PlatformException catch (error) {
      _isConnecting = false;
      _connectingDeviceAddress = null;
      _recordError(
        type: HouseprintStatusType.bluetooth,
        message: error.message ?? '连接蓝牙设备失败。',
        payload: <String, dynamic>{'deviceAddress': address},
      );
    }
  }

  /// 断开当前设备。
  Future<void> disconnectDevice() async {
    if (!_canUse || !hasConnectedDevice) {
      return;
    }

    clearError();

    try {
      await _printer.disconnectBluetoothPrinter();
    } on PlatformException catch (error) {
      _recordError(
        type: HouseprintStatusType.bluetooth,
        message: error.message ?? '断开蓝牙设备失败。',
        payload: <String, dynamic>{
          'deviceAddress': _connectedDevice?['deviceAddress'],
        },
      );
    }
  }

  /// 发起二维码标签打印。
  Future<void> printLabel({
    required String qrContent,
    required String title,
    required String subtitle,
    double? titleFontSizeMm,
    double? subtitleFontSizeMm,
  }) async {
    await setUp();

    if (!_canUse) {
      return;
    }

    if (!hasConnectedDevice || !_canPrint) {
      _recordError(
        type: HouseprintStatusType.print,
        message: '请先连接蓝牙设备后再打印。',
        payload: <String, dynamic>{},
      );
      return;
    }

    clearError();
    _isPrinting = true;
    notifyListeners();

    try {
      await _printer.printQrLabel(
        qrContent: qrContent,
        title: title,
        subtitle: subtitle,
        titleFontSizeMm: titleFontSizeMm,
        subtitleFontSizeMm: subtitleFontSizeMm,
      );
    } on PlatformException catch (error) {
      _isPrinting = false;
      _recordError(
        type: HouseprintStatusType.print,
        message: error.message ?? '打印失败。',
        payload: <String, dynamic>{},
      );
    }
  }

  /// 判断设备是否是当前连接设备。
  bool isConnectedDevice(String? address) {
    if (address == null || _connectedDevice == null) {
      return false;
    }

    return _connectedDevice?['deviceAddress']?.toString() == address;
  }

  Future<void> _loadInitialStates() async {
    try {
      final HouseprintStatus bluetoothStatus =
          await _printer.getBluetoothState();
      final HouseprintStatus printStatus = await _printer.getPrintState();
      _applyStatus(bluetoothStatus, notify: false);
      _applyStatus(printStatus, notify: false);
    } on PlatformException catch (error) {
      _recordError(
        type: HouseprintStatusType.unknown,
        message: error.message ?? '读取初始状态失败。',
        payload: <String, dynamic>{},
        notify: false,
      );
    }
  }

  void _applyStatus(HouseprintStatus status, {bool notify = true}) {
    if (status.type == HouseprintStatusType.bluetooth) {
      _latestBluetoothStatus = status;
      _bluetoothState = status.state;
      _bluetoothMessage = status.message;
      _applyBluetoothState(status);
    } else if (status.type == HouseprintStatusType.print) {
      _latestPrintStatus = status;
      _printState = status.state;
      _printMessage = status.message;
      _applyPrintState(status);
    }

    if (notify) {
      notifyListeners();
    }
  }

  void _applyBluetoothState(HouseprintStatus status) {
    switch (status.state) {
      case 'idle':
        _isScanning = false;
        _isConnecting = false;
        break;
      case 'scanning':
        _isScanning = true;
        _isConnecting = false;
        _foundDevices.clear();
        _deviceList.clear();
        break;
      case 'deviceFound':
        final String deviceName =
            status.payload['deviceName']?.toString().trim() ?? '';

        // 只接收名称以 B1- 开头的蓝牙设备。
        if (!deviceName.startsWith('B1-')) {
          return;
        }

        _upsertDevice(status.payload);
        break;
      case 'scanFinished':
      case 'scanStopped':
      case 'permissionDenied':
      case 'bluetoothDisabled':
      case 'gpsDisabled':
        _isScanning = false;
        break;
      case 'pairingRequested':
      case 'pairing':
      case 'paired':
      case 'connecting':
        _isConnecting = true;
        _connectingDeviceAddress =
            status.payload['deviceAddress']?.toString() ??
                _connectingDeviceAddress;
        _upsertDevice(status.payload);
        break;
      case 'connected':
        _isScanning = false;
        _isConnecting = false;
        _canPrint = true;
        _connectingDeviceAddress = null;
        _connectedDevice = Map<String, dynamic>.from(status.payload);
        _upsertDevice(status.payload, forceConnected: true);
        _syncConnectedFlags();
        _latestErrorStatus = null;
        break;
      case 'disconnected':
        _isScanning = false;
        _isConnecting = false;
        _canPrint = false;
        _connectingDeviceAddress = null;
        _connectedDevice = null;
        _syncConnectedFlags();
        break;
      case 'error':
        _isScanning = false;
        _isConnecting = false;
        _connectingDeviceAddress = null;
        _recordError(
          type: HouseprintStatusType.bluetooth,
          message: status.message,
          payload: status.payload,
          notify: false,
        );
        break;
      default:
        break;
    }
  }

  void _applyPrintState(HouseprintStatus status) {
    switch (status.state) {
      case 'idle':
      case 'completed':
      case 'cancelled':
        _isPrinting = false;
        if (status.state == 'completed') {
          _latestErrorStatus = null;
        }
        break;
      case 'preparing':
      case 'generatingQr':
      case 'renderingLayout':
      case 'starting':
      case 'sending':
      case 'progress':
      case 'cancelRequested':
        _isPrinting = true;
        break;
      case 'error':
        _isPrinting = false;
        _recordError(
          type: HouseprintStatusType.print,
          message: status.message,
          payload: status.payload,
          notify: false,
        );
        break;
      default:
        break;
    }
  }

  void _upsertDevice(
    Map<String, dynamic> payload, {
    bool forceConnected = false,
  }) {
    final String? address = payload['deviceAddress']?.toString();
    if (address == null || address.isEmpty) {
      return;
    }

    final Map<String, dynamic> merged = <String, dynamic>{
      ...?_foundDevices[address],
      ...payload,
      'connected': forceConnected || isConnectedDevice(address),
    };

    _foundDevices[address] = merged;
    _refreshDeviceList();
  }

  void _refreshDeviceList() {
    _deviceList
      ..clear()
      ..addAll(
        _foundDevices.values.map<Map<String, dynamic>>(
          (Map<String, dynamic> value) => Map<String, dynamic>.from(value),
        ),
      );

    _deviceList.sort((Map<String, dynamic> left, Map<String, dynamic> right) {
      final bool leftConnected = left['connected'] == true;
      final bool rightConnected = right['connected'] == true;
      if (leftConnected != rightConnected) {
        return leftConnected ? -1 : 1;
      }

      final String leftName = left['deviceName']?.toString() ?? '';
      final String rightName = right['deviceName']?.toString() ?? '';
      return leftName.compareTo(rightName);
    });
  }

  void _syncConnectedFlags() {
    final String? connectedAddress =
        _connectedDevice?['deviceAddress']?.toString();

    for (final MapEntry<String, Map<String, dynamic>> entry
        in _foundDevices.entries) {
      entry.value['connected'] = entry.key == connectedAddress;
    }

    _refreshDeviceList();
  }

  void _recordError({
    required String type,
    required String message,
    required Map<String, dynamic> payload,
    bool notify = true,
  }) {
    _latestErrorStatus = HouseprintStatus(
      type: type,
      state: 'error',
      message: message,
      payload: Map<String, dynamic>.from(payload),
    );

    if (notify) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }
}
