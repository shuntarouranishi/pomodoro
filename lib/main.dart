import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PomodoroApp());
}

enum SessionType { work, breakTime }

class PomodoroApp extends StatelessWidget {
  const PomodoroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pomodoro MVP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const PomodoroPage(),
    );
  }
}

class PomodoroPage extends StatefulWidget {
  const PomodoroPage({super.key});

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> with WidgetsBindingObserver {
  static const int workSeconds = 25 * 60;
  static const int breakSeconds = 5 * 60;

  static const String keySession = 'sessionType';
  static const String keyRunning = 'isRunning';
  static const String keyEndEpochMs = 'endEpochMs';
  static const String keyPausedRemaining = 'pausedRemaining';

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Timer? _ticker;
  SessionType _sessionType = SessionType.work;
  bool _isRunning = false;
  DateTime? _endAt;
  int _pausedRemaining = workSeconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconcileElapsedTime();
    }
  }

  Future<void> _bootstrap() async {
    await _initNotifications();
    await _restoreState();
    _startTicker();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initNotifications() async {
    tz.initializeTimeZones();

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(iOS: iosSettings);
    await _notifications.initialize(settings);
  }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionType = (prefs.getString(keySession) == SessionType.breakTime.name)
        ? SessionType.breakTime
        : SessionType.work;
    _isRunning = prefs.getBool(keyRunning) ?? false;
    _pausedRemaining = prefs.getInt(keyPausedRemaining) ?? _defaultSeconds;

    final endEpochMs = prefs.getInt(keyEndEpochMs);
    _endAt = endEpochMs != null ? DateTime.fromMillisecondsSinceEpoch(endEpochMs) : null;

    await _reconcileElapsedTime();
  }

  int get _defaultSeconds => _sessionType == SessionType.work ? workSeconds : breakSeconds;

  int get _remainingSeconds {
    if (_isRunning && _endAt != null) {
      final diff = _endAt!.difference(DateTime.now()).inSeconds;
      return diff.clamp(0, 24 * 60 * 60);
    }
    return _pausedRemaining;
  }

  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keySession, _sessionType.name);
    await prefs.setBool(keyRunning, _isRunning);
    await prefs.setInt(keyPausedRemaining, _pausedRemaining);
    if (_endAt != null) {
      await prefs.setInt(keyEndEpochMs, _endAt!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(keyEndEpochMs);
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (_isRunning && _remainingSeconds == 0) {
        _onSessionComplete();
        return;
      }
      setState(() {});
    });
  }

  Future<void> _start() async {
    if (_isRunning) {
      return;
    }
    final now = DateTime.now();
    _endAt = now.add(Duration(seconds: _pausedRemaining));
    _isRunning = true;
    await _scheduleCompletionNotification();
    await _persistState();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pause() async {
    if (!_isRunning) {
      return;
    }
    _pausedRemaining = _remainingSeconds;
    _isRunning = false;
    _endAt = null;
    await _notifications.cancel(0);
    await _persistState();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _reset() async {
    _isRunning = false;
    _endAt = null;
    _pausedRemaining = _defaultSeconds;
    await _notifications.cancel(0);
    await _persistState();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onSessionComplete() async {
    _isRunning = false;
    _endAt = null;
    _sessionType = _sessionType == SessionType.work ? SessionType.breakTime : SessionType.work;
    _pausedRemaining = _defaultSeconds;
    await _persistState();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _reconcileElapsedTime() async {
    if (_isRunning && _endAt != null && _remainingSeconds == 0) {
      await _onSessionComplete();
      return;
    }
    if (!_isRunning && _pausedRemaining <= 0) {
      _pausedRemaining = _defaultSeconds;
    }
    await _persistState();
  }

  Future<void> _scheduleCompletionNotification() async {
    if (_endAt == null) {
      return;
    }

    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _notifications.zonedSchedule(
      0,
      'Pomodoro',
      _sessionType == SessionType.work ? '作業時間が終了しました。休憩しましょう！' : '休憩が終了しました。作業を再開しましょう！',
      tz.TZDateTime.from(_endAt!, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  String _label(SessionType type) => type == SessionType.work ? '作業中' : '休憩中';

  String _formatMMSS(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remainingSeconds;

    return Scaffold(
      appBar: AppBar(title: const Text('Pomodoro MVP')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_label(_sessionType), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              Text(
                _formatMMSS(remaining),
                style: Theme.of(context).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 36),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(onPressed: _isRunning ? null : _start, child: const Text('Start')),
                  OutlinedButton(onPressed: _isRunning ? _pause : null, child: const Text('Pause')),
                  TextButton(onPressed: _reset, child: const Text('Reset')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
