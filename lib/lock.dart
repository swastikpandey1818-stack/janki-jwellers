import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';

const _kPinHash = 'app_pin_hash_v1';
const _kPinSalt = 'app_pin_salt_v1';
const _kLockAfter = 'app_lock_after_sec_v1';

/// Optional 4-digit PIN that protects the app when it is opened or comes back from the background.
class AppLock extends ChangeNotifier {
  AppLock._();
  static final AppLock i = AppLock._();

  SharedPreferences? _p;
  String _hash = '';
  String _salt = '';
  int lockAfterSeconds = 30;
  bool locked = false;
  int fails = 0;
  DateTime? blockedUntil;

  bool get enabled => _hash.isNotEmpty;

  bool get blocked => blockedUntil != null && DateTime.now().isBefore(blockedUntil!);

  int get blockedSeconds => blocked ? blockedUntil!.difference(DateTime.now()).inSeconds + 1 : 0;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _p = p;
      _hash = p.getString(_kPinHash) ?? '';
      _salt = p.getString(_kPinSalt) ?? '';
      lockAfterSeconds = p.getInt(_kLockAfter) ?? 30;
    } catch (_) {
      _hash = '';
    }
    locked = enabled;
  }

  static String _digest(String pin, String salt) {
    var h = 1469598103934665603;
    final bytes = utf8.encode('$salt:$pin:$salt');
    for (var r = 0; r < 2000; r++) {
      for (final b in bytes) {
        h ^= b;
        h = (h * 1099511628211) & 0x7FFFFFFFFFFFFFFF;
      }
    }
    return h.toRadixString(16);
  }

  Future<void> setPin(String pin) async {
    _salt = DateTime.now().microsecondsSinceEpoch.toString();
    _hash = _digest(pin, _salt);
    locked = false;
    fails = 0;
    notifyListeners();
    try {
      await _p?.setString(_kPinSalt, _salt);
      await _p?.setString(_kPinHash, _hash);
    } catch (_) {}
  }

  Future<void> disable() async {
    _hash = '';
    _salt = '';
    locked = false;
    notifyListeners();
    try {
      await _p?.remove(_kPinHash);
      await _p?.remove(_kPinSalt);
    } catch (_) {}
  }

  bool verify(String pin) => enabled && _digest(pin, _salt) == _hash;

  /// Returns true when the PIN was right (and unlocks the app).
  bool tryUnlock(String pin) {
    if (blocked) return false;
    if (verify(pin)) {
      fails = 0;
      locked = false;
      notifyListeners();
      return true;
    }
    fails++;
    if (fails >= 5) {
      blockedUntil = DateTime.now().add(const Duration(seconds: 30));
      fails = 0;
    }
    notifyListeners();
    return false;
  }

  void lock() {
    if (!enabled) return;
    locked = true;
    notifyListeners();
  }

  Future<void> setLockAfter(int seconds) async {
    lockAfterSeconds = seconds;
    notifyListeners();
    try {
      await _p?.setInt(_kLockAfter, seconds);
    } catch (_) {}
  }
}

