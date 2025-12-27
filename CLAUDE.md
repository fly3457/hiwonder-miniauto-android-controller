# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个Flutter开发的Android蓝牙控制应用,用于通过BLE蓝牙控制miniAuto麦克纳姆轮小车。

**小车Arduino程序:**
- 路径: `D:\project\yuncii\automini\11lehand\02 程序文件\miniAuto出厂程序\app_control\miniAuto出厂程序\app_control.ino`
- 协议: 字符串协议 (格式: `X|data1|data2|...|$`)
- 功能: 运动控制、RGB灯光、速度调节、超声波避障、电压监测

**开发原则:**
- Android控制端功能应根据 `app_control.ino` 的实现来完善
- 所有新功能需要与Arduino端协议保持一致
- 计划移除手套控制相关代码,专注于APP控制模式

## 核心架构

### 通信层 (bluetooth_service.dart)

**BLE通信实现:**
- 使用 `flutter_blue_plus` 库进行BLE通信
- 服务UUID: `0000FFE0-0000-1000-8000-00805F9B34FB`
- 特征UUID: `0000FFE1-0000-1000-8000-00805F9B34FB` (同时用于收发)
- 蓝牙模块: DXBT24-5.0 (HM-10兼容)

**APP控制协议** (app_control.ino):

协议格式: `X|data1|data2|...|$`

| 命令 | 格式 | 说明 | Arduino处理函数 |
|------|------|------|----------------|
| 运动控制 | `A\|state\|$` | state: 0-10 | `Rockerandgravity_Task()` |
| RGB灯光 | `B\|r\|g\|b\|$` | r/g/b: 0-255 | `Rgb_Task()` |
| 速度控制 | `C\|speed\|$` | speed: 20-100 | `Speed_Task()` |
| 请求数据 | `D\|$` | 请求超声波距离和电压 | `MODE_ULTRASOUND_SEND` |
| 舵机控制 | `E\|angle\|$` | angle: -90到90 | `Servo_Data_Receive()` |
| 避障模式 | `F\|state\|$` | state: 0=关闭, 1=开启 | `MODE_AVOID` |

**运动控制状态码:**
- 0: 右移 (90°)
- 1: 右前 (45°)
- 2: 前进 (0°)
- 3: 左前 (315°)
- 4: 左移 (270°)
- 5: 左后 (225°)
- 6: 后退 (180°)
- 7: 右后 (135°)
- 8: 停止
- 9: 顺时针旋转
- 10: 逆时针旋转
- 11: 停止旋转

**数据返回格式:**
- `$distance,voltage$`
- distance: 超声波距离 (单位: mm)
- voltage: 电池电压 (单位: mV)

**关键方法:**
- `connect()` - BLE设备连接,自动启用notify订阅数据接收
- `_handleReceivedData()` - 解析Arduino返回的电压/距离数据
- `requestVoltageData()` - 定期请求电量信息
- `_sendAppCommand()` - 发送APP控制协议命令
- `setSpeed()` - 设置速度 (20-100)
- `setRgbColor()` - 设置RGB灯光颜色

**待移除的代码:**
- `_sendGloveCommand()` - 手套控制协议(二进制),计划移除
- 相关的手套协议注释和文档

### UI层 (main.dart)

**状态管理:**
- 使用StatefulWidget管理连接状态、电量、RGB等状态
- 关键状态: `_connectedDevice`, `_voltage`, `_showAdvancedRgb`
- 自动连接: 启动时尝试连接上次设备(SharedPreferences存储)

**电量显示实现:**
- 电量计算公式: `(voltage_mV - 6000) / (8400 - 6000) * 100`
- 基于7.4V锂电池(满电8.4V, 截止6.0V)
- 每2秒自动请求一次电压数据(`_requestVoltageLoop`)
- 根据电量百分比自动切换图标和颜色

