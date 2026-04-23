import 'dart:developer';

import 'package:flutter/material.dart';
import 'dart:async';

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

  final Map<String, Map<String, dynamic>> foundDevices = {};

  List deviceList = [];

  late final StreamSubscription sub;

  bool coundPrint = false;

  void setUpPrint() async {
    sub = printer.statusStream.listen((status) {
      coundPrint = false;

      switch (status.state) {
        case 'connected':
          print("链接了设备");
          coundPrint = true;
          setState(() {

          });


          break;

        case 'scanning':
          foundDevices.clear();
          break;

        case 'deviceFound':
          final address = status.payload['deviceAddress'] as String?;
          if (address != null) {
            foundDevices[address] = Map<String, dynamic>.from(status.payload);
          }
          deviceList = foundDevices.values.toList();
          print('当前设备列表: ${foundDevices.values.toList()}');
          setState(() {

          });
          break;

        case 'scanFinished':
        case 'scanStopped':
          deviceList = foundDevices.values.toList();
          print('搜索结束, 共找到 ${deviceList.length} 个设备');
          setState(() {

          });
          break;

        case 'permissionDenied':
          break;
        case 'bluetoothDisabled':
          break;
        case 'gpsDisabled':
        case 'error':
          print('搜索失败: ${status.message}');
          break;
      }


      if (status.type == HouseprintStatusType.bluetooth) {


        switch (status.state) {
        // 插件初始化完成，蓝牙能力已经准备好。
          case 'idle':
            break;

        // 开始申请蓝牙扫描或连接所需的系统权限。
          case 'permissionRequesting':
            break;

        // 用户拒绝了权限申请，后续扫描/连接会失败。
          case 'permissionDenied':
            break;

        // 手机蓝牙未开启，需要用户手动打开。
          case 'bluetoothDisabled':

            break;

        // Android 12 以下扫描蓝牙时，定位服务也需要开启。
          case 'gpsDisabled':
            break;

        // 开始扫描前先清空旧列表，页面只显示本轮扫描结果。
          case 'scanning':
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

            break;

        // 用户主动停止扫描。
          case 'scanStopped':

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

            break;

        // 蓝牙相关错误统一在这里显示。
          case 'error':

            break;

        // 如果原生后续新增了新状态，这里先保底显示到界面日志里。
          default:
            break;
        }

        return;
      }

      if (status.type == HouseprintStatusType.print) {


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







      setState(() {

      });
    });

    await printer.startBluetoothDiscovery(namePrefix: 'B21');
  }

  @override
  void initState() {
    super.initState();
    initPlatformState();
    setUpPrint();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion =
          await printer.getPlatformVersion() ?? 'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

  }

  @override
  Widget build(BuildContext context) {
    List<Widget> list = [
      GestureDetector(
        onTap: () {
          printer.startBluetoothDiscovery();
        },
        child: Container(
          child: Text("搜索蓝牙"),
        ),
      ),
    ];

    for (int i = 0; i < deviceList.length; i++) {
      // deviceName
      Map data = deviceList[i];
      String deviceName = data["deviceName"];
      String deviceAddress = data["deviceAddress"];

      list.add(GestureDetector(
        onTap: () {
          printer.connectBluetoothPrinter(deviceAddress);
        },
        child: Container(
          margin: EdgeInsets.only(top: 30),
          child: Text(deviceName + " | " + deviceAddress),
        ),
      ));
    }

    list.add(GestureDetector(
      onTap: () {
        printer.printQrLabel(qrContent: "hello world", title: "123", subtitle: "456");
      },
      child: Container(
        margin: EdgeInsets.only(top: 30),
        child: Text("打印测试"),
      ),
    ));

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(
            children: list,
          ),
        ),
      ),
    );
  }
}
