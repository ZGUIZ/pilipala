import 'package:cookie_jar/cookie_jar.dart';

/// 登录态相关的 cookie
const List<String> sessionCookieNames = ['SESSDATA', 'bili_jct'];

/// 一份登录态：SESSDATA 与 bili_jct 必须成对出现
class SessionState {
  SessionState({
    required this.sessdata,
    required this.biliJct,
    required this.scopeCount,
  });

  final String sessdata;
  final String biliJct;

  /// 该登录态覆盖的作用域数量
  final int scopeCount;

  /// SESSDATA 中携带的服务端会话过期时间，形如 <hash>,<expiry>,...*<sign>
  int get expiry {
    try {
      final List<String> parts = Uri.decodeComponent(sessdata).split(',');
      if (parts.length > 1) {
        return int.tryParse(parts[1]) ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  String get key => '$sessdata|$biliJct';
}

/// 读取某个作用域下保存的登录态
SessionState? _readState(Map<String, SerializableCookie> cookies) {
  final String? sessdata = cookies['SESSDATA']?.cookie.value;
  final String? biliJct = cookies['bili_jct']?.cookie.value;
  if (sessdata == null || biliJct == null) return null;
  return SessionState(sessdata: sessdata, biliJct: biliJct, scopeCount: 1);
}

/// 收集 jar 中各作用域下保存的登录态
List<SessionState> readSessionStates(CookieJar jar) {
  final List<SessionState> states = [];
  if (jar is! DefaultCookieJar) return states;

  void collect(Map<String, Map<String, Map<String, SerializableCookie>>> source) {
    for (final MapEntry<String, Map<String, Map<String, SerializableCookie>>>
        host in source.entries) {
      for (final MapEntry<String, Map<String, SerializableCookie>> path
          in host.value.entries) {
        final SessionState? state = _readState(path.value);
        if (state != null) states.add(state);
      }
    }
  }

  collect(jar.domainCookies);
  collect(jar.hostCookies);
  return states;
}

/// 统一 jar 中各作用域下的登录态。
///
/// 登录后 jar 里可能同时存在多份登录态：bilibili.com 根域与
/// www.bilibili.com / api.bilibili.com 各存了一份 SESSDATA 与 bili_jct，
/// 且值并不相同。服务端解析 Cookie 头时同名 Cookie 以最后一次出现的为准，
/// 于是服务端认定的会话与 app 计算 csrf 时取到的会话可能不是同一份，点赞、
/// 投币、收藏等需要 csrf 的接口就会全部返回 -111 CSRF 校验失败。
///
/// 这里把各作用域统一成同一份登录态，之后无论请求发往哪个域、服务端按什么
/// 顺序解析 Cookie 头，认定的会话与 app 取到的 csrf 都必然配套。
Future<void> unifySessionCookies(CookieJar jar) async {
  if (jar is! DefaultCookieJar) return;
  // 触发持久化存储初始化，否则读不到已保存的 cookie
  await jar.loadForRequest(Uri.parse('https://www.bilibili.com'));

  final List<SessionState> states = readSessionStates(jar);
  if (states.isEmpty) return;

  // 按登录态归并，覆盖的作用域越多越可能是当前登录的那份
  final Map<String, SessionState> grouped = {};
  for (final SessionState state in states) {
    final SessionState? exist = grouped[state.key];
    grouped[state.key] = exist == null
        ? state
        : SessionState(
            sessdata: exist.sessdata,
            biliJct: exist.biliJct,
            scopeCount: exist.scopeCount + 1,
          );
  }

  // 服务端会话过期时间最晚的一份优先
  SessionState? canonical;
  for (final SessionState state in grouped.values) {
    if (canonical == null ||
        state.expiry > canonical.expiry ||
        (state.expiry == canonical.expiry &&
            state.scopeCount > canonical.scopeCount)) {
      canonical = state;
    }
  }
  if (canonical == null) return;

  await _writeSession(jar, canonical);
}

/// 把 jar 中各作用域下的登录态写成同一份
Future<void> _writeSession(CookieJar jar, SessionState canonical) async {
  if (jar is! DefaultCookieJar) return;

  // 先取快照，写回过程中 jar 会被修改
  final List<({String host, String path, List<Cookie> updates})> writes = [];
  // domain 为 null 表示主机作用域（不写 Domain 属性），否则写回域作用域
  void collect(
    Map<String, Map<String, Map<String, SerializableCookie>>> source, {
    required bool isDomainScope,
  }) {
    for (final MapEntry<String, Map<String, Map<String, SerializableCookie>>>
        host in source.entries) {
      for (final MapEntry<String, Map<String, SerializableCookie>> path
          in host.value.entries) {
        final List<Cookie> updates = _buildUpdates(
          path.value,
          canonical,
          isDomainScope ? host.key : null,
        );
        if (updates.isEmpty) continue;
        writes.add((host: host.key, path: path.key, updates: updates));
      }
    }
  }

  collect(jar.domainCookies, isDomainScope: true);
  collect(jar.hostCookies, isDomainScope: false);

  for (final write in writes) {
    await jar.saveFromResponse(
      Uri.parse('https://${write.host}${write.path}'),
      write.updates,
    );
  }
}

/// 生成需要写回的 cookie，保留原有属性，只替换登录态的值
///
/// 某个作用域下只存了 SESSDATA 或只存了 bili_jct 时，补齐缺失的那一个，
/// 否则该作用域发出的请求仍然配不上对。
List<Cookie> _buildUpdates(
  Map<String, SerializableCookie> cookies,
  SessionState canonical,
  String? scopeDomain,
) {
  final List<Cookie> updates = [];
  for (final String name in sessionCookieNames) {
    final SerializableCookie? exist = cookies[name];
    final String value =
        name == 'SESSDATA' ? canonical.sessdata : canonical.biliJct;
    if (exist != null) {
      if (exist.cookie.value == value) continue;
      updates.add(_withValue(exist.cookie, value));
    } else {
      updates.add(_newCookie(name, value, scopeDomain));
    }
  }
  return updates;
}

/// 新建一个登录态 cookie，[scopeDomain] 为 null 时是主机作用域
Cookie _newCookie(String name, String value, String? scopeDomain) {
  final StringBuffer buffer = StringBuffer('$name=$value');
  if (scopeDomain != null) {
    buffer.write('; Domain=$scopeDomain');
  }
  buffer.write('; Path=/');
  return Cookie.fromSetCookieValue(buffer.toString());
}

/// 保留原有属性的前提下替换 cookie 的值
Cookie _withValue(Cookie cookie, String value) {
  final StringBuffer buffer = StringBuffer('${cookie.name}=$value');
  if (cookie.expires != null) {
    buffer.write('; Expires=${_formatExpires(cookie.expires!)}');
  } else if (cookie.maxAge != null) {
    buffer.write('; Max-Age=${cookie.maxAge}');
  }
  if (cookie.domain != null) {
    buffer.write('; Domain=${cookie.domain}');
  }
  buffer.write('; Path=${cookie.path ?? '/'}');
  if (cookie.secure) buffer.write('; Secure');
  if (cookie.httpOnly) buffer.write('; HttpOnly');
  if (cookie.sameSite != null) {
    buffer.write('; SameSite=${cookie.sameSite!.name}');
  }
  return Cookie.fromSetCookieValue(buffer.toString());
}

/// 格式化 Expires，格式与 Set-Cookie 一致
String _formatExpires(DateTime expires) {
  const List<String> months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  const List<String> weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  final DateTime utc = expires.toUtc();
  final String day = utc.day.toString().padLeft(2, '0');
  final String hour = utc.hour.toString().padLeft(2, '0');
  final String minute = utc.minute.toString().padLeft(2, '0');
  final String second = utc.second.toString().padLeft(2, '0');
  return '${weekdays[utc.weekday - 1]}, $day ${months[utc.month - 1]} '
      '${utc.year} $hour:$minute:$second GMT';
}

/// 取出与 [uri] 匹配、且服务端会认定的 csrf
///
/// 服务端以 Cookie 头里最后一次出现的 SESSDATA 判定会话，csrf 必须取自
/// 同一份会话的 bili_jct。
///
/// [extraCookieHeader] 是 dio 上已经存在的全局 cookie 头，dio_cookie_manager
/// 会把它拼在 jar 里匹配到的 cookie 前面，所以判定时要一起算进去。
/// 统一登录态后各作用域下的值都相同，取哪一份都一样。
Future<String> sessionCsrf(
  CookieJar jar,
  Uri uri, {
  String? extraCookieHeader,
}) async {
  final List<Cookie> cookies = <Cookie>[
    ...?extraCookieHeader
        ?.split(';')
        .where((e) => e.isNotEmpty)
        .map((c) => Cookie.fromSetCookieValue(c)),
    ...await jar.loadForRequest(uri),
  ];
  // 与 dio_cookie_manager 拼 cookie 的顺序保持一致：路径长的在前
  cookies.sort((a, b) {
    if (a.path == null && b.path == null) return 0;
    if (a.path == null) return -1;
    if (b.path == null) return 1;
    return b.path!.length.compareTo(a.path!.length);
  });

  String? sessionDomain;
  for (final Cookie cookie in cookies) {
    if (cookie.name == 'SESSDATA') {
      sessionDomain = cookie.domain;
    }
  }
  for (final Cookie cookie in cookies) {
    if (cookie.name == 'bili_jct' && cookie.domain == sessionDomain) {
      return cookie.value;
    }
  }
  for (final Cookie cookie in cookies) {
    if (cookie.name == 'bili_jct') {
      return cookie.value;
    }
  }
  return '';
}