**灯光控制UI设计:**
- 快捷颜色按钮(8个预设颜色)
- 高级RGB滑块(默认隐藏,点击展开)
- 实时颜色预览方块

**控制按钮交互:**
- 使用 `GestureDetector` 实现按下/松开控制
- `onTapDown` - 发送运动指令
- `onTapUp` / `onTapCancel` - 自动发送停止指令

### 权限和位置服务

**Android权限要求:**
- Android 11及以下: `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION`
- Android 12+: `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE`
- BLE扫描必须开启位置服务(GPS)

**位置服务检测流程:**
1. 扫描前检查 `location.serviceEnabled()`
2. 未开启时显示引导对话框
3. 调用 `location.requestService()` 跳转系统设置
4. 开启后自动重新扫描

## 开发命令

### 基础开发

```bash
# 进入项目目录
cd miniauto_controller

# 安装依赖
flutter pub get

# 运行调试版本(连接Android设备)
flutter run

# 热重载(运行中修改代码自动刷新)
# 按 'r' 键 - 热重载
# 按 'R' 键 - 热重启

# 查看设备
flutter devices

# 清理构建缓存
flutter clean
```

### 构建发布

```bash
# 构建APK(支持所有架构)
flutter build apk --release

# 构建APK(仅支持arm64)
flutter build apk --release --target-platform android-arm64

# 构建App Bundle(用于Google Play)
flutter build appbundle --release

# 输出位置:
# APK: build/app/outputs/flutter-apk/app-release.apk
# AAB: build/app/outputs/bundle/release/app-release.aab
```

### 测试和调试

```bash
# 运行测试
flutter test

# 查看日志(运行中)
flutter logs

# 分析代码
flutter analyze

# 格式化代码
flutter format lib/

# 查看已安装包版本
flutter pub outdated
```

### 常见问题排查

```bash
# 权限问题 - 检查AndroidManifest.xml
# 位置服务问题 - 确保设备GPS已开启
# BLE连接失败 - 检查蓝牙模块UUID是否匹配

# 清理并重新构建
flutter clean && flutter pub get && flutter run
```

## 架构要点

### BLE连接流程

1. **扫描阶段:**
   - 检查权限 → 检查位置服务 → 开始扫描
   - 扫描12秒后自动停止
   - 过滤显示发现的BLE设备

2. **连接阶段:**
   - 连接设备 → 发现服务 → 查找FFE0/FFE1特征
   - 启用notify订阅 → 保存设备ID
   - 启动电压数据定期请求循环

3. **通信阶段:**
   - 发送: 通过 `characteristic.write()` 发送命令
   - 接收: 通过 `characteristic.value.listen()` 订阅数据
   - 自动解析电压/距离数据并更新UI

### 数据流向

```
用户操作 → UI事件(按钮/滑块)
    ↓
BluetoothService方法调用
    ↓
构建APP协议数据包 (X|data|$)
    ↓
BLE特征写入(withoutResponse: true)
    ↓
Arduino (app_control.ino) 接收并执行
    ↓
Task_Dispatcher() 解析命令 → 执行对应任务
    ↓
返回数据(电压/距离) → $distance,voltage$
    ↓
characteristic.value.listen回调
    ↓
_handleReceivedData解析
    ↓
onDataReceived回调 → setState更新UI
```

### 状态持久化

- **自动连接**: 使用 `SharedPreferences` 保存上次连接的设备ID
- **启动流程**: 权限请求 → 读取设备ID → 自动扫描并连接
- **重连逻辑**: 扫描8秒寻找目标设备,找到后自动连接

## Arduino端实现 (app_control.ino)

### 命令处理流程

**Task_Dispatcher() 主调度器:**
```cpp
// 解析串口数据,格式: X|data1|data2|...|$
while (Serial.available() > 0) {
  String cmd = Serial.readStringUntil('$');
  // 按 '|' 分割数据到 rec_data[] 数组
  // 根据 rec_data[0] 判断命令类型
}
```

