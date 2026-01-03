import 'package:flutter/material.dart';
import 'bluetooth_service.dart';
import 'motor_test_page.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  final BluetoothService bluetoothService;
  final bool isAdvancedMode;
  final Function(bool) onModeChanged;

  const SettingsPage({
    super.key,
    required this.bluetoothService,
    required this.isAdvancedMode,
    required this.onModeChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _isAdvancedMode;

  @override
  void initState() {
    super.initState();
    // 初始化本地状态副本
    _isAdvancedMode = widget.isAdvancedMode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          // 电机检测栏目
          ListTile(
            leading: const Icon(Icons.settings_input_component, color: Colors.blue),
            title: const Text('电机检测'),
            subtitle: const Text('检测四个电机的运行状态'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // 跳转到电机检测页面
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MotorTestPage(
                    bluetoothService: widget.bluetoothService,
                  ),
                ),
              );
            },
          ),
          const Divider(),

          // 控制模式栏目
          ListTile(
            leading: Icon(
              _isAdvancedMode ? Icons.gamepad : Icons.control_camera,
              color: Colors.orange,
            ),
            title: const Text('控制模式'),
            subtitle: Text(_isAdvancedMode ? '高级控制模式' : '普通控制模式'),
            trailing: Switch(
              value: _isAdvancedMode,
              onChanged: (value) {
                setState(() {
                  _isAdvancedMode = value;
                });
                widget.onModeChanged(value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(value ? '已切换到高级控制模式' : '已切换到普通控制模式'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
