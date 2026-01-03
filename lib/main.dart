import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bluetooth_service.dart';
import 'settings_page.dart';
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

  // HSB色彩模式状态
  double _hue = 0.0; // 色相 0-360度

  // 控制模式: false=简易模式, true=高级模式
  bool _isAdvancedMode = false;

  // 电压信息
  int _voltage = 0; // 单位: mV
  int _distance = 0; // 单位: mm

  // 定时器用于定期请求电压数据
  bool _voltageRequestActive = false;

  // 前进按钮状态（用于距离保护）
  bool _isForwardPressed = false;

  // 用户活动检测（用于智能电压请求）
  bool _isUserControlling = false;
  DateTime? _lastControlTime;

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

  /// 定期请求电压和距离数据的循环（智能暂停）
  Future<void> _requestVoltageLoop() async {
    while (_voltageRequestActive && _bluetoothService.isConnected) {
      // 智能电压请求：如果用户在1秒内有操作，暂停电压请求以避免BLE冲突
      if (_isUserControlling &&
          _lastControlTime != null &&
          DateTime.now().difference(_lastControlTime!).inMilliseconds < 1000) {
        // 用户正在操作，暂停电压请求，等待100ms后重新检查
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      // 用户已停止操作超过1秒，恢复电压请求
      _isUserControlling = false;
      await _bluetoothService.requestVoltageData();
      await Future.delayed(const Duration(milliseconds: 100)); // 优化: 100ms间隔,提升距离显示响应速度(方案1A)
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

  /// HSB转RGB颜色转换
  /// h: 色相 0-360度
  /// s: 饱和度 0.0-1.0
  /// brightness: 亮度 0.0-1.0
  /// 返回: [r, g, b] 0-255
  List<int> hsbToRgb(double h, double s, double brightness) {
    // 确保h在0-360范围内
    h = h % 360;

    double c = brightness * s; // 色度
    double x = c * (1 - ((h / 60) % 2 - 1).abs());
    double m = brightness - c;

    double r0, g0, b0;

    if (h < 60) {
      r0 = c; g0 = x; b0 = 0;
    } else if (h < 120) {
      r0 = x; g0 = c; b0 = 0;
    } else if (h < 180) {
      r0 = 0; g0 = c; b0 = x;
    } else if (h < 240) {
      r0 = 0; g0 = x; b0 = c;
    } else if (h < 300) {
      r0 = x; g0 = 0; b0 = c;
    } else {
      r0 = c; g0 = 0; b0 = x;
    }

    int r = ((r0 + m) * 255).round();
    int g = ((g0 + m) * 255).round();
    int b = ((b0 + m) * 255).round();

    return [r, g, b];
  }

  /// 通过HSB设置颜色
  void _setColorByHSB(double hue) {
    // S设置为100% (1.0), B保持50% (0.5)
    List<int> rgb = hsbToRgb(hue, 1.0, 0.5);

    setState(() {
      _hue = hue;
      _red = rgb[0].toDouble();
      _green = rgb[1].toDouble();
      _blue = rgb[2].toDouble();
    });

    _bluetoothService.setRgbColor(rgb[0], rgb[1], rgb[2]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MiniAuto控制器'),
        actions: [
          // 设置图标 (仅连接时显示，点击进入设置页)
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsPage(
                      bluetoothService: _bluetoothService,
                      isAdvancedMode: _isAdvancedMode,
                      onModeChanged: (value) {
                        setState(() {
                          _isAdvancedMode = value;
                        });
                      },
                    ),
                  ),
                );
              },
              tooltip: '设置',
            ),
          // 速度控制图标 (仅连接时显示)
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.speed),
              onPressed: _showSpeedDialog,
              tooltip: '速度控制',
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
                // 蓝牙图标按钮 - 已连接时点击断开,未连接时点击扫描
                IconButton(
                  icon: Icon(
                    _bluetoothService.isConnected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
                    color: _bluetoothService.isConnected
                        ? Colors.green
                        : Colors.grey,
                  ),
                  onPressed: _bluetoothService.isConnected
                      ? _showDisconnectDialog
                      : _scanDevices,
                  tooltip: _bluetoothService.isConnected ? '断开连接' : '扫描设备',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('可用设备:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('${_devices.length}个',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 设备列表占据大部分屏幕高度，添加滚动条
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6, // 占据60%的屏幕高度
                      child: Scrollbar(
                        thumbVisibility: true, // 始终显示滚动条
                        thickness: 6.0,
                        radius: const Radius.circular(3),
                        child: ListView.builder(
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

  /// 构建RGB灯光控制（HSB色彩模式）
  Widget _buildRgbControl() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行: 白色圆形按钮 + 黑色圆形按钮 + RGB设置按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('灯光控制', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    // 白色按钮（圆形）- 纯白光
                    _buildCircularColorButton(
                      color: Colors.white,
                      borderColor: Colors.grey.shade400,
                      onPressed: () {
                        setState(() {
                          _red = 255;
                          _green = 255;
                          _blue = 255;
                        });
                        _bluetoothService.setRgbColor(255, 255, 255);
                      },
                    ),
                    const SizedBox(width: 10),
                    // 黑色按钮（圆形，关灯）
                    _buildCircularColorButton(
                      color: Colors.black,
                      borderColor: Colors.grey.shade600,
                      onPressed: () {
                        setState(() {
                          _red = 0;
                          _green = 0;
                          _blue = 0;
                        });
                        _bluetoothService.setRgbColor(0, 0, 0);
                      },
                    ),
                    const SizedBox(width: 10),
                    // 高级RGB设置按钮
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
            const SizedBox(height: 16),

            // HSB色相滑块 - 带彩虹渐变背景
            Row(
              children: [
                const SizedBox(
                  width: 30,
                  child: Text('色相', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))
                ),
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      // 彩虹渐变背景: S=100%, B=100% 显示纯色
                      // 红->黄->绿->青->蓝->洋红->红
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFF0000), // 红色 0° (S=100%, B=100%)
                          Color(0xFFFFFF00), // 黄色 60°
                          Color(0xFF00FF00), // 绿色 120°
                          Color(0xFF00FFFF), // 青色 180°
                          Color(0xFF0000FF), // 蓝色 240°
                          Color(0xFFFF00FF), // 洋红 300°
                          Color(0xFFFF0000), // 红色 360° (循环)
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade300, width: 1),
                    ),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 0, // 隐藏原生轨道,使用渐变背景
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12.0),
                        thumbColor: Colors.white,
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20.0),
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                      ),
                      child: Slider(
                        value: _hue,
                        min: 0,
                        max: 360,
                        divisions: 72, // 每5度一个刻度
                        label: '${_hue.round()}°',
                        onChanged: (value) {
                          _setColorByHSB(value);
                        },
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 45,
                  child: Text('${_hue.round()}°', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建圆形颜色按钮
  Widget _buildCircularColorButton({
    required Color color,
    required Color borderColor,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
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

  /// 构建简易控制UI (4方向控制)
  Widget _buildSimpleControl() {
    // 计算按钮尺寸: 屏幕宽度80% / 3个按钮 - 间距
    double screenWidth = MediaQuery.of(context).size.width;
    double availableWidth = screenWidth * 0.8;
    double spacing = 12.0;
    double buttonSize = (availableWidth - spacing * 2) / 3;

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
          // 第一行: 前进按钮居中
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildUnifiedControlButton(
                icon: Icons.arrow_upward,
                label: '前进',
                onPressed: () => _bluetoothService.forward(),
                color: Colors.green,
                width: buttonSize,
                height: buttonSize,
                isForward: true, // 启用距离保护
              ),
            ],
          ),
          SizedBox(height: spacing),

          // 第二行: 左移、后退、右移
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildUnifiedControlButton(
                icon: Icons.arrow_back,
                label: '左移',
                onPressed: () => _bluetoothService.turnLeft(),
                color: Colors.orange,
                width: buttonSize,
                height: buttonSize,
              ),
              SizedBox(width: spacing),
              _buildUnifiedControlButton(
                icon: Icons.arrow_downward,
                label: '后退',
                onPressed: () => _bluetoothService.backward(),
                color: Colors.blue,
                width: buttonSize,
                height: buttonSize,
              ),
              SizedBox(width: spacing),
              _buildUnifiedControlButton(
                icon: Icons.arrow_forward,
                label: '右移',
                onPressed: () => _bluetoothService.turnRight(),
                color: Colors.orange,
                width: buttonSize,
                height: buttonSize,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建高级控制UI (8方向 + 旋转)
  Widget _buildAdvancedControl() {
    // 获取屏幕尺寸
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    // 控制区域最大高度为屏幕的1/3
    double maxControlHeight = screenHeight / 3;

    // 计算按钮间距
    double spacing = 12.0;
    double verticalPadding = 12.0;

    // 按钮宽度: 屏幕宽度80% / 3个按钮 - 间距
    double availableWidth = screenWidth * 0.8;
    double buttonWidth = (availableWidth - spacing * 2) / 3;

    // 按钮高度: 根据控制区域最大高度计算
    // 高级控制模式总共有:
    // - 3行方向键 (每行高度 buttonHeight)
    // - 2个间距 (在3行方向键之间)
    // - 1个间距 (方向键和旋转按钮之间)
    // - 1行旋转按钮 (高度 buttonHeight * 0.6)
    // - 上下padding (verticalPadding * 2)
    // 总高度 = buttonHeight * 3 + spacing * 3 + buttonHeight * 0.6 + verticalPadding * 2
    //        = buttonHeight * 3.6 + spacing * 3 + verticalPadding * 2

    // 根据最大高度反推按钮高度
    double availableHeight = maxControlHeight - (spacing * 3 + verticalPadding * 2);
    double buttonHeight = availableHeight / 3.6;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: verticalPadding),
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
          _build8DirectionPad(buttonWidth, buttonHeight, spacing),
          SizedBox(height: spacing),

          // 旋转控制按钮
          _buildRotationButtons(buttonWidth, buttonHeight, spacing),
        ],
      ),
    );
  }

  /// 构建8方向控制盘
  Widget _build8DirectionPad(double btnWidth, double btnHeight, double spacing) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行: 左前、前进、右前
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildUnifiedControlButton(
              icon: Icons.north_west,
              label: '左前',
              onPressed: () => _bluetoothService.moveLeftForward(),
              color: Colors.purple,
              width: btnWidth,
              height: btnHeight,
            ),
            SizedBox(width: spacing),
            _buildUnifiedControlButton(
              icon: Icons.north,
              label: '前进',
              onPressed: () => _bluetoothService.forward(),
              color: Colors.green,
              width: btnWidth,
              height: btnHeight,
              isForward: true, // 标记为前进按钮,启用距离保护
            ),
            SizedBox(width: spacing),
            _buildUnifiedControlButton(
              icon: Icons.north_east,
              label: '右前',
              onPressed: () => _bluetoothService.moveRightForward(),
              color: Colors.purple,
              width: btnWidth,
              height: btnHeight,
            ),
          ],
        ),
        SizedBox(height: spacing),

        // 第二行: 左移、停止(空位)、右移
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildUnifiedControlButton(
              icon: Icons.west,
              label: '左移',
              onPressed: () => _bluetoothService.turnLeft(),
              color: Colors.orange,
              width: btnWidth,
              height: btnHeight,
            ),
            SizedBox(width: spacing + btnWidth), // 中间留空
            _buildUnifiedControlButton(
              icon: Icons.east,
              label: '右移',
              onPressed: () => _bluetoothService.turnRight(),
              color: Colors.orange,
              width: btnWidth,
              height: btnHeight,
            ),
          ],
        ),
        SizedBox(height: spacing),

        // 第三行: 左后、后退、右后
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildUnifiedControlButton(
              icon: Icons.south_west,
              label: '左后',
              onPressed: () => _bluetoothService.moveLeftBackward(),
              color: Colors.teal,
              width: btnWidth,
              height: btnHeight,
            ),
            SizedBox(width: spacing),
            _buildUnifiedControlButton(
              icon: Icons.south,
              label: '后退',
              onPressed: () => _bluetoothService.backward(),
              color: Colors.blue,
              width: btnWidth,
              height: btnHeight,
            ),
            SizedBox(width: spacing),
            _buildUnifiedControlButton(
              icon: Icons.south_east,
              label: '右后',
              onPressed: () => _bluetoothService.moveRightBackward(),
              color: Colors.teal,
              width: btnWidth,
              height: btnHeight,
            ),
          ],
        ),
      ],
    );
  }

  /// 构建旋转控制按钮
  Widget _buildRotationButtons(double btnWidth, double btnHeight, double spacing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildRotateButton(
          icon: Icons.rotate_left,
          label: '逆时针',
          onPressed: () => _bluetoothService.rotateCounterClockwise(),
          onReleased: () => _bluetoothService.stopRotate(),
          color: Colors.deepPurple,
          width: btnWidth,
          height: btnHeight * 0.6, // 旋转按钮高度为方向键的60%
        ),
        SizedBox(width: spacing),
        _buildRotateButton(
          icon: Icons.rotate_right,
          label: '顺时针',
          onPressed: () => _bluetoothService.rotateClockwise(),
          onReleased: () => _bluetoothService.stopRotate(),
          color: Colors.deepPurple,
          width: btnWidth,
          height: btnHeight * 0.6, // 旋转按钮高度为方向键的60%
        ),
      ],
    );
  }

  /// 构建统一控制按钮 (支持距离保护)
  Widget _buildUnifiedControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
    required double width,
    required double height,
    bool isForward = false, // 是否是前进按钮(需要距离保护)
  }) {
    // 如果是前进按钮,检查距离保护
    bool canMove = true;
    Color buttonColor = color;

    if (isForward) {
      canMove = _distance == 0 || _distance >= 100;
      if (!canMove) {
        buttonColor = Colors.grey.shade400;
      }
    }

    return GestureDetector(
      onTapDown: canMove ? (_) {
        // 标记用户正在操作（智能电压请求）
        _isUserControlling = true;
        _lastControlTime = DateTime.now();

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
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: buttonColor,
          borderRadius: BorderRadius.circular(10),
          boxShadow: canMove ? [
            BoxShadow(
              color: buttonColor.withOpacity(0.3),
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
              size: height * 0.35,
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
    required double width,
    required double height,
  }) {
    return GestureDetector(
      onTapDown: (_) {
        // 标记用户正在操作（智能电压请求）
        _isUserControlling = true;
        _lastControlTime = DateTime.now();
        onPressed();
      },
      onTapUp: (_) => onReleased(),
      onTapCancel: () => onReleased(),
      child: Container(
        width: width,
        height: height,
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
            Icon(icon, color: Colors.white, size: height * 0.4),
            SizedBox(width: width * 0.04),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: height * 0.2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