**命令映射表:**

| 命令 | 处理函数 | 功能实现 |
|------|---------|---------|
| `A\|state\|$` | `Rockerandgravity_Task()` | 解析state → 设置car_derection/speed_data/car_rot → `Velocity_Controller()` |
| `B\|r\|g\|b\|$` | `Rgb_Task()` | 解析RGB值 → `ultrasound.Color()` 控制超声波模块RGB灯 |
| `C\|speed\|$` | `Speed_Task()` | 更新 `speed_update` 变量 (20-100) |
| `D\|$` | `MODE_ULTRASOUND_SEND` | 读取超声波距离和电压 → 返回 `$distance,voltage$` |
| `E\|angle\|$` | `Servo_Data_Receive()` | 控制机械爪舵机角度 (default_angle + increase_angle) |
| `F\|state\|$` | `MODE_AVOID` | 开启/关闭避障模式 |

### 核心功能实现

**1. 电压监测 (Voltage_Detection):**
```cpp
voltage = analogRead(A3) * 0.02989;  // 单位: V
voltage_send = (int)(voltage * 1000);  // 单位: mV

// 低电量警告 (< 7.0V)
if (real_voltage_send <= 7000) {
  // 蜂鸣器警报 → RGB灯变红
}
```

**2. 麦克纳姆轮运动学 (Velocity_Controller):**
```cpp
void Velocity_Controller(uint16_t angle, uint8_t velocity, int8_t rot)
// angle: 运动方向角度 (0-359°)
//   0°=前进, 90°=右移, 180°=后退, 270°=左移
// velocity: 线速度 (0-100)
// rot: 角速度 (-100到100, 正=逆时针)

// 运动学逆解计算四轮速度:
velocity_0 = (velocity * sin(rad) - velocity * cos(rad)) * speed + rot * speed;
velocity_1 = (velocity * sin(rad) + velocity * cos(rad)) * speed - rot * speed;
velocity_2 = (velocity * sin(rad) - velocity * cos(rad)) * speed - rot * speed;
velocity_3 = (velocity * sin(rad) + velocity * cos(rad)) * speed + rot * speed;
```

**3. 避障模式 (Aovid):**
```cpp
// 当 distance < 400mm 时自动转向
// 当 distance >= 500mm 时继续前进
```

**4. 超声波测距:**
```cpp
distance = ultrasound.Filter();  // 滤波后的距离值 (mm)
```

### 硬件引脚定义

```cpp
const static uint8_t ledPin = 2;              // WS2812 RGB LED
const static uint8_t buzzerPin = 3;           // 蜂鸣器
const static uint8_t servoPin = 5;            // 机械爪舵机
const static uint8_t motorpwmPin[4] = {10, 9, 6, 11};      // 电机PWM
const static uint8_t motordirectionPin[4] = {12, 8, 7, 13}; // 电机方向
// A3: 电压检测
```

### 待实现的Android功能

根据 `app_control.ino` 的完整功能,Android端还需要添加:

1. **舵机控制界面** (E命令)
   - 滑块控制机械爪角度 (-90° 到 90°)

2. **避障模式开关** (F命令)
   - 切换按钮开启/关闭自动避障

3. **超声波距离显示**
   - 实时显示前方障碍物距离
   - 距离过近时警告提示

4. **速度范围限制**
   - 当前支持20-100,需要在UI上体现最小值20

## 调试技巧

**BLE通信日志:**
```dart
// bluetooth_service.dart 中已有详细日志
// 查看连接过程: [BLE] 前缀
// 查看数据收发: [BLE] 发送指令/收到数据
```

**UI状态监控:**
```dart
// main.dart 中的print语句
// [权限] [扫描] [连接] [自动连接] [位置服务] 前缀
```

