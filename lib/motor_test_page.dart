import 'package:flutter/material.dart';
import 'bluetooth_service.dart';

/// 电机检测页面
/// 用于测试4个直流电机是否正确安装和接线
class MotorTestPage extends StatefulWidget {
  final BluetoothService bluetoothService;

  const MotorTestPage({Key? key, required this.bluetoothService})
      : super(key: key);

  @override
  State<MotorTestPage> createState() => _MotorTestPageState();
}

class _MotorTestPageState extends State<MotorTestPage> {
  // 测试状态
  int _currentStep = 0; // 当前测试步骤 (0-7)
  bool _isTesting = false; // 是否正在测试
  bool _testCompleted = false; // 测试是否完成

  // 测试结果记录 - 存储实际观察到的位置和方向
  List<Map<String, String>?> _testResults = List.filled(8, null);
  // 格式: {'position': '左前/右前/左后/右后', 'direction': '正转/反转'}

  // 测试配置
  static const int testSpeed = 50; // 测试速度
  static const int testDuration = 1000; // 每次测试持续时间(ms)

  // 测试步骤定义 [电机ID, 位置名称, 方向描述, 速度]
  // 注意：物理索引定义（与 Arduino 端 app_control_common.ino 一致）
  // 物理索引0 = 右前轮, 物理索引1 = 左前轮, 物理索引2 = 左后轮, 物理索引3 = 右后轮
  final List<Map<String, dynamic>> _testSteps = [
    {'motorId': 0, 'position': '右前', 'direction': '正转', 'speed': testSpeed},
    {'motorId': 0, 'position': '右前', 'direction': '反转', 'speed': -testSpeed},
    {'motorId': 1, 'position': '左前', 'direction': '正转', 'speed': testSpeed},
    {'motorId': 1, 'position': '左前', 'direction': '反转', 'speed': -testSpeed},
    {'motorId': 2, 'position': '左后', 'direction': '正转', 'speed': testSpeed},
    {'motorId': 2, 'position': '左后', 'direction': '反转', 'speed': -testSpeed},
    {'motorId': 3, 'position': '右后', 'direction': '正转', 'speed': testSpeed},
    {'motorId': 3, 'position': '右后', 'direction': '反转', 'speed': -testSpeed},
  ];

  // 电机位置映射（物理索引 → 实际轮子位置）
  // 与 Arduino 端 app_control_common.ino 定义一致
  final Map<int, String> _motorPositions = {
    0: '右前',
    1: '左前',
    2: '左后',
    3: '右后',
  };

  // 当前步骤的选择
  String? _selectedPosition;
  String? _selectedDirection;

  @override
  void initState() {
    super.initState();
  }

  /// 开始检测
  void _startTest() {
    setState(() {
      _isTesting = true;
      _testCompleted = false;
      _currentStep = 0;
      _testResults = List.filled(8, null);
    });
    _runCurrentTest();
  }

  /// 执行当前步骤的测试
  Future<void> _runCurrentTest() async {
    if (_currentStep >= _testSteps.length) {
      return;
    }

    // 重置选择状态
    setState(() {
      _selectedPosition = null;
      _selectedDirection = null;
    });

    var step = _testSteps[_currentStep];
    int motorId = step['motorId'];
    int speed = step['speed'];

    // 发送测试指令
    await widget.bluetoothService.testMotor(motorId, speed);

    // 持续运行一段时间后停止
    await Future.delayed(Duration(milliseconds: testDuration));
    await widget.bluetoothService.testMotor(motorId, 0); // 停止电机
  }

  /// 确认当前测试结果 - 记录实际观察到的位置和方向
  void _confirmResult(String actualPosition, String actualDirection) {
    setState(() {
      _testResults[_currentStep] = {
        'position': actualPosition,
        'direction': actualDirection,
      };
      _currentStep++;

      if (_currentStep >= _testSteps.length) {
        // 测试完成
        _isTesting = false;
        _testCompleted = true;
      } else {
        // 进入下一步测试
        _runCurrentTest();
      }
    });
  }

