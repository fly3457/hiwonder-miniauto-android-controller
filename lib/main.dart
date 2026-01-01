import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bluetooth_service.dart';
import 'motor_test_page.dart';
import 'package:location/location.dart' as loc;

void main() {
  runApp(const MiniAutoControllerApp());
}

class MiniAutoControllerApp extends StatelessWidget {
  const MiniAutoControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MiniAuto控制器',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BluetoothService _bluetoothService = BluetoothService();
  List<fbp.BluetoothDevice> _devices = [];
  fbp.BluetoothDevice? _connectedDevice;
  bool _isScanning = false;

  // 速度和RGB控制状态
  double _speed = 20.0; // 默认速度20%
  double _red = 255.0;
  double _green = 255.0;
  double _blue = 255.0;

  // 控制模式: false=简易模式, true=高级模式
  bool _isAdvancedMode = false;

  // 电压信息
  int _voltage = 0; // 单位: mV
  int _distance = 0; // 单位: mm

  // 定时器用于定期请求电压数据
  bool _voltageRequestActive = false;

  // 前进按钮状态（用于距离保护）
  bool _isForwardPressed = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _tryAutoConnect(); // 尝试自动连接上次的设备

    // 设置数据接收回调
    _bluetoothService.onDataReceived = (voltage, distance) {
      setState(() {
        _voltage = voltage;
        _distance = distance;
      });

      // 距离保护：如果正在前进且距离小于100mm (10cm)，自动停止
      if (_isForwardPressed && distance > 0 && distance < 100) {
        print('[距离保护] 距离过近(${distance}mm)，自动停止');
        _bluetoothService.stop();
        _isForwardPressed = false;
      }
    };
  }

  @override
  void dispose() {
    _bluetoothService.dispose();
    _voltageRequestActive = false;
    super.dispose();
  }

  /// 请求蓝牙权限
  Future<void> _requestPermissions() async {
    try {
      print('[权限] 开始请求蓝牙权限...');

      // Android 12+ (API 31+) 需要新的蓝牙权限
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location, // BLE扫描需要位置权限
      ].request();

      print('[权限] 权限请求结果:');
      statuses.forEach((permission, status) {
        print('  - $permission: $status');
      });

      // 检查关键权限是否被授予
      bool bluetoothGranted = (statuses[Permission.bluetoothScan]?.isGranted ?? false) &&
                               (statuses[Permission.bluetoothConnect]?.isGranted ?? false);
      bool locationGranted = statuses[Permission.location]?.isGranted ?? false;

      if (!bluetoothGranted) {
        print('[权限] ⚠️ 蓝牙权限未授予');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('需要蓝牙权限才能扫描和连接设备'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else if (!locationGranted) {
        print('[权限] ⚠️ 位置权限未授予(BLE扫描需要此权限)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('需要位置权限才能扫描BLE设备'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        print('[权限] ✅ 所有权限已授予');
      }
    } catch (e) {
      print('[权限] ❌ 请求权限失败: $e');
    }
  }

  /// 扫描BLE设备
  Future<void> _scanDevices() async {
    print('[扫描] 开始扫描BLE设备...');

    // 检查位置服务是否开启
    loc.Location location = loc.Location();
    bool serviceEnabled = await location.serviceEnabled();

    if (!serviceEnabled) {
      print('[扫描] ❌ 位置服务未开启');
      if (mounted) {
        _showLocationServiceDialog();
      }
      return;
    }

    setState(() {
      _isScanning = true;
      _devices.clear();
    });

    try {
      // 检查是否支持BLE
      if (await fbp.FlutterBluePlus.isSupported == false) {
        print('[扫描] ❌ 设备不支持BLE');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('您的设备不支持BLE蓝牙')),
          );
        }
        setState(() {
          _isScanning = false;
        });
        return;
      }

      // 监听扫描结果
      _bluetoothService.scanDevices().listen((results) {
        print('[扫描] 收到扫描结果,共 ${results.length} 个设备');

        setState(() {
          _devices = results.map((r) => r.device).toList();
        });

        // 打印每个发现的设备
        for (var result in results) {
          String deviceName = result.device.platformName.isNotEmpty
              ? result.device.platformName
              : '未知设备';
          print('[扫描] 发现设备: $deviceName (${result.device.remoteId}), 信号: ${result.rssi} dBm');
        }
      });

      // 12秒后停止扫描
      Future.delayed(const Duration(seconds: 12), () {
        if (_isScanning) {
          print('[扫描] 扫描超时,停止扫描');
          _bluetoothService.stopScan();
          setState(() {
            _isScanning = false;
          });

          if (_devices.isEmpty && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('未找到BLE设备\n请确保小车已开机并在附近'),
                duration: Duration(seconds: 4),
              ),
            );
          } else {
            print('[扫描] 扫描完成,共找到 ${_devices.length} 个设备');
          }
        }
      });

    } catch (e) {
      print('[扫描] ❌ 扫描设备失败: $e');

      // 友好的错误提示
      String errorMessage = '扫描失败';
      if (e.toString().contains('Location services')) {
        errorMessage = '需要开启位置服务(GPS)才能扫描蓝牙设备';
      } else if (e.toString().contains('Bluetooth')) {
        errorMessage = '请检查蓝牙是否已开启';
      } else if (e.toString().contains('Permission')) {
        errorMessage = '缺少蓝牙权限,请在设置中授予权限';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '重试',
              onPressed: () => _scanDevices(),
            ),
          ),
        );
      }
      setState(() {
        _isScanning = false;
      });
    }
  }

  /// 连接到设备
  Future<void> _connectToDevice(fbp.BluetoothDevice device) async {
    String deviceName = device.platformName.isNotEmpty ? device.platformName : device.remoteId.toString();
    print('[连接] 尝试连接到设备: $deviceName');

    bool success = await _bluetoothService.connect(device);
    if (success) {
      print('[连接] ✅ 连接成功');
      setState(() {
        _connectedDevice = device;
      });

      // 保存设备ID供下次自动连接
      _saveLastDevice(device.remoteId.toString());

      // 启动电压数据定期请求
      _startVoltageRequest();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已连接到 $deviceName')),
        );
      }
    } else {
      print('[连接] ❌ 连接失败');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接失败,请确保设备已开机并在附近'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 断开连接
  Future<void> _disconnect() async {
    _voltageRequestActive = false;
    await _bluetoothService.disconnect();
    setState(() {
      _connectedDevice = null;
      _voltage = 0;
      _distance = 0;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已断开连接')),
      );
    }
  }

  /// 启动定期请求电压数据
  void _startVoltageRequest() {
    _voltageRequestActive = true;
    _requestVoltageLoop();
  }

  /// 定期请求电压和距离数据的循环
  Future<void> _requestVoltageLoop() async {
    while (_voltageRequestActive && _bluetoothService.isConnected) {
      await _bluetoothService.requestVoltageData();
      await Future.delayed(const Duration(milliseconds: 200)); // 每200ms请求一次，实现更快的距离刷新
    }
  }

  /// 保存上次连接的设备ID
  Future<void> _saveLastDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_device_id', deviceId);
    print('[存储] 保存设备ID: $deviceId');
  }

  /// 获取上次连接的设备ID
  Future<String?> _getLastDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_device_id');
  }

  /// 尝试自动连接上次的设备
  Future<void> _tryAutoConnect() async {
    // 等待权限请求完成
    await Future.delayed(const Duration(seconds: 1));

    final lastDeviceId = await _getLastDeviceId();
    if (lastDeviceId == null) {
      print('[自动连接] 没有保存的设备记录');
      return;
    }

    print('[自动连接] 尝试连接上次设备: $lastDeviceId');

    // 开始扫描
    setState(() {
      _isScanning = true;
    });

    try {
      if (await fbp.FlutterBluePlus.isSupported == false) {
        print('[自动连接] 设备不支持BLE');
        setState(() {
          _isScanning = false;
        });
        return;
      }

      // 扫描8秒,寻找目标设备
      bool found = false;
      _bluetoothService.scanDevices().listen((results) {
        for (var result in results) {
          if (result.device.remoteId.toString() == lastDeviceId) {
            print('[自动连接] 找到目标设备,正在连接...');
            found = true;
            _bluetoothService.stopScan();
            setState(() {
              _isScanning = false;
            });
            _connectToDevice(result.device);
            break;
          }
        }
      });

      // 8秒后停止扫描
      Future.delayed(const Duration(seconds: 8), () {
        if (_isScanning) {
          _bluetoothService.stopScan();
          setState(() {
            _isScanning = false;
          });
          if (!found) {
            print('[自动连接] 未找到上次连接的设备');
          }
        }
      });

    } catch (e) {
      print('[自动连接] 失败: $e');
      setState(() {
        _isScanning = false;
      });
    }
  }

  /// 显示位置服务未开启的对话框
  Future<void> _showLocationServiceDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.orange),
            SizedBox(width: 8),
            Text('需要开启位置服务'),
          ],
        ),
        content: const Text(
          'Android系统要求开启位置服务(GPS)才能扫描蓝牙设备。\n\n'
          '这是系统安全要求,不会获取您的位置信息。\n\n'
          '点击"去开启"将跳转到系统设置页面。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('去开启'),
          ),
        ],
      ),
    );

    if (result == true) {
      // 请求开启位置服务
      loc.Location location = loc.Location();
      bool serviceEnabled = await location.requestService();

      if (serviceEnabled) {
        print('[位置服务] ✅ 用户已开启位置服务');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('位置服务已开启,可以开始扫描')),
          );
          // 自动开始扫描
          _scanDevices();
        }
      } else {
        print('[位置服务] ❌ 用户未开启位置服务');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('需要开启位置服务才能扫描蓝牙设备'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  /// 显示断开连接确认对话框
  Future<void> _showDisconnectDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('断开连接'),
        content: Text('确定要断开与 ${_connectedDevice?.platformName.isNotEmpty == true ? _connectedDevice!.platformName : _connectedDevice?.remoteId} 的连接吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('断开'),
          ),
        ],
      ),
    );

    if (result == true) {
      _disconnect();
    }
  }

  /// 显示速度控制对话框
  Future<void> _showSpeedDialog() async {
    double tempSpeed = _speed;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('速度控制'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('当前速度:', style: TextStyle(fontSize: 16)),
                    Text('${tempSpeed.round()}%',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                Slider(
                  value: tempSpeed,
                  min: 20,  // 最小值20
                  max: 100, // 最大值100
                  divisions: 16, // 分成16档 (20-100, 每档5)
                  label: '${tempSpeed.round()}%',
                  onChanged: (value) {
                    setDialogState(() {
                      tempSpeed = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // 快捷速度按钮
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildSpeedPreset('低速', 20, (value) {
                      setDialogState(() {
                        tempSpeed = value;
                      });
                    }),
                    _buildSpeedPreset('中速', 50, (value) {
                      setDialogState(() {
                        tempSpeed = value;
                      });
                    }),
                    _buildSpeedPreset('高速', 75, (value) {
                      setDialogState(() {
                        tempSpeed = value;
                      });
                    }),
                    _buildSpeedPreset('全速', 100, (value) {
                      setDialogState(() {
                        tempSpeed = value;
                      });
                    }),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _speed = tempSpeed;
              });
              _bluetoothService.setSpeed(_speed.round());
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('速度已设置为 ${_speed.round()}%')),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示RGB高级控制对话框（实时生效）
  Future<void> _showRgbDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('RGB高级控制'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 颜色预览
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('当前颜色:', style: TextStyle(fontSize: 16)),
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Color.fromRGBO(
                          _red.round(),
                          _green.round(),
                          _blue.round(),
                          1
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 红色滑块
                Row(
                  children: [
                    const SizedBox(
                      width: 30,
                      child: Text('R', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                    ),
                    Expanded(
                      child: Slider(
                        value: _red,
                        min: 0,
                        max: 255,
                        divisions: 255,
                        activeColor: Colors.red,
                        label: _red.round().toString(),
                        onChanged: (value) {
                          setState(() {
                            _red = value;
                          });
                          setDialogState(() {}); // 更新对话框UI
                          // 实时发送到硬件
                          _bluetoothService.setRgbColor(
                            _red.round(),
                            _green.round(),
                            _blue.round()
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(_red.round().toString(), textAlign: TextAlign.right)
                    ),
                  ],
                ),

                // 绿色滑块
                Row(
                  children: [
                    const SizedBox(
                      width: 30,
                      child: Text('G', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                    ),
                    Expanded(
                      child: Slider(
                        value: _green,
                        min: 0,
                        max: 255,
                        divisions: 255,
                        activeColor: Colors.green,
                        label: _green.round().toString(),
                        onChanged: (value) {
                          setState(() {
                            _green = value;
                          });
                          setDialogState(() {}); // 更新对话框UI
                          // 实时发送到硬件
                          _bluetoothService.setRgbColor(
                            _red.round(),
                            _green.round(),
                            _blue.round()
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(_green.round().toString(), textAlign: TextAlign.right)
                    ),
                  ],
                ),

                // 蓝色滑块
                Row(
                  children: [
                    const SizedBox(
                      width: 30,
                      child: Text('B', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                    ),
                    Expanded(
                      child: Slider(
                        value: _blue,
                        min: 0,
                        max: 255,
                        divisions: 255,
                        activeColor: Colors.blue,
                        label: _blue.round().toString(),
                        onChanged: (value) {
                          setState(() {
                            _blue = value;
                          });
                          setDialogState(() {}); // 更新对话框UI
                          // 实时发送到硬件
                          _bluetoothService.setRgbColor(
                            _red.round(),
                            _green.round(),
                            _blue.round()
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(_blue.round().toString(), textAlign: TextAlign.right)
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 构建速度预设按钮
  Widget _buildSpeedPreset(String label, double speed, Function(double) onTap) {
    return ElevatedButton(
      onPressed: () => onTap(speed),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MiniAuto 小车控制器'),
        actions: [
          // 设置图标 (仅连接时显示，用于进入电机检测)
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MotorTestPage(
                      bluetoothService: _bluetoothService,
                    ),
                  ),
                );
              },
              tooltip: '电机检测',
            ),
          // 控制模式切换开关 (仅连接时显示)
          if (_connectedDevice != null)
            IconButton(
              icon: Icon(_isAdvancedMode ? Icons.gamepad : Icons.control_camera),
              onPressed: () {
                setState(() {
                  _isAdvancedMode = !_isAdvancedMode;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_isAdvancedMode ? '已切换到高级控制模式' : '已切换到简易控制模式'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              tooltip: _isAdvancedMode ? '切换到简易控制' : '切换到高级控制',
            ),
          // 速度控制图标 (仅连接时显示)
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.speed),
              onPressed: _showSpeedDialog,
              tooltip: '速度控制',
            ),
          // 蓝牙连接/断开图标
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.bluetooth_connected),
              onPressed: _showDisconnectDialog, // 显示确认对话框
              tooltip: '断开连接',
            )
          else
            IconButton(
              icon: const Icon(Icons.bluetooth),
              onPressed: _scanDevices,
              tooltip: '扫描设备',
            ),
        ],
      ),
      body: _bluetoothService.isConnected
        ? Column(
            children: [
              // 上部可滚动区域（连接信息 + 灯光控制）
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // 连接状态卡片
                      _buildConnectionCard(),

                      // 灯光控制卡片（紧跟在连接信息下方）
                      _buildRgbControl(),
                    ],
                  ),
                ),
              ),

              // 底部固定方向控制
              _buildDirectionControl(),
              const SizedBox(height: 16), // 底部留白
            ],
          )
        : Column(
            children: [
              // 未连接时只显示连接状态卡片
              _buildConnectionCard(),
            ],
          ),
    );
  }

  /// 构建连接状态卡片
  Widget _buildConnectionCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _bluetoothService.isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: _bluetoothService.isConnected
                      ? Colors.green
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _bluetoothService.isConnected
                            ? '已连接: ${_connectedDevice?.platformName.isNotEmpty == true ? _connectedDevice!.platformName : _connectedDevice?.remoteId}'
                            : '未连接',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // 测距距离显示 (仅连接时显示)
                      if (_bluetoothService.isConnected && _distance > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.straighten, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              '距离: ${(_distance / 10).toStringAsFixed(1)} cm',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // 电量显示 (仅连接时显示)
                if (_bluetoothService.isConnected) ...[
                  const SizedBox(width: 8),
                  _buildBatteryIndicator(),
                ],
              ],
            ),
            if (!_bluetoothService.isConnected) ...[
              const SizedBox(height: 16),
              if (_isScanning)
                const Center(child: CircularProgressIndicator())
              else if (_devices.isEmpty)
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _scanDevices,
                    icon: const Icon(Icons.search),
                    label: const Text('扫描蓝牙设备'),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('可用设备:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    // 使用 ConstrainedBox 限制设备列表最大高度,并添加滚动
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _devices.length,
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          return ListTile(
                            leading: const Icon(Icons.bluetooth),
                            title: Text(device.platformName.isNotEmpty
                                ? device.platformName
                                : '未知设备'),
                            subtitle: Text(device.remoteId.toString()),
                            onTap: () => _connectToDevice(device),
                          );
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建电量指示器
  Widget _buildBatteryIndicator() {
    // 将电压(mV)转换为伏特(V)并计算电量百分比
    double voltageV = _voltage / 1000.0;

    // 7.4V锂电池电量计算 (满电8.4V, 截止电压6.0V)
    // 电量百分比 = (当前电压 - 6.0) / (8.4 - 6.0) * 100
    int batteryPercentage = ((voltageV - 6.0) / (8.4 - 6.0) * 100).clamp(0, 100).round();

    // 根据电量选择颜色和图标
    Color batteryColor;
    IconData batteryIcon;

    if (batteryPercentage > 75) {
      batteryColor = Colors.green;
      batteryIcon = Icons.battery_full;
    } else if (batteryPercentage > 50) {
      batteryColor = Colors.lightGreen;
      batteryIcon = Icons.battery_6_bar;
    } else if (batteryPercentage > 25) {
      batteryColor = Colors.orange;
      batteryIcon = Icons.battery_3_bar;
    } else if (batteryPercentage > 10) {
      batteryColor = Colors.deepOrange;
      batteryIcon = Icons.battery_2_bar;
    } else {
      batteryColor = Colors.red;
      batteryIcon = Icons.battery_alert;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(batteryIcon, color: batteryColor, size: 24),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$batteryPercentage%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: batteryColor,
              ),
            ),
            Text(
              '${voltageV.toStringAsFixed(1)}V',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建RGB灯光控制（紧凑版）
  Widget _buildRgbControl() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('灯光控制', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    // "关"按钮（放在原来预览框的位置）
                    _buildColorPreset('关', 0, 0, 0, displayR: 0, displayG: 0, displayB: 0),
                    const SizedBox(width: 8),
                    // 高级设置按钮
                    IconButton(
                      icon: const Icon(Icons.tune, size: 20),
                      onPressed: _showRgbDialog,
                      tooltip: '高级RGB控制',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 快捷颜色按钮（紧凑排列，不含"关"）
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildColorPreset('红', 10, 0, 0, displayR: 200, displayG: 0, displayB: 0),
                _buildColorPreset('橘', 50, 10, 0, displayR: 200, displayG: 100, displayB: 0),
                _buildColorPreset('黄', 30, 10, 0, displayR: 200, displayG: 200, displayB: 0),
                _buildColorPreset('绿', 0, 10, 0, displayR: 0, displayG: 200, displayB: 0),
                _buildColorPreset('青', 0, 15, 30, displayR: 0, displayG: 100, displayB: 200),
                _buildColorPreset('蓝', 0, 0, 10, displayR: 0, displayG: 0, displayB: 200),
                _buildColorPreset('紫', 10, 0, 10, displayR: 200, displayG: 0, displayB: 200),
                _buildColorPreset('白', 30, 20, 10, displayR: 255, displayG: 255, displayB: 255),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建方向控制（固定在底部）
  Widget _buildDirectionControl() {
    // 根据控制模式显示不同的UI
    return _isAdvancedMode ? _buildAdvancedControl() : _buildSimpleControl();
  }

  /// 构建简易控制UI (原有的4方向控制)
  Widget _buildSimpleControl() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 前进按钮（宽一些，带距离保护）
          _buildForwardButton(),
          const SizedBox(height: 12),

          // 左移、后退、右移 一排
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton(
                icon: Icons.arrow_back,
                label: '左移',
                onPressed: () => _bluetoothService.turnLeft(),
                color: Colors.orange,
                width: 90,
                height: 70,
              ),
              const SizedBox(width: 12),
              _buildControlButton(
                icon: Icons.arrow_downward,
                label: '后退',
                onPressed: () => _bluetoothService.backward(),
                color: Colors.blue,
                width: 90,
                height: 70,
              ),
              const SizedBox(width: 12),
              _buildControlButton(
                icon: Icons.arrow_forward,
                label: '右移',
                onPressed: () => _bluetoothService.turnRight(),
                color: Colors.orange,
                width: 90,
                height: 70,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建高级控制UI (8方向 + 旋转)
  Widget _buildAdvancedControl() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 8方向控制盘
          _build8DirectionPad(),
          const SizedBox(height: 12),

          // 旋转控制按钮
          _buildRotationButtons(),
        ],
      ),
    );
  }

  /// 构建8方向控制盘
  Widget _build8DirectionPad() {
    const double btnSize = 65.0;
    const double spacing = 8.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行: 左前、前进、右前
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDirectionButton(
              icon: Icons.north_west,
              label: '左前',
              onPressed: () => _bluetoothService.moveLeftForward(),
              color: Colors.purple,
              size: btnSize,
            ),
            const SizedBox(width: spacing),
            _buildDirectionButton(
              icon: Icons.north,
              label: '前进',
              onPressed: () => _bluetoothService.forward(),
              color: Colors.green,
              size: btnSize,
              isForward: true, // 标记为前进按钮,启用距离保护
            ),
            const SizedBox(width: spacing),
            _buildDirectionButton(
              icon: Icons.north_east,
              label: '右前',
              onPressed: () => _bluetoothService.moveRightForward(),
              color: Colors.purple,
              size: btnSize,
            ),
          ],
        ),
        const SizedBox(height: spacing),

        // 第二行: 左移、停止(空位)、右移
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDirectionButton(
              icon: Icons.west,
              label: '左移',
              onPressed: () => _bluetoothService.turnLeft(),
              color: Colors.orange,
              size: btnSize,
            ),
            const SizedBox(width: spacing + btnSize), // 中间留空
            _buildDirectionButton(
              icon: Icons.east,
              label: '右移',
              onPressed: () => _bluetoothService.turnRight(),
              color: Colors.orange,
              size: btnSize,
            ),
          ],
        ),
        const SizedBox(height: spacing),

        // 第三行: 左后、后退、右后
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDirectionButton(
              icon: Icons.south_west,
              label: '左后',
              onPressed: () => _bluetoothService.moveLeftBackward(),
              color: Colors.teal,
              size: btnSize,
            ),
            const SizedBox(width: spacing),
            _buildDirectionButton(
              icon: Icons.south,
              label: '后退',
              onPressed: () => _bluetoothService.backward(),
              color: Colors.blue,
              size: btnSize,
            ),
            const SizedBox(width: spacing),
            _buildDirectionButton(
              icon: Icons.south_east,
              label: '右后',
              onPressed: () => _bluetoothService.moveRightBackward(),
              color: Colors.teal,
              size: btnSize,
            ),
          ],
        ),
      ],
    );
  }

  /// 构建旋转控制按钮
  Widget _buildRotationButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildRotateButton(
          icon: Icons.rotate_left,
          label: '逆时针',
          onPressed: () => _bluetoothService.rotateCounterClockwise(),
          onReleased: () => _bluetoothService.stopRotate(),
          color: Colors.deepPurple,
        ),
        const SizedBox(width: 16),
        _buildRotateButton(
          icon: Icons.rotate_right,
          label: '顺时针',
          onPressed: () => _bluetoothService.rotateClockwise(),
          onReleased: () => _bluetoothService.stopRotate(),
          color: Colors.deepPurple,
        ),
      ],
    );
  }

  /// 构建方向按钮 (用于8方向控制盘)
  Widget _buildDirectionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
    required double size,
    bool isForward = false, // 是否是前进按钮(需要距离保护)
  }) {
    // 如果是前进按钮,检查距离保护
    bool canMove = true;
    if (isForward) {
      canMove = _distance == 0 || _distance >= 100;
      if (!canMove) {
        color = Colors.grey.shade400;
      }
    }

    return GestureDetector(
      onTapDown: canMove ? (_) {
        if (isForward) {
          setState(() {
            _isForwardPressed = true;
          });
        }
        onPressed();
      } : null,
      onTapUp: (_) {
        if (isForward) {
          setState(() {
            _isForwardPressed = false;
          });
        }
        _bluetoothService.stop();
      },
      onTapCancel: () {
        if (isForward) {
          setState(() {
            _isForwardPressed = false;
          });
        }
        _bluetoothService.stop();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: canMove ? [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ] : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: canMove ? Colors.white : Colors.grey.shade600,
              size: size * 0.35,
            ),
            const SizedBox(height: 2),
            Text(
              isForward && !canMove ? '过近' : label,
              style: TextStyle(
                color: canMove ? Colors.white : Colors.grey.shade600,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建旋转按钮
  Widget _buildRotateButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required VoidCallback onReleased,
    required Color color,
  }) {
    return GestureDetector(
      onTapDown: (_) => onPressed(),
      onTapUp: (_) => onReleased(),
      onTapCancel: () => onReleased(),
      child: Container(
        width: 100,
        height: 60,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建前进按钮（带距离保护）
  Widget _buildForwardButton() {
    // 判断是否可以前进（距离大于等于10cm 或 距离未知）
    bool canMoveForward = _distance == 0 || _distance >= 100;

    return GestureDetector(
      onTapDown: canMoveForward ? (_) {
        setState(() {
          _isForwardPressed = true;
        });
        _bluetoothService.forward();
      } : null,
      onTapUp: (_) {
        setState(() {
          _isForwardPressed = false;
        });
        _bluetoothService.stop();
      },
      onTapCancel: () {
        setState(() {
          _isForwardPressed = false;
        });
        _bluetoothService.stop();
      },
      child: Container(
        width: 200,
        height: 70,
        decoration: BoxDecoration(
          color: canMoveForward ? Colors.green : Colors.grey.shade400,
          borderRadius: BorderRadius.circular(12),
          boxShadow: canMoveForward ? [
            BoxShadow(
              color: Colors.green.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ] : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.arrow_upward,
              color: canMoveForward ? Colors.white : Colors.grey.shade600,
              size: 70 * 0.35,
            ),
            const SizedBox(height: 4),
            Text(
              canMoveForward ? '前进' : '距离过近',
              style: TextStyle(
                color: canMoveForward ? Colors.white : Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建颜色预设按钮（紧凑版）
  /// r, g, b: 实际发送给硬件的值
  /// displayR, displayG, displayB: 用于按钮显示的颜色值
  Widget _buildColorPreset(
    String label,
    int r,
    int g,
    int b, {
    int? displayR,
    int? displayG,
    int? displayB,
  }) {
    // 如果没有指定显示颜色，使用实际发送值
    final int btnR = displayR ?? r;
    final int btnG = displayG ?? g;
    final int btnB = displayB ?? b;

    return ElevatedButton(
      onPressed: () {
        setState(() {
          _red = r.toDouble();
          _green = g.toDouble();
          _blue = b.toDouble();
        });
        _bluetoothService.setRgbColor(r, g, b);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Color.fromRGBO(btnR, btnG, btnB, 1),
        foregroundColor: (btnR + btnG + btnB) < 400 ? Colors.white : Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  /// 构建控制按钮（支持自定义宽高）
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
    double width = 80,
    double height = 80,
  }) {
    return GestureDetector(
      onTapDown: (_) => onPressed(),
      onTapUp: (_) => _bluetoothService.stop(),
      onTapCancel: () => _bluetoothService.stop(),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: height * 0.35),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
