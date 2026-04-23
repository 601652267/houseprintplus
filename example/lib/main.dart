import 'package:flutter/material.dart';

import 'print_popup.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Houseprint Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const PrintDemoPage(),
    );
  }
}

/// 示例页只负责准备打印内容并打开弹窗。
class PrintDemoPage extends StatefulWidget {
  const PrintDemoPage({super.key});

  @override
  State<PrintDemoPage> createState() => _PrintDemoPageState();
}

class _PrintDemoPageState extends State<PrintDemoPage> {
  late final TextEditingController _qrController;
  late final TextEditingController _titleController;
  late final TextEditingController _subtitleController;
  late final TextEditingController _titleFontSizeController;
  late final TextEditingController _subtitleFontSizeController;

  @override
  void initState() {
    super.initState();
    _qrController = TextEditingController(
      text: 'https://houseprintplus.example/label/10001',
    );
    _titleController = TextEditingController(text: '示例标题');
    _subtitleController = TextEditingController(
      text: '这是一段用于测试自动换行能力的示例副标题。',
    );
    _titleFontSizeController = TextEditingController(text: '5.0');
    _subtitleFontSizeController = TextEditingController(text: '3.6');
  }

  @override
  void dispose() {
    _qrController.dispose();
    _titleController.dispose();
    _subtitleController.dispose();
    _titleFontSizeController.dispose();
    _subtitleFontSizeController.dispose();
    super.dispose();
  }

  double? _parseFontSize(String rawValue) {
    final String trimmedValue = rawValue.trim();
    if (trimmedValue.isEmpty) {
      return null;
    }
    return double.tryParse(trimmedValue);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Houseprint 示例')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text(
              '填写打印内容后，点击下面按钮打开蓝牙打印弹窗。',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _qrController,
              decoration: const InputDecoration(
                labelText: '二维码字符串',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subtitleController,
              decoration: const InputDecoration(
                labelText: 'Subtitle',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleFontSizeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Title 字号(mm)',
                helperText: '例如 5.0，数值越大字体越大',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subtitleFontSizeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Subtitle 字号(mm)',
                helperText: '例如 3.6，数值越大字体越大',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  showPrintPopup(
                    context,
                    qrContent: _qrController.text.trim(),
                    title: _titleController.text.trim(),
                    subtitle: _subtitleController.text.trim(),
                    titleFontSizeMm: _parseFontSize(
                      _titleFontSizeController.text,
                    ),
                    subtitleFontSizeMm: _parseFontSize(
                      _subtitleFontSizeController.text,
                    ),
                  );
                },
                child: const Text('打开打印弹窗'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/*
*
cd /Users/zhuhaiming/Desktop/ph-app/trunk/houseprintplus
git status
git add .
git commit -m "feat: adjust print layout"
git push origin main
*
*
*
*
* */
