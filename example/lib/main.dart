import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:houseprintplus/houseprintplus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const Map<String, String> _bluetoothStateDescriptions =
  <String, String>{
    'idle': '蓝牙管理器已初始化，当前没有正在进行的蓝牙操作。',
    'permissionRequesting': '正在向系统申请蓝牙扫描或连接所需权限。',
    'permissionDenied': '用户拒绝了蓝牙相关权限，本轮操作无法继续。',
    'bluetoothDisabled': '系统蓝牙开关未打开，需要用户先手动开启。',
    'gpsDisabled': '低版本 Android 搜索蓝牙时需要同时打开定位服务。',
    'scanning': '蓝牙扫描中，等待系统回调搜索到的设备。',
    'deviceFound': '扫描到了一个符合条件的蓝牙打印机设备。',
    'scanFinished': '本轮蓝牙扫描自然结束。',
    'scanStopped': '本轮蓝牙扫描被主动停止。',
    'pairingRequested': '系统已经弹出蓝牙配对确认框。',
    'pairing': '目标设备正在进行蓝牙配对。',
    'paired': '蓝牙配对成功，可以继续走连接流程。',
    'connecting': '正在调用打印 SDK 建立蓝牙连接。',
    'connected': '蓝牙打印机已经连接成功，可以开始打印。',
    'powerChanged': '打印机电量状态发生了变化。',
    'coverStatusChanged': '打印机盖子状态发生了变化。',
    'paperStatusChanged': '打印机纸张状态发生了变化。',
    'rfidStatusChanged': '标签 RFID 状态发生了变化。',
    'ribbonRfidStatusChanged': '碳带 RFID 状态发生了变化。',
    'ribbonStatusChanged': '碳带状态发生了变化。',
    'firmwareError': '打印机固件上报了异常状态。',
    'disconnected': '蓝牙连接已经断开。',
    'error': '蓝牙流程中出现错误，具体原因看 message 和 payload。',
  };

  static const Map<String, String> _printStateDescriptions = <String, String>{
    'idle': '打印管理器已初始化，当前没有待执行任务。',
    'cancelRequested': '已经发起取消打印请求，等待设备侧结果。',
    'preparing': '正在准备打印参数和位图数据。',
    'generatingQr': '正在把二维码字符串生成二维码图片。',
    'renderingLayout': '正在把二维码、title、subtitle 组合成最终标签位图。',
    'starting': '正在启动 SDK 打印任务。',
    'sending': '正在向打印机发送位图数据。',
    'progress': '打印中，SDK 正在回调当前进度。',
    'completed': '打印任务已经完成。',
    'cancelled': '打印任务已经取消。',
    'error': '打印流程中出现错误，具体原因看 message 和 payload。',
  };

  final Houseprintplus printer = Houseprintplus();
  final Map<String, Map<String, dynamic>> foundDevices =
  <String, Map<String, dynamic>>{};
  final List<String> _eventLogs = <String>[];

  StreamSubscription<HouseprintStatus>? _statusSubscription;
  List<Map<String, dynamic>> deviceList = <Map<String, dynamic>>[];

  String _platformVersion = 'Unknown';
  String _bluetoothState = 'idle';
  String _bluetoothMessage = '等待蓝牙操作';
  String _printState = 'idle';
  String _printMessage = '等待打印操作';
  String? _connectedDeviceName;
  String? _connectedDeviceAddress;
  bool _isScanning = false;
  bool _canPrint = false;

  Map<String, dynamic> _bluetoothPayload = <String, dynamic>{};
  Map<String, dynamic> _printPayload = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    initPlatformState();
    setUpPrint();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  void _appendStatusLog(HouseprintStatus status) {
    final String payloadText = status.payload.isEmpty
        ? ''
        : ' | payload: ${_formatPayload(status.payload)}';
    _eventLogs.insert(
      0,
      '[${status.type}] ${status.state} | ${status.message}$payloadText',
    );

    // 示例页只保留最近 50 条日志，避免列表无限增长。
    if (_eventLogs.length > 50) {
      _eventLogs.removeRange(50, _eventLogs.length);
    }
  }

  String _formatPayload(Map<String, dynamic> payload) {
    if (payload.isEmpty) {
      return '{}';
    }
    return payload.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
  }

  Future<void> _loadInitialStates() async {
    try {
      final HouseprintStatus bluetoothStatus =
      await printer.getBluetoothState();
      final HouseprintStatus printStatus = await printer.getPrintState();

      if (!mounted) {
        return;
      }

      setState(() {
        _bluetoothState = bluetoothStatus.state;
        _bluetoothMessage = bluetoothStatus.message;
        _bluetoothPayload = Map<String, dynamic>.from(bluetoothStatus.payload);
        _printState = printStatus.state;
        _printMessage = printStatus.message;
        _printPayload = Map<String, dynamic>.from(printStatus.payload);
        _appendStatusLog(bluetoothStatus);
        _appendStatusLog(printStatus);
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _appendStatusLog(
          HouseprintStatus(
            type: HouseprintStatusType.unknown,
            state: 'error',
            message: error.message ?? '读取初始状态失败',
            payload: <String, dynamic>{},
          ),
        );
      });
    }
  }

  void setUpPrint() async {
    // 统一监听插件原生状态回调。蓝牙状态和打印状态都会从这里回到 Dart。
    _statusSubscription = printer.statusStream.listen((status) {
      if (!mounted) {
        return;
      }

      setState(() {
        _appendStatusLog(status);

        if (status.type == HouseprintStatusType.bluetooth) {
          _bluetoothState = status.state;
          _bluetoothMessage = status.message;
          _bluetoothPayload = Map<String, dynamic>.from(status.payload);

          switch (status.state) {
          // 插件初始化完成，蓝牙能力已经准备好。
            case 'idle':
              _isScanning = false;
              break;

          // 开始申请蓝牙扫描或连接所需的系统权限。
            case 'permissionRequesting':
              break;

          // 用户拒绝了权限申请，后续扫描/连接会失败。
            case 'permissionDenied':
              _isScanning = false;
              break;

          // 手机蓝牙未开启，需要用户手动打开。
            case 'bluetoothDisabled':
              _isScanning = false;
              _canPrint = false;
              break;

          // Android 12 以下扫描蓝牙时，定位服务也需要开启。
            case 'gpsDisabled':
              _isScanning = false;
              break;

          // 开始扫描前先清空旧列表，页面只显示本轮扫描结果。
            case 'scanning':
              _isScanning = true;
              foundDevices.clear();
              deviceList = <Map<String, dynamic>>[];
              break;

          // 每发现一台符合条件的蓝牙设备，就追加到页面列表中。
            case 'deviceFound':
              final String? address =
              status.payload['deviceAddress'] as String?;
              if (address != null) {
                foundDevices[address] =
                Map<String, dynamic>.from(status.payload);
              }
              deviceList = foundDevices.values.toList();
              break;

          // 扫描正常结束，保留当前扫描到的设备列表。
            case 'scanFinished':
              _isScanning = false;
              deviceList = foundDevices.values.toList();
              break;

          // 用户主动停止扫描。
            case 'scanStopped':
              _isScanning = false;
              deviceList = foundDevices.values.toList();
              break;

          // 系统准备弹出蓝牙配对确认框。
            case 'pairingRequested':
              break;

          // 打印机正在走蓝牙配对流程。
            case 'pairing':
              break;

          // 蓝牙配对成功，下一步通常会继续进入连接。
            case 'paired':
              break;

          // 已经拿到目标设备，正在请求 SDK 建立连接。
            case 'connecting':
              break;

          // 打印机连接成功，允许触发打印。
            case 'connected':
              _isScanning = false;
              _canPrint = true;
              _connectedDeviceName = status.payload['deviceName'] as String?;
              _connectedDeviceAddress =
              status.payload['deviceAddress'] as String?;
              final String? connectedAddress =
              status.payload['deviceAddress'] as String?;
              if (connectedAddress != null) {
                foundDevices[connectedAddress] =
                Map<String, dynamic>.from(status.payload);
                deviceList = foundDevices.values.toList();
              }
              break;

          // 当前连接的打印机电量有变化。
            case 'powerChanged':
              break;

          // 打印机盖子状态变化。
            case 'coverStatusChanged':
              break;

          // 打印机缺纸/有纸状态变化。
            case 'paperStatusChanged':
              break;

          // 标签 RFID 状态变化。
            case 'rfidStatusChanged':
              break;

          // 碳带 RFID 状态变化。
            case 'ribbonRfidStatusChanged':
              break;

          // 碳带状态变化。
            case 'ribbonStatusChanged':
              break;

          // 固件上报了异常状态。
            case 'firmwareError':
              break;

          // 连接断开后，清理页面上的可打印状态。
            case 'disconnected':
              _isScanning = false;
              _canPrint = false;
              _connectedDeviceName = null;
              _connectedDeviceAddress = null;
              break;

          // 蓝牙相关错误统一在这里显示。
            case 'error':
              _isScanning = false;
              break;

          // 如果原生后续新增了新状态，这里先保底显示到界面日志里。
            default:
              break;
          }

          return;
        }

        if (status.type == HouseprintStatusType.print) {
          _printState = status.state;
          _printMessage = status.message;
          _printPayload = Map<String, dynamic>.from(status.payload);

          switch (status.state) {
          // 打印管理器初始化完成，当前没有任务。
            case 'idle':
              break;

          // 已收到取消打印请求。
            case 'cancelRequested':
              break;

          // 开始准备打印参数和位图数据。
            case 'preparing':
              break;

          // 正在把传入的字符串编码成二维码。
            case 'generatingQr':
              break;

          // 正在把二维码、title、subtitle 绘制成最终位图。
            case 'renderingLayout':
              break;

          // 正在启动 SDK 打印任务。
            case 'starting':
              break;

          // 正在向打印机发送位图数据。
            case 'sending':
              break;

          // 打印过程中 SDK 上报的进度回调。
            case 'progress':
              break;

          // 当前打印任务已经完成。
            case 'completed':
              break;

          // 当前打印任务被取消。
            case 'cancelled':
              break;

          // 打印阶段的任何错误都会走到这里。
            case 'error':
              break;

          // 如果原生后续新增了新状态，这里先保底显示到界面日志里。
            default:
              break;
          }
        }
      });
    });

    // 先同步一次当前原生状态快照，避免页面初始化时全是默认文案。
    await _loadInitialStates();

    // 示例页启动后默认扫描一次 B21，方便直接看到完整状态流。
    try {
      await printer.startBluetoothDiscovery(namePrefix: 'B21');
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _appendStatusLog(
          HouseprintStatus(
            type: HouseprintStatusType.bluetooth,
            state: 'error',
            message: error.message ?? '启动蓝牙扫描失败',
            payload: <String, dynamic>{},
          ),
        );
      });
    }
  }

  Future<void> initPlatformState() async {
    String platformVersion;
    try {
      platformVersion =
          await printer.getPlatformVersion() ?? 'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  Widget _buildStateOverviewCard({
    required String title,
    required String currentState,
    required Map<String, String> descriptions,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final MapEntry<String, String> entry in descriptions.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${entry.key == currentState ? '>> ' : ''}'
                      '${entry.key}: ${entry.value}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        ElevatedButton(
          onPressed: () {
            printer.startBluetoothDiscovery(namePrefix: 'B21');
          },
          child: const Text('搜索蓝牙'),
        ),
        ElevatedButton(
          onPressed: _isScanning ? printer.stopBluetoothDiscovery : null,
          child: const Text('停止搜索'),
        ),
        ElevatedButton(
          onPressed: _connectedDeviceAddress == null
              ? null
              : printer.disconnectBluetoothPrinter,
          child: const Text('断开连接'),
        ),
        ElevatedButton(
          onPressed: _canPrint
              ? () {
            printer.printQrLabel(
              qrContent: 'hello world',
              title: '123',
              subtitle: '456',
            );
          }
              : null,
          child: const Text('打印测试'),
        ),
      ],
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String state,
    required String message,
    required Map<String, dynamic> payload,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('state: $state'),
            const SizedBox(height: 4),
            Text('message: $message'),
            const SizedBox(height: 4),
            Text('payload: ${_formatPayload(payload)}'),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList() {
    if (deviceList.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('当前没有扫描到设备'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '扫描到的设备',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final Map<String, dynamic> data in deviceList)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${data['deviceName'] ?? '未知设备'}'),
                subtitle: Text(
                  'MAC: ${data['deviceAddress'] ?? '-'} | bondState: ${data['bondState'] ?? '-'}',
                ),
                trailing: ElevatedButton(
                  onPressed: () {
                    final String? address = data['deviceAddress'] as String?;
                    if (address != null) {
                      printer.connectBluetoothPrinter(address);
                    }
                  },
                  child: const Text('连接'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '最近状态日志',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_eventLogs.isEmpty) const Text('还没有状态日志'),
            for (final String log in _eventLogs) Text(log),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text('Running on: $_platformVersion'),
              const SizedBox(height: 8),
              Text(
                '当前连接设备: ${_connectedDeviceName ?? '无'}'
                    '${_connectedDeviceAddress == null ? '' : ' | $_connectedDeviceAddress'}',
              ),
              const SizedBox(height: 16),
              _buildActionButtons(),
              const SizedBox(height: 16),
              _buildStatusCard(
                title: '蓝牙状态',
                state: _bluetoothState,
                message: _bluetoothMessage,
                payload: _bluetoothPayload,
              ),
              const SizedBox(height: 12),
              _buildStatusCard(
                title: '打印状态',
                state: _printState,
                message: _printMessage,
                payload: _printPayload,
              ),
              const SizedBox(height: 12),
              _buildStateOverviewCard(
                title: '蓝牙状态说明',
                currentState: _bluetoothState,
                descriptions: _bluetoothStateDescriptions,
              ),
              const SizedBox(height: 12),
              _buildStateOverviewCard(
                title: '打印状态说明',
                currentState: _printState,
                descriptions: _printStateDescriptions,
              ),
              const SizedBox(height: 12),
              _buildDeviceList(),
              const SizedBox(height: 12),
              _buildLogCard(),
            ],
          ),
        ),
      ),
    );
  }
}
