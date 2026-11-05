// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '观象';

  @override
  String get searchTitle => '观象 · 天文事件搜索';

  @override
  String get loadingEphemeris => '正在加载星历…';

  @override
  String ephemerisLoadFailed(String error) {
    return '星历加载失败：$error';
  }

  @override
  String ephemerisLoaded(int ms) {
    return '星历加载 $ms ms';
  }

  @override
  String get kindTransit => '凌日';

  @override
  String get kindConjunction => '合';

  @override
  String get kindOpposition => '冲';

  @override
  String get kindAppulse => '角距极小';

  @override
  String get kindSolarEclipse => '日食';

  @override
  String get kindLunarEclipse => '月食';

  @override
  String get kindOccultation => '月掩星';

  @override
  String get occAll => '全部（行星和 550 颗亮星）';

  @override
  String get occPlanets => '全部行星';

  @override
  String get occStars => '全部亮星';

  @override
  String get starSpica => '角宿一';

  @override
  String get starAntares => '心宿二';

  @override
  String get starRegulus => '轩辕十四';

  @override
  String get starAldebaran => '毕宿五';

  @override
  String get starAlcyone => '昴宿六（昴星团）';

  @override
  String get occultedTarget => '被掩目标';

  @override
  String get eclipseHint => '日月食按地心计算；打开“只显示本地可见”可得到本地情况';

  @override
  String get planet => '行星';

  @override
  String get mercuryAndVenus => '水星和金星';

  @override
  String get bodyA => '天体 A';

  @override
  String get bodyB => '天体 B';

  @override
  String get maxSeparation => '角距上限°';

  @override
  String get startYear => '起始年';

  @override
  String get endYear => '结束年（不含）';

  @override
  String get localOnly => '只显示本地可见';

  @override
  String get localOnlyHint => '目标在地平线上；非凌日事件还要求太阳低于 −6°';

  @override
  String get latitude => '纬度°';

  @override
  String get longitude => '经度°（东正）';

  @override
  String get height => '高度 m';

  @override
  String get search => '搜索';

  @override
  String get cancel => '取消';

  @override
  String get satelliteTooltip => '卫星凌日、凌月';

  @override
  String get aboutTooltip => '关于与许可';

  @override
  String get noResults => '暂无结果';

  @override
  String get searching => '搜索中…';

  @override
  String searchFinished(int count, int ms) {
    return '共 $count 个事件，用时 $ms ms';
  }

  @override
  String searchCancelled(int count, int ms) {
    return '已取消，共 $count 个事件，用时 $ms ms';
  }

  @override
  String searchFailed(String error) {
    return '搜索失败：$error';
  }

  @override
  String get searchFailedShort => '搜索失败';

  @override
  String get invalidObserver => '测站坐标无效';

  @override
  String detailFooter(String jd) {
    return '时刻为 UTC。TT 儒略日 $jd。';
  }

  @override
  String get enterYears => '请输入起止年份';

  @override
  String get endAfterStart => '结束年份必须晚于起始年份';

  @override
  String yearsOutOfRange(int from, int to) {
    return '内置星历只覆盖 $from–$to 年，请在这个范围内搜索';
  }

  @override
  String get satTitle => '卫星凌日、凌月';

  @override
  String get issName => '国际空间站';

  @override
  String get cssName => '天宫空间站';

  @override
  String cacheOpenFailed(String error) {
    return '打开根数缓存失败：$error';
  }

  @override
  String get enterNorad => '请输入 NORAD 编号';

  @override
  String get invalidInput => '输入无效';

  @override
  String get noElementsYet => '还没有根数，请先刷新';

  @override
  String get computing => '计算中…';

  @override
  String satSummary(int count, int transits, int ms) {
    return '共 $count 次接近（$transits 次凌日凌月），用时 $ms ms';
  }

  @override
  String get noElements => '无根数';

  @override
  String cacheEpoch(String epoch) {
    return '历元 $epoch UTC';
  }

  @override
  String downloadedAgo(int minutes) {
    return '，$minutes 分钟前下载';
  }

  @override
  String get hasPrevious => '，有旧根数可比较';

  @override
  String get noradNumber => 'NORAD 编号';

  @override
  String get addSatellite => '添加卫星';

  @override
  String get refreshElements => '刷新根数';

  @override
  String get days => '天数';

  @override
  String get startTime => '起始时间（本地）';

  @override
  String get startNow => '现在';

  @override
  String get resetToNow => '改回现在';

  @override
  String get osmAttribution => '© OpenStreetMap 贡献者';

  @override
  String centerlineHintSun(String width) {
    return '红线（未凌时为橙线）是中心线：最近时刻前后各 10 秒的地面轨迹，站在线上看到卫星正好穿过日心。可见带半宽约 $width km。';
  }

  @override
  String centerlineHintMoon(String width) {
    return '红线（未凌时为橙线）是中心线：最近时刻前后各 10 秒的地面轨迹，站在线上看到卫星正好穿过月心。可见带半宽约 $width km。';
  }

  @override
  String get refreshBlocked => '之前的请求出错，暂停下载，使用缓存的根数';

  @override
  String refreshRecent(int minutes) {
    return '$minutes 分钟前已下载，CelesTrak 每 2 小时才更新，使用缓存';
  }

  @override
  String refreshNetwork(String error) {
    return '$error，使用缓存的根数';
  }

  @override
  String refreshHttp(int status) {
    return 'CelesTrak 返回 $status，暂停下载 2 小时';
  }

  @override
  String refreshInvalid(int id, String hint) {
    return '没有拿到编号 $id 的根数：$hint';
  }

  @override
  String refreshUpdated(String epoch) {
    return '已更新，根数历元 $epoch';
  }

  @override
  String refreshUnchanged(String epoch) {
    return '根数没有变化（历元 $epoch）';
  }

  @override
  String errInternal(String message) {
    return '内部错误：$message';
  }

  @override
  String get errNetwork => '网络不可用，请检查网络连接';

  @override
  String get errTimeout => '请求超时，请稍后再试';

  @override
  String errHttp(String message) {
    return '网络请求失败：$message';
  }

  @override
  String errFormat(String message) {
    return '数据格式错误：$message';
  }

  @override
  String get legalese => '天文事件搜索。计算结果仅供参考，观测太阳时务必做好防护。';
}
