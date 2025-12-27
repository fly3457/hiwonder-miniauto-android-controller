# 项目编译和运行指南

## 前置条件

1. **Flutter SDK**: 确保已安装Flutter 3.0+
2. **Android Studio**: 已安装并配置好Android SDK
3. **设备**: Android 5.0+ (API 21+) 的手机或模拟器
4. **小车Arduino程序**: 已烧录 `app_control.ino` (出厂程序)

## 项目依赖

当前使用的关键依赖包:
- `flutter_blue_plus: ^1.32.0` - BLE蓝牙通信
- `permission_handler: ^11.0.0` - 权限管理
- `shared_preferences: ^2.2.2` - 本地存储(保存上次连接设备)
- `location: ^5.0.0` - 位置服务检测

## 编译步骤

### 1. 配置Flutter SDK路径

在项目根目录创建 `android/local.properties` 文件:

```properties
sdk.dir=C:\\Users\\你的用户名\\AppData\\Local\\Android\\sdk
flutter.sdk=C:\\flutter路径
```

### 2. 获取依赖

```bash
cd miniauto_controller
flutter pub get
```

### 3. 检查环境

```bash
flutter doctor
```

确保以下项目都有绿色勾号:
- Flutter SDK
- Android toolchain
- Android Studio

### 4. 连接设备或启动模拟器

```bash
# 查看可用设备
flutter devices

# 如果没有设备,启动Android模拟器
# 或通过USB连接真机并开启USB调试
```

### 5. 运行应用

```bash
# 调试模式运行
flutter run

# 或指定设备
flutter run -d <device-id>

# 热重载 (运行中按 'r' 键)
# 热重启 (运行中按 'R' 键)
```

### 6. 构建APK

```bash
# 构建Release版本APK (推荐)
flutter build apk --release

# 构建Debug版本APK
flutter build apk --debug

# 构建特定架构 (减小体积)
flutter build apk --release --target-platform android-arm64

# 清空构建缓存
flutter clean

# APK输出位置:
# Release: build/app/outputs/flutter-apk/app-release.apk
# Debug: build/app/outputs/flutter-apk/app-debug.apk
```

## 常见问题

### 问题1: Gradle下载慢

**解决方案**: 已在 `android/settings.gradle` 中配置阿里云镜像

### 问题2: 位置服务错误 (PlatformException: Location services are required)

**错误原因**: Android BLE扫描需要开启位置服务(GPS)

**解决方案**:
1. 应用会自动弹出引导对话框
2. 点击"去开启"跳转到系统设置
3. 开启位置服务后返回应用
4. 应用会自动开始扫描

**注意**: 这是Android系统要求,不会获取实际位置信息

### 问题3: 权限被拒绝

**解决方案**:
- 首次运行会自动请求权限
- 在手机设置中手动授予应用以下权限:
  - 蓝牙权限 (Android 12+: 附近的设备)
  - 位置权限 (精确位置)
- 重启应用重新请求

### 问题4: 扫描不到设备

**解决方案**:
1. 确保蓝牙已开启
2. 确保位置服务(GPS)已开启
3. 确保小车已开机
4. 小车蓝牙不需要在系统设置中配对
5. 点击扫描按钮重新扫描

### 问题5: 连接失败

**解决方案**:
- 检查小车是否已开机
- 确保小车蓝牙未被其他设备连接
- 检查蓝牙模块UUID是否匹配 (FFE0/FFE1)
- 查看日志输出的错误信息
- 尝试重启小车和应用

### 问题6: 电量显示为0%

**原因**: 电压数据未接收或Arduino未返回数据

**解决方案**:
1. 确保连接成功
2. 等待2秒(数据请求间隔)
3. 检查Arduino串口监视器是否有输出
4. 查看Flutter日志是否收到数据

## 测试清单

### 基础功能
- [ ] 应用成功启动
- [ ] 自动请求蓝牙和位置权限
- [ ] 位置服务检测和引导正常
- [ ] 扫描到小车蓝牙设备
- [ ] 成功连接到小车
- [ ] 显示连接状态
- [ ] 电量图标和百分比显示正常

