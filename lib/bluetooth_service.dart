import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

/// BLE蓝牙通信服务类
/// 负责管理BLE蓝牙连接和发送控制指令到miniAuto小车(DXBT24-5.0模块)
class BluetoothService {
  fbp.BluetoothDevice? _device;
  fbp.BluetoothCharacteristic? _txCharacteristic;
  fbp.BluetoothCharacteristic? _rxCharacteristic;
  bool _isConnected = false;

  // 电压数据
  int _voltage = 0; // 单位: mV (毫伏)
  int _distance = 0; // 单位: mm (毫米)

  // 数据接收回调
  Function(int voltage, int distance)? onDataReceived;

  // DXBT24-5.0的服务和特征UUID
  // 这些是常见的BLE串口服务UUID,如果不匹配需要通过扫描获取实际UUID
  static const String SERVICE_UUID = "0000FFE0-0000-1000-8000-00805F9B34FB";
  static const String TX_CHAR_UUID = "0000FFE1-0000-1000-8000-00805F9B34FB";

  /// 获取连接状态
  bool get isConnected => _isConnected;

  /// 获取当前电压 (mV)
  int get voltage => _voltage;

  /// 获取当前超声波距离 (mm)
  int get distance => _distance;

  /// 扫描BLE设备
  /// 返回扫描结果流
  Stream<List<fbp.ScanResult>> scanDevices() {
    print('[BLE] 开始扫描BLE设备...');
    fbp.FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
    return fbp.FlutterBluePlus.scanResults;
  }

  /// 停止扫描
  void stopScan() {
    print('[BLE] 停止扫描');
    fbp.FlutterBluePlus.stopScan();
  }

