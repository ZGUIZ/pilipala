import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilipala/http/session.dart';

/// 域作用域下的登录态，服务端会话过期时间更晚
/// 真实 SESSDATA 是 url 编码过的，逗号写作 %2C
const String sessdataA = 'aaaa%2C1999999999%2C1%2AsigA';
const String jctA = 'jct-a';

/// 主机作用域下的旧登录态
const String sessdataB = 'bbbb%2C1800000000%2C2%2AsigB';
const String jctB = 'jct-b';

Cookie _cookie(String name, String value, {String? domain}) =>
    Cookie.fromSetCookieValue(
        '$name=$value; Path=/${domain == null ? '' : '; Domain=$domain'}');

/// 构造一个和线上一样的 jar：域作用域一份登录态，主机作用域另一份
Future<DefaultCookieJar> buildJar() async {
  final DefaultCookieJar jar = DefaultCookieJar();
  await jar.saveFromResponse(Uri.parse('https://bilibili.com/'), [
    _cookie('SESSDATA', sessdataA, domain: 'bilibili.com'),
    _cookie('bili_jct', jctA, domain: 'bilibili.com'),
  ]);
  await jar.saveFromResponse(Uri.parse('https://api.bilibili.com/'), [
    _cookie('SESSDATA', sessdataB),
    _cookie('bili_jct', jctB),
  ]);
  return jar;
}

/// 拼出请求头，和 dio_cookie_manager 的做法一致
String headerOf(List<Cookie> cookies) =>
    cookies.map((c) => '${c.name}=${c.value}').join('; ');

void main() {
  test('统一登录态后各作用域都变成同一份', () async {
    final DefaultCookieJar jar = await buildJar();
    await unifySessionCookies(jar);

    for (final String url in [
      'https://www.bilibili.com',
      'https://api.bilibili.com',
      'https://api.vc.bilibili.com',
    ]) {
      final List<Cookie> cookies = await jar.loadForRequest(Uri.parse(url));
      final String sessdata =
          cookies.firstWhere((c) => c.name == 'SESSDATA').value;
      final String jct = cookies.firstWhere((c) => c.name == 'bili_jct').value;
      expect(sessdata, sessdataA, reason: '$url 的 SESSDATA 没有统一');
      expect(jct, jctA, reason: '$url 的 bili_jct 没有统一');
    }
  });

  test('csrf 取的是请求头里最后一个 SESSDATA 配套的 bili_jct', () async {
    final DefaultCookieJar jar = await buildJar();
    final Uri uri = Uri.parse('https://api.bilibili.com/x/web-interface/archive/like');

    // 未统一时，请求头里存在两份登录态，服务端按最后一个 SESSDATA 判定
    final List<Cookie> cookies = await jar.loadForRequest(uri);
    final String header = headerOf(cookies);
    final String lastSessdata = header
        .split('; ')
        .where((e) => e.startsWith('SESSDATA='))
        .last;
    final String lastJct = header
        .split('; ')
        .where((e) => e.startsWith('bili_jct='))
        .last;
    expect(
      await sessionCsrf(jar, uri),
      lastJct.substring('bili_jct='.length),
      reason: 'csrf 必须和服务端认定的会话配套',
    );
    // 用例本身要能复现两份登录态并存的情况
    expect(
      header.split('; ').where((e) => e.startsWith('SESSDATA=')).toSet().length,
      2,
      reason: '请求头里应该同时存在两份不同的 SESSDATA',
    );
    expect(lastSessdata, isNotEmpty);
  });

  test('统一之后 csrf 与请求头里的会话必然配套', () async {
    final DefaultCookieJar jar = await buildJar();
    await unifySessionCookies(jar);

    final Uri uri =
        Uri.parse('https://api.bilibili.com/x/web-interface/archive/like');
    final String header = headerOf(await jar.loadForRequest(uri));
    final Set<String> sessdataValues = header
        .split('; ')
        .where((e) => e.startsWith('SESSDATA='))
        .toSet();
    final Set<String> jctValues = header
        .split('; ')
        .where((e) => e.startsWith('bili_jct='))
        .toSet();

    expect(sessdataValues.length, 1);
    expect(jctValues.length, 1);
    expect(await sessionCsrf(jar, uri),
        jctValues.first.substring('bili_jct='.length));
  });
}