  /// 重新开始测试
  void _resetTest() {
    setState(() {
      _isTesting = false;
      _testCompleted = false;
      _currentStep = 0;
      _testResults = List.filled(8, null);
    });
  }

  /// 构建开始界面
  Widget _buildStartView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.settings_suggest,
            size: 80,
            color: Colors.blue.shade400,
          ),
          const SizedBox(height: 24),
          const Text(
            '电机检测',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '本检测将测试4个电机的位置和转向\n共8个动作,请仔细观察轮子位置和转向',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _startTest,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始检测'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 24),
          _buildMotorInfo(),
        ],
      ),
    );
  }

  /// 构建电机信息说明
  Widget _buildMotorInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '电机编号说明（物理索引）:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          SizedBox(height: 8),
          Text('电机0: 右前轮', style: TextStyle(fontSize: 12)),
          Text('电机1: 左前轮', style: TextStyle(fontSize: 12)),
          Text('电机2: 左后轮', style: TextStyle(fontSize: 12)),
          Text('电机3: 右后轮', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  /// 构建测试中界面
  Widget _buildTestingView() {
    var step = _testSteps[_currentStep];
    int motorId = step['motorId'];
    String position = step['position'];
    String direction = step['direction'];
    int progress = _currentStep + 1;
    int total = _testSteps.length;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 进度指示
            Text(
              '测试进度: $progress / $total',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress / total,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
            ),
            const SizedBox(height: 24),

            // 位置示意图
            _buildPositionDiagram(motorId),
            const SizedBox(height: 24),

            // 当前测试信息
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade200, width: 2),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.settings,
                    size: 50,
                    color: Colors.blue.shade600,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$position轮 (电机$motorId)',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: direction == '正转' ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      direction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 确认区域
            const Text(
              '请选择实际观察到的情况:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              '预期: $position轮$direction',
              style: TextStyle(fontSize: 14, color: Colors.blue.shade700),
            ),
            const SizedBox(height: 16),

            // 位置选择
            const Text(
              '实际转动的轮子位置:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            _buildPositionSelector(),
            const SizedBox(height: 16),

            // 方向选择
            const Text(
              '实际转动方向:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            _buildDirectionSelector(),
          ],
        ),
      ),
    );
  }

  /// 构建轮子位置示意图
  Widget _buildPositionDiagram(int activeMotorId) {
    const double wheelSize = 50.0;
    const double spacing = 60.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 2),
      ),
      child: Column(
        children: [
          const Text(
            '小车俯视图',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // 车体
          Container(
            width: wheelSize + spacing * 2,
            height: wheelSize + spacing * 2,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                // 左前轮 (电机1) - 注意物理索引
                Positioned(
                  left: 0,
                  top: 0,
                  child: _buildWheel(1, activeMotorId, '左前'),
                ),
                // 右前轮 (电机0) - 注意物理索引
                Positioned(
                  right: 0,
                  top: 0,
                  child: _buildWheel(0, activeMotorId, '右前'),
                ),
                // 左后轮 (电机2)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: _buildWheel(2, activeMotorId, '左后'),
                ),
                // 右后轮 (电机3)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _buildWheel(3, activeMotorId, '右后'),
                ),
                // 前方向指示
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Icon(
                      Icons.arrow_upward,
                      color: Colors.blue.shade700,
                      size: 24,
                    ),
                  ),
                ),
                Positioned(
                  top: 35,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      '前',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单个轮子
  Widget _buildWheel(int motorId, int activeMotorId, String position) {
    bool isActive = motorId == activeMotorId;
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: isActive ? Colors.red : Colors.grey.shade700,
        borderRadius: BorderRadius.circular(6),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.red.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            motorId.toString(),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: isActive ? 20 : 16,
            ),
          ),
          if (isActive)
            const Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 16,
            ),
        ],
      ),
    );
  }

  /// 构建位置选择器
  Widget _buildPositionSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ['左前', '右前', '左后', '右后'].map((pos) {
        bool isSelected = _selectedPosition == pos;
        return ElevatedButton(
          onPressed: () {
            setState(() {
              _selectedPosition = pos;
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? Colors.blue : Colors.grey.shade300,
            foregroundColor: isSelected ? Colors.white : Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(pos, style: const TextStyle(fontSize: 14)),
        );
      }).toList(),
    );
  }

  /// 构建方向选择器
  Widget _buildDirectionSelector() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['正转', '反转'].map((dir) {
            bool isSelected = _selectedDirection == dir;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedDirection = dir;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isSelected ? Colors.green : Colors.grey.shade300,
                  foregroundColor: isSelected ? Colors.white : Colors.black87,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: Text(dir, style: const TextStyle(fontSize: 14)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        // 确认按钮
        ElevatedButton.icon(
          onPressed: (_selectedPosition != null && _selectedDirection != null)
              ? () => _confirmResult(_selectedPosition!, _selectedDirection!)
              : null,
          icon: const Icon(Icons.check),
          label: const Text('确认'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }

  /// 构建检测报告
  Widget _buildReportView() {
    // 统计结果
    int passCount = 0;
    int failCount = 0;
    for (int i = 0; i < _testResults.length; i++) {
      var result = _testResults[i];
      var expected = _testSteps[i];
      if (result != null) {
        if (result['position'] == expected['position'] &&
            result['direction'] == expected['direction']) {
          passCount++;
        } else {
          failCount++;
        }
      }
    }
    double passRate = (passCount / _testResults.length) * 100;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 整体结果
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: passCount == _testResults.length
                  ? Colors.green.shade50
                  : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: passCount == _testResults.length
                    ? Colors.green
                    : Colors.orange,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  passCount == _testResults.length
                      ? Icons.check_circle
                      : Icons.warning,
                  size: 60,
                  color: passCount == _testResults.length
                      ? Colors.green
                      : Colors.orange,
                ),
                const SizedBox(height: 16),
                Text(
                  passCount == _testResults.length ? '检测完成' : '发现问题',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '通过率: ${passRate.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatItem('通过', passCount, Colors.green),
                    const SizedBox(width: 32),
                    _buildStatItem('失败', failCount, Colors.red),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 详细结果
          const Text(
            '详细结果',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._buildDetailedResults(),
          const SizedBox(height: 24),

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _resetTest,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新检测'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建统计项
  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  /// 构建详细结果列表
  List<Widget> _buildDetailedResults() {
    List<Widget> widgets = [];

    for (int i = 0; i < _testSteps.length; i++) {
      var step = _testSteps[i];
      var actual = _testResults[i];

      // 判断是否正确
      bool isCorrect = false;
      if (actual != null) {
        isCorrect = actual['position'] == step['position'] &&
            actual['direction'] == step['direction'];
      }

      widgets.add(
        Card(
          elevation: 2,
          child: ListTile(
            leading: Icon(
              actual == null
                  ? Icons.help
                  : (isCorrect ? Icons.check_circle : Icons.cancel),
              color: actual == null
                  ? Colors.grey
                  : (isCorrect ? Colors.green : Colors.red),
              size: 32,
            ),
            title: Text(
              '预期: ${step['position']}轮 (电机${step['motorId']}) - ${step['direction']}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: actual == null
                ? const Text(
                    '未测试',
                    style: TextStyle(color: Colors.grey),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '实际: ${actual['position']}轮 - ${actual['direction']}',
                        style: TextStyle(
                          color: isCorrect ? Colors.green : Colors.orange,
                        ),
                      ),
                      if (!isCorrect)
                        Text(
                          '❌ 不匹配',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      );
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('电机检测'),
      ),
      body: _testCompleted
          ? _buildReportView()
          : (_isTesting ? _buildTestingView() : _buildStartView()),
    );
  }
}