**Arduino端调试:**
```cpp
// app_control.ino 中取消注释
Serial.println(g_state);  // 查看接收到的状态
Serial.print("$");Serial.print(distance);Serial.print(",");
Serial.print(voltage_send);Serial.print("$");  // 查看发送的数据
```

## 常见修改场景

**修改电池电压计算:**
```dart
// main.dart: _buildBatteryIndicator()
// 调整满电电压和截止电压参数
int batteryPercentage = ((voltageV - 6.0) / (8.4 - 6.0) * 100)
```

**修改数据请求频率:**
```dart
// main.dart: _requestVoltageLoop()
await Future.delayed(const Duration(seconds: 2)); // 改为其他秒数
```

**添加新的控制功能 (基于app_control.ino):**

1. **添加舵机控制:**
```dart
// bluetooth_service.dart
Future<void> setServoAngle(int angle) async {
  // angle: -90 到 90
  String command = 'E|$angle|\$';
  List<int> data = command.codeUnits;
  await _txCharacteristic!.write(data, withoutResponse: true);
}

// main.dart
// 添加滑块控件,范围 -90 到 90
```

2. **添加避障模式开关:**
```dart
// bluetooth_service.dart
Future<void> setAvoidMode(bool enabled) async {
  int state = enabled ? 1 : 0;
  String command = 'F|$state|\$';
  List<int> data = command.codeUnits;
  await _txCharacteristic!.write(data, withoutResponse: true);
}

// main.dart
// 添加Switch控件
```

3. **显示超声波距离:**
```dart
// main.dart
// 使用 _distance 变量显示距离
// 距离 < 400mm 时显示警告
```

**移除手套控制代码:**
```dart
// bluetooth_service.dart
// 删除 _sendGloveCommand() 方法
// 删除相关注释和文档

// 搜索关键词: "glove", "手套", "0x55 0x55"
```

**修改BLE UUID:**
```dart
// bluetooth_service.dart
static const String SERVICE_UUID = "新的服务UUID";
static const String TX_CHAR_UUID = "新的特征UUID";
```

## 依赖库说明

- `flutter_blue_plus`: BLE蓝牙通信 (支持跨平台)
- `permission_handler`: 运行时权限请求
- `shared_preferences`: 本地键值存储
- `location`: 位置服务检测和请求

## 代码清理计划

### 待移除的手套控制相关代码

**bluetooth_service.dart:**
```dart
// 删除以下方法和注释:
- _sendGloveCommand() 方法
- 手套协议相关注释 (二进制协议: 0x55 0x55...)
- forward()/backward()/turnLeft()/turnRight() 中的手套协议注释
```

**搜索关键词进行清理:**
- "glove" / "手套"
- "0x55 0x55"
- "二进制协议"
- "motor1" / "motor2" (在手套协议上下文中)

### 代码规范

1. **所有新功能必须基于 app_control.ino**
   - 查看Arduino代码确认支持的命令
   - 遵循 `X|data|$` 协议格式
   - 测试Arduino端是否正确响应

2. **命令发送规范:**
   - 使用 `String command = 'X|data|\$';`
   - 转换为字节: `List<int> data = command.codeUnits;`
   - 发送: `await _txCharacteristic!.write(data, withoutResponse: true);`

3. **数据接收规范:**
   - 格式: `$data1,data2,...$`
   - 解析: `dataString.substring(1, dataString.length - 1).split(',')`

## 注意事项

1. **FFE1特征同时用于收发**: 需要启用notify才能接收数据
2. **位置服务强制要求**: Android BLE扫描必须开启GPS
3. **write参数**: 使用 `withoutResponse: true` 提高发送速度
4. **内存管理**: 断开连接时清理定时器和监听器
5. **RGB值映射**: Arduino使用GRB顺序(FastLED库), Flutter使用RGB顺序
6. **速度范围**: app_control.ino 最小速度为20,不是0
7. **协议一致性**: 所有功能必须与 app_control.ino 保持同步
