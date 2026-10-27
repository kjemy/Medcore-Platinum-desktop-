import 'dart:io';

/// Returns an OS-derived identity stable across isolates and unique across process starts.
/// It is only a boundary detector; it does not establish elapsed time while powered off.
class ProcessIdentity {
  ProcessIdentity._();

  static String current() {
    final pid = pidString;
    final creationTicks = Platform.isWindows
        ? _windowsCreationTicks(pid)
        : Platform.isLinux
            ? _linuxStartTicks()
            : throw UnsupportedError('Secure process-boundary detection is implemented only for Windows and Linux.');
    if (!RegExp(r'^\d+$').hasMatch(creationTicks)) {
      throw StateError('OS process creation identity is unavailable; security startup must fail closed.');
    }
    return '$pid-$creationTicks';
  }

  static String get pidString => pid.toString();

  static String _windowsCreationTicks(String pid) {
    final result = Process.runSync(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "(Get-Process -Id $pid).StartTime.ToUniversalTime().Ticks",
      ],
      runInShell: false,
    );
    if (result.exitCode != 0) throw StateError('Unable to read OS process creation time.');
    return result.stdout.toString().trim();
  }

  static String _linuxStartTicks() {
    final stat = File('/proc/self/stat').readAsStringSync();
    final closeParen = stat.lastIndexOf(')');
    if (closeParen < 0) throw StateError('Unable to parse OS process identity.');
    final fields = stat.substring(closeParen + 1).trim().split(RegExp(r'\s+'));
    if (fields.length <= 19) throw StateError('Unable to parse OS process start time.');
    return fields[19]; // /proc stat field 22 (starttime), after pid and comm.
  }
}
