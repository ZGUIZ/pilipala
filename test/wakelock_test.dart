import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/plugin/pl_player/controller.dart';
import 'package:pilipala/utils/global_data_cache.dart';
import 'package:pilipala/utils/storage.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// 记录 wakelock 调用 以便断言
class FakeWakelock extends WakelockPlusPlatformInterface {
  final List<bool> calls = [];
  bool _enabled = false;

  @override
  Future<void> toggle({required bool enable}) async {
    calls.add(enable);
    _enabled = enable;
  }

  @override
  Future<bool> get enabled async => _enabled;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWakelock fake;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pilipala_wakelock_test');
    Hive.init(tempDir.path);
    GStrorage.userInfo = await Hive.openBox('userInfo');
    GStrorage.localCache = await Hive.openBox('localCache');
    GStrorage.setting = await Hive.openBox('setting');
    GStrorage.historyword = await Hive.openBox('historyWord');
    GStrorage.video = await Hive.openBox('video');
    await GlobalDataCache().initialize();

    // 播放器销毁时会重置亮度 这里给个空实现
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('github.com/aaassseee/screen_brightness'),
      (call) async => null,
    );
  });

  setUp(() {
    fake = FakeWakelock();
    wakelockPlusPlatformInstance = fake;
    GStrorage.setting.delete(SettingBoxKey.enableKeepScreenOn);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('播放中开启屏幕常亮 暂停后关闭', () async {
    final controller = PlPlayerController();

    controller.updateWakelock(playing: true);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(fake.calls, contains(true));

    controller.updateWakelock(playing: false);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(fake.calls.last, false);

    await controller.dispose();
  });

  test('设置关闭时不开启屏幕常亮', () async {
    GStrorage.setting.put(SettingBoxKey.enableKeepScreenOn, false);

    final controller = PlPlayerController();
    controller.updateWakelock(playing: true);
    await Future.delayed(const Duration(milliseconds: 50));

    expect(fake.calls, isNot(contains(true)));
    expect(fake.calls.last, false);

    await controller.dispose();
  });

  test('状态未变化时不重复调用', () async {
    final controller = PlPlayerController();

    controller.updateWakelock(playing: true);
    await Future.delayed(const Duration(milliseconds: 50));
    final int count = fake.calls.length;

    controller.updateWakelock(playing: true);
    controller.updateWakelock(playing: true);
    await Future.delayed(const Duration(milliseconds: 50));

    expect(fake.calls.length, count);

    await controller.dispose();
  });
}
