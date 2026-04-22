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
  String _platformVersion = 'Unknown';

  final Houseprintplus printer = Houseprintplus();

  final Map<String, Map<String, dynamic>> foundDevices = {};

  List deviceList = [];

  late final StreamSubscription sub;

  bool coundPrint = false;

  void setUpPrint() async {
    sub = printer.statusStream.listen((status) {
      coundPrint = false;
      if (status.type != HouseprintStatusType.bluetooth) {
        return;
      }



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

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
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
          margin: EdgeInsets.only(top: 20),
          child: Text(deviceName + " | " + deviceAddress),
        ),
      ));
    }

    list.add(GestureDetector(
      onTap: () {
        printer.printQrLabel(qrContent: "hello world", title: "123", subtitle: "456");
      },
      child: Container(
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