/// Wraps the whole app and covers it with the PIN screen while locked.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  DateTime? _away;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = AppLock.i;
    if (state == AppLifecycleState.paused) {
      _away = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final t = _away;
      _away = null;
      if (lock.enabled && t != null && DateTime.now().difference(t).inSeconds >= lock.lockAfterSeconds) {
        lock.lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLock.i,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (AppLock.i.enabled && AppLock.i.locked) const Positioned.fill(child: _LockScreen()),
        ],
      ),
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen();

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  String entry = '';
  bool wrong = false;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _press(String d) {
    final lock = AppLock.i;
    if (lock.blocked || entry.length >= 4) return;
    setState(() {
      entry += d;
      wrong = false;
    });
    if (entry.length == 4) {
      final ok = lock.tryUnlock(entry);
      if (!ok) {
        HapticFeedback.heavyImpact();
        setState(() {
          entry = '';
          wrong = true;
        });
        if (lock.blocked) {
          _tick?.cancel();
          _tick = Timer.periodic(const Duration(seconds: 1), (t) {
            if (!mounted) {
              t.cancel();
              return;
            }
            if (!lock.blocked) t.cancel();
            setState(() {});
          });
        }
      }
    }
  }

  void _back() {
    if (entry.isEmpty) return;
    setState(() => entry = entry.substring(0, entry.length - 1));
  }

  Widget _key(String label) {
    if (label.isEmpty) return const SizedBox(width: 78, height: 78);
    final isBack = label == 'back';
    return Padding(
      padding: const EdgeInsets.all(7),
      child: InkResponse(
        onTap: () => isBack ? _back() : _press(label),
        radius: 42,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isBack ? Colors.transparent : const Color(0x22FFFFFF),
            border: isBack ? null : Border.all(color: gold, width: 1.2),
          ),
          alignment: Alignment.center,
          child: isBack
              ? const Icon(Icons.backspace_outlined, color: goldLight)
              : Text(label, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lock = AppLock.i;
    final blocked = lock.blocked;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: maroonDark,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [maroonDark, maroon], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: gold, width: 2.5),
                      ),
                      child: ClipOval(
                        child: Image.asset(logoAsset, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: maroon, size: 40)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(shopName,
                        style: TextStyle(color: goldLight, fontSize: 21, fontWeight: FontWeight.w800, fontFamily: 'serif')),
                    const SizedBox(height: 22),
                    Text(
                      blocked
                          ? 'Too many wrong tries. Wait ${lock.blockedSeconds}s'
                          : wrong
                              ? 'Wrong PIN, try again'
                              : 'Enter your PIN',
                      style: TextStyle(color: wrong || blocked ? const Color(0xFFFFB3AD) : Colors.white70, fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < 4; i++)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 15,
                            height: 15,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < entry.length ? gold : Colors.transparent,
                              border: Border.all(color: gold, width: 1.5),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    for (final row in const [
                      ['1', '2', '3'],
                      ['4', '5', '6'],
                      ['7', '8', '9'],
                      ['', '0', 'back'],
                    ])
                      Row(mainAxisSize: MainAxisSize.min, children: [for (final k in row) _key(k)]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> _askPin(BuildContext context, String title) async {
  final ctl = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 28, letterSpacing: 12),
        decoration: const InputDecoration(counterText: '', hintText: '4 digits'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(ctl.text), child: const Text('OK')),
      ],
    ),
  );
  return (r != null && r.length == 4) ? r : null;
}

/// Settings card to switch the PIN lock on / off and change it.
class AppLockCard extends StatelessWidget {
  const AppLockCard({super.key});

  void _msg(BuildContext context, String m) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<bool> _newPin(BuildContext context) async {
    final a = await _askPin(context, 'Choose a 4-digit PIN');
    if (a == null || !context.mounted) return false;
    final b = await _askPin(context, 'Enter the PIN again');
    if (!context.mounted) return false;
    if (b == null || a != b) {
      _msg(context, 'PINs did not match. Nothing changed.');
      return false;
    }
    await AppLock.i.setPin(a);
    return true;
  }

  Future<bool> _confirmOld(BuildContext context) async {
    final p = await _askPin(context, 'Enter your current PIN');
    if (p == null) return false;
    final ok = AppLock.i.verify(p);
    if (!ok && context.mounted) _msg(context, 'Wrong PIN.');
    return ok;
  }

  String _afterLabel(int s) => s <= 0 ? 'Immediately' : s < 60 ? '$s seconds' : '${s ~/ 60} minute${s >= 120 ? 's' : ''}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLock.i,
      builder: (context, _) {
        final lock = AppLock.i;
        return Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.lock_outline, color: maroon),
                title: const Text('App Lock (PIN)', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Ask for a 4-digit PIN when the app is opened. If you forget the PIN, the only way in is to reinstall the app, so keep a backup.'),
                value: lock.enabled,
                onChanged: (on) async {
                  if (on) {
                    final done = await _newPin(context);
                    if (done && context.mounted) _msg(context, 'App lock is on.');
                  } else {
                    final ok = await _confirmOld(context);
                    if (ok) await lock.disable();
                  }
                },
              ),
              if (lock.enabled) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.password, color: maroon),
                  title: const Text('Change PIN'),
                  onTap: () async {
                    if (await _confirmOld(context) && context.mounted) {
                      final done = await _newPin(context);
                      if (done && context.mounted) _msg(context, 'PIN changed.');
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined, color: maroon),
                  title: const Text('Lock again after'),
                  subtitle: Text('${_afterLabel(lock.lockAfterSeconds)} away from the app'),
                  onTap: () async {
                    final v = await showDialog<int>(
                      context: context,
                      builder: (ctx) => SimpleDialog(
                        title: const Text('Lock again after'),
                        children: [
                          for (final s in const [0, 30, 60, 300])
                            SimpleDialogOption(
                              onPressed: () => Navigator.of(ctx).pop(s),
                              child: Text(_afterLabel(s)),
                            ),
                        ],
                      ),
                    );
                    if (v != null) await lock.setLockAfter(v);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock, color: maroon),
                  title: const Text('Lock now'),
                  onTap: lock.lock,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