### 运动控制
- [ ] 前进按钮正常工作
- [ ] 后退按钮正常工作
- [ ] 左移按钮正常工作
- [ ] 右移按钮正常工作
- [ ] 停止按钮正常工作
- [ ] 松开按钮自动停止

### 速度控制
- [ ] 速度调节对话框正常打开
- [ ] 速度滑块范围 20-100
- [ ] 速度预设按钮 (低速/中速/高速/全速)
- [ ] 速度设置成功发送到小车

### 灯光控制
- [ ] 快捷颜色按钮正常工作 (8种颜色)
- [ ] 颜色预览方块实时更新
- [ ] 高级选项展开/收起正常
- [ ] RGB滑块默认隐藏
- [ ] RGB滑块调节正常
- [ ] 灯光颜色正确显示在小车上

### 连接管理
- [ ] 断开连接确认对话框
- [ ] 断开连接功能正常
- [ ] 重启应用自动连接上次设备
- [ ] 连接断开后自动清理资源

## 调试技巧

### 查看日志

```bash
# 实时查看Flutter日志
flutter logs

# 过滤特定标签
flutter logs | grep "\[BLE\]"
flutter logs | grep "\[权限\]"
flutter logs | grep "\[扫描\]"
```

### 日志关键信息

应用已添加详细日志输出:
- `[权限]` - 权限请求相关
- `[扫描]` - BLE设备扫描
- `[连接]` - 设备连接过程
- `[BLE]` - 蓝牙通信细节
- `[位置服务]` - 位置服务检测

### 使用Android Studio调试

1. 用Android Studio打开项目
2. 选择设备
3. 点击运行按钮 (Shift+F10)
4. 使用Logcat查看详细日志
5. 设置断点调试代码

### Arduino端调试

在 `app_control.ino` 中取消注释以下代码:
```cpp
// 查看接收到的状态
Serial.println(g_state);

// 查看发送的电压数据
Serial.print("$");Serial.print(distance);Serial.print(",");
Serial.print(voltage_send);Serial.print("$");
```

## 性能优化建议

1. **电量请求频率**: 当前每2秒请求一次,可根据需要调整
2. **BLE写入优化**: 使用 `withoutResponse: true` 提高速度
3. **UI响应优化**: 按钮使用 GestureDetector 避免延迟
4. **内存管理**: 断开连接时清理定时器和监听器

## 已实现功能

✅ **蓝牙通信**
- BLE设备扫描和连接
- 自动重连上次设备
- 稳定的数据收发

✅ **权限管理**
- 自动请求所需权限
- 位置服务检测和引导
- 友好的错误提示

✅ **运动控制**
- 四方向移动 (前/后/左/右)
- 按下发送/松开停止

✅ **速度控制**
- 范围 20-100
- 四档预设 (低速/中速/高速/全速)

✅ **灯光控制**
- 8种快捷颜色
- RGB高级调节 (可展开/收起)
- 实时颜色预览

✅ **电量显示**
- 实时电压监测
- 电量百分比计算
- 根据电量自动变色的图标

## 待实现功能

基于 `app_control.ino` 支持的功能,以下功能待添加:

1. **舵机控制** (E命令)
   - 机械爪角度控制 (-90° 到 90°)

2. **避障模式** (F命令)
   - 开启/关闭自动避障

3. **超声波距离显示**
   - 实时显示距离值
   - 距离过近时警告

4. **更多运动方向**
   - 斜向移动 (45°, 135°, 225°, 315°)
   - 原地旋转 (顺时针/逆时针)

## 代码清理计划

计划移除手套控制相关代码:
- `bluetooth_service.dart` 中的 `_sendGloveCommand()` 方法
- 手套协议相关注释 (二进制: 0x55 0x55...)
- 搜索关键词: "glove", "手套", "motor1", "motor2"

## 发布前检查

- [ ] 所有测试用例通过
- [ ] 日志中无错误信息
- [ ] 在多台设备上测试
- [ ] 移除Debug相关代码
- [ ] 更新版本号 (pubspec.yaml)
- [ ] 构建Release APK
- [ ] APK在真机上测试通过