  /// 连接到BLE设备
  /// [device] 要连接的BLE设备
  /// 返回连接是否成功
  Future<bool> connect(fbp.BluetoothDevice device) async {
    try {
      print('[BLE] 正在连接到设备: ${device.platformName}');
      print('[BLE] 设备ID: ${device.remoteId}');

      // 连接设备(15秒超时)
      await device.connect(timeout: const Duration(seconds: 15));
      _device = device;
      print('[BLE] 设备已连接,开始发现服务...');

      // 发现服务
      List<fbp.BluetoothService> services = await device.discoverServices();
      print('[BLE] 发现 ${services.length} 个服务');

      // 查找TX特征(用于发送数据)
      bool foundCharacteristic = false;
      for (var service in services) {
        print('[BLE] 服务UUID: ${service.uuid}');

        // 检查是否是目标服务(FFE0)
        if (service.uuid.toString().toUpperCase().contains("FFE0")) {
          print('[BLE] 找到目标服务: ${service.uuid}');

          for (var char in service.characteristics) {
            print('[BLE]   特征UUID: ${char.uuid}, 属性: ${char.properties}');

            // 检查是否是TX特征(FFE1)
            if (char.uuid.toString().toUpperCase().contains("FFE1")) {
              _txCharacteristic = char;
              _rxCharacteristic = char; // FFE1同时用于收发
              foundCharacteristic = true;
              print('[BLE] ✅ 找到TX/RX特征: ${char.uuid}');

              // 启用notify来接收数据
              try {
                await char.setNotifyValue(true);
                print('[BLE] 已启用数据接收通知');

                // 订阅数据接收
                char.value.listen((data) {
                  _handleReceivedData(data);
                });
              } catch (e) {
                print('[BLE] 启用通知失败: $e');
              }

              break;
            }
          }
        }

        if (foundCharacteristic) break;
      }

      if (_txCharacteristic == null) {
        print('[BLE] ❌ 未找到TX特征');
        print('[BLE] 可用的服务和特征:');
        for (var service in services) {
          print('[BLE]   服务: ${service.uuid}');
          for (var char in service.characteristics) {
            print('[BLE]     特征: ${char.uuid} (${char.properties})');
          }
        }
        await device.disconnect();
        return false;
      }

      _isConnected = true;
      print('[BLE] ✅ 连接成功');
      return true;
    } catch (e) {
      print('[BLE] ❌ 连接失败: $e');
      print('[BLE] 可能的原因:');
      print('  1. 设备未开机或不在范围内');
      print('  2. BLE信号干扰或距离过远');
      print('  3. 设备已被其他设备连接');
      print('  4. 设备不支持BLE或服务UUID不匹配');

      _isConnected = false;
      return false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    try {
      if (_device != null) {
        await _device!.disconnect();
        print('[BLE] 已断开连接');
      }
      _isConnected = false;
      _txCharacteristic = null;
      _rxCharacteristic = null;
      _device = null;
    } catch (e) {
      print('[BLE] 断开连接失败: $e');
    }
  }

  /// 处理接收到的数据
  /// 格式: $distance,voltage$
  void _handleReceivedData(List<int> data) {
    try {
      String dataString = String.fromCharCodes(data);
      print('[BLE] 收到数据: $dataString');

      // 解析格式: $distance,voltage$
      if (dataString.startsWith('\$') && dataString.endsWith('\$')) {
        String content = dataString.substring(1, dataString.length - 1);
        List<String> parts = content.split(',');

        if (parts.length == 2) {
          _distance = int.tryParse(parts[0]) ?? 0;
          _voltage = int.tryParse(parts[1]) ?? 0;

          print('[BLE] 解析成功 - 距离: ${_distance}mm, 电压: ${_voltage}mV');

          // 触发回调
          if (onDataReceived != null) {
            onDataReceived!(_voltage, _distance);
          }
        }
      }
    } catch (e) {
      print('[BLE] 解析数据失败: $e');
    }
  }

  /// 请求超声波距离和电压数据
  /// 发送命令: D|$
  Future<void> requestVoltageData() async {
    if (!_isConnected || _txCharacteristic == null) {
      print('[BLE] 未连接到设备');
      return;
    }

    try {
      String command = 'D|\$';
      List<int> data = command.codeUnits;

      await _txCharacteristic!.write(data, withoutResponse: true);
      print('[BLE] 请求电压数据: $command');
    } catch (e) {
      print('[BLE] 请求电压数据失败: $e');
    }
  }

  /// 发送运动控制指令 (出厂程序字符串协议)
  /// 格式: A|state|$
  /// 标准协议定义（符合Arduino端 app_control_common.ino）：
  /// state=0: 右移(90°)   state=1: 右前(45°)    state=2: 前进(0°)
  /// state=3: 左前(315°)  state=4: 左移(270°)   state=5: 左后(225°)
  /// state=6: 后退(180°)  state=7: 右后(135°)   state=8: 停止
  /// state=9: 顺时针旋转  state=10: 逆时针旋转  state=11: 停止旋转
  Future<void> _sendAppCommand(int state) async {
    if (!_isConnected || _txCharacteristic == null) {
      print('[BLE] 未连接到设备');
      return;
    }

    try {
      // 构建字符串命令: A|state|$
      String command = 'A|$state|\$';
      List<int> data = command.codeUnits; // 转换为ASCII字节数组

      await _txCharacteristic!.write(data, withoutResponse: true);
      print('[BLE] 发送运动指令: $command');
    } catch (e) {
      print('[BLE] 发送指令失败: $e');
    }
  }

  /// 设置速度 (0-100)
  /// 格式: C|speed|$
  Future<void> setSpeed(int speed) async {
    if (!_isConnected || _txCharacteristic == null) {
      print('[BLE] 未连接到设备');
      return;
    }

    try {
      speed = speed.clamp(0, 100);
      String command = 'C|$speed|\$';
      List<int> data = command.codeUnits;

      await _txCharacteristic!.write(data, withoutResponse: true);
      print('[BLE] 设置速度: $speed');
    } catch (e) {
      print('[BLE] 设置速度失败: $e');
    }
  }

  /// 设置RGB灯颜色
  /// 格式: B|r|g|b|$
  /// [r] 红色 (0-255)
  /// [g] 绿色 (0-255)
  /// [b] 蓝色 (0-255)
  Future<void> setRgbColor(int r, int g, int b) async {
    if (!_isConnected || _txCharacteristic == null) {
      print('[BLE] 未连接到设备');
      return;
    }

    try {
      r = r.clamp(0, 255);
      g = g.clamp(0, 255);
      b = b.clamp(0, 255);
      String command = 'B|$r|$g|$b|\$';
      List<int> data = command.codeUnits;

      await _txCharacteristic!.write(data, withoutResponse: true);
      print('[BLE] 设置RGB颜色: R=$r, G=$g, B=$b');
    } catch (e) {
      print('[BLE] 设置RGB颜色失败: $e');
    }
  }

  /// 发送手套控制指令 (二进制协议)
  /// 协议格式: 0x55 0x55 0x04 0x32 motor1 motor2
  /// [motor1] 电机1速度 (-100 到 100)
  /// [motor2] 电机2速度 (-100 到 100)
  Future<void> _sendGloveCommand(int motor1, int motor2) async {
    if (!_isConnected || _txCharacteristic == null) {
      print('[BLE] 未连接到设备');
      return;
    }

    try {
      // 限制速度范围在 -100 到 100
      motor1 = motor1.clamp(-100, 100);
      motor2 = motor2.clamp(-100, 100);

      // 将有符号整数转换为无符号字节 (保持二进制补码表示)
      int motor1Byte = motor1 < 0 ? 256 + motor1 : motor1;
      int motor2Byte = motor2 < 0 ? 256 + motor2 : motor2;

      // 构建数据包
      List<int> data = [
        0x55, // 帧头1
        0x55, // 帧头2
        0x04, // 数据长度
        0x32, // 功能号
        motor1Byte, // motor1 (有符号转无符号字节)
        motor2Byte, // motor2 (有符号转无符号字节)
      ];

      await _txCharacteristic!.write(data, withoutResponse: true);
      print('[BLE] 发送手套指令: motor1=$motor1($motor1Byte), motor2=$motor2($motor2Byte)');
    } catch (e) {
      print('[BLE] 发送指令失败: $e');
    }
  }

  /// 停止小车
  void stop() {
    _sendAppCommand(8); // APP协议: state=8 表示停止
    // _sendGloveCommand(0, 0); // 手套协议版本
  }

  /// 前进
  void forward() {
    _sendAppCommand(2); // APP协议: state=2 表示前进
    // _sendGloveCommand(100, 100); // 手套协议版本
  }

  /// 后退
  void backward() {
    _sendAppCommand(6); // APP协议: state=6 表示后退
    // _sendGloveCommand(-100, -100); // 手套协议版本
  }

  /// 左移 (标准协议: state=4, 270°)
  void turnLeft() {
    _sendAppCommand(4); // 协议定义: state=4 表示左移 (270°)
  }

  /// 右移 (标准协议: state=0, 90°)
  void turnRight() {
    _sendAppCommand(0); // 协议定义: state=0 表示右移 (90°)
  }

  // ==================== 高级控制: 8方向移动 ====================

  /// 右前移动 (45°, 标准协议: state=1)
  void moveRightForward() {
    _sendAppCommand(1); // 协议定义: state=1 表示右前 (45°)
  }

  /// 左前移动 (315°, 标准协议: state=3)
  void moveLeftForward() {
    _sendAppCommand(3); // 协议定义: state=3 表示左前 (315°)
  }

  /// 左后移动 (225°, 标准协议: state=5)
  void moveLeftBackward() {
    _sendAppCommand(5); // 协议定义: state=5 表示左后 (225°)
  }

  /// 右后移动 (135°, 标准协议: state=7)
  void moveRightBackward() {
    _sendAppCommand(7); // 协议定义: state=7 表示右后 (135°)
  }

  // ==================== 高级控制: 旋转 ====================

  /// 顺时针旋转
  void rotateClockwise() {
    _sendAppCommand(9); // APP协议: state=9 表示顺时针旋转
  }

  /// 逆时针旋转
  void rotateCounterClockwise() {
    _sendAppCommand(10); // APP协议: state=10 表示逆时针旋转
  }

  /// 停止旋转
  void stopRotate() {
    _sendAppCommand(11); // APP协议: state=11 表示停止旋转
  }

  // ==================== 电机测试 ====================

  /// 测试单个电机
  /// [motorId] 电机编号 (0-3)
  /// [speed] 速度 (-100到100, 正值正转, 负值反转)
  /// 格式: G|motorId|speed|$
  Future<void> testMotor(int motorId, int speed) async {
    if (!_isConnected || _txCharacteristic == null) {
      print('[BLE] 未连接到设备');
      return;
    }

    try {
      motorId = motorId.clamp(0, 3);
      speed = speed.clamp(-100, 100);
      String command = 'G|$motorId|$speed|\$';
      List<int> data = command.codeUnits;

      await _txCharacteristic!.write(data, withoutResponse: true);
      print('[BLE] 测试电机: 电机$motorId, 速度$speed');
    } catch (e) {
      print('[BLE] 测试电机失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    disconnect();
  }
}
