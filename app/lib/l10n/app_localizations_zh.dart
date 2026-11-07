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
  String get tonightTitle => '今晚';

  @override
  String get tonightSunset => '日落';

  @override
  String get tonightDusk => '天黑';

  @override
  String get tonightDawn => '天亮';

  @override
  String get tonightSunrise => '日出';

  @override
  String get tonightMoonrise => '月出';

  @override
  String get tonightMoonset => '月落';

  @override
  String tonightDark(int hours, int minutes) {
    return '完全天黑 $hours 小时 $minutes 分';
  }

  @override
  String get tonightDarkHint => '天黑、天亮指天文晨昏：太阳在地平线下 18°';

  @override
  String get tonightPolarDay => '极昼：太阳整天不落';

  @override
  String get tonightPolarNight => '极夜：太阳整天不升起';

  @override
  String get tonightWhiteNight => '整晚都没有完全天黑';

  @override
  String tonightIllumination(int percent) {
    return '照亮 $percent%';
  }

  @override
  String tonightNextFull(String when) {
    return '满月：$when';
  }

  @override
  String tonightNextNew(String when) {
    return '新月：$when';
  }

  @override
  String get tonightNeedsLocation => '设置观测地后，这里显示今晚的日月出没和月相';

  @override
  String get tonightSetLocation => '设置观测地';

  @override
  String get diagramTitle => '示意图';

  @override
  String get diagramLunarCaption =>
      '北在上、东在左（抬头所见）。外圈是地球的半影，内圈是本影；小圆是月球在各接触时刻（P1 半影食始、U1 初亏、U2 食既、U3 生光、U4 复圆、P4 半影食终）和食甚时的位置，箭头是月球运动的方向。';

  @override
  String get diagramSolarCaption =>
      '从太阳方向看地球，北在上。实线是影子中心扫过的轨迹（标注本地时间），虚线圆是食甚时的半影范围，圆内能看到偏食；黑点是本影，落在地球上时，经过的地方能看到全食。';

  @override
  String get diagramSolarCaptionAnnular =>
      '从太阳方向看地球，北在上。实线是影子中心扫过的轨迹（标注本地时间），虚线圆是食甚时的半影范围，圆内能看到偏食；黑点是伪本影，落在地球上时，经过的地方能看到环食。';

  @override
  String get today => '今天';

  @override
  String get tomorrow => '明天';

  @override
  String inDays(int n) {
    return '$n 天后';
  }

  @override
  String get subtleHint => '肉眼几乎看不出';

  @override
  String get copyDetails => '复制';

  @override
  String get copied => '已复制';

  @override
  String get searchIdle => '选好条件后点“搜索”';

  @override
  String get yearsNext10 => '未来 10 年';

  @override
  String get yearsNext30 => '未来 30 年';

  @override
  String yearsTo2100(int year) {
    return '到 $year 年';
  }

  @override
  String yearsAll(int from, int to) {
    return '全部 $from–$to';
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
  String get endYear => '结束年';

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
  String get endBeforeStart => '结束年份不能早于起始年份';

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
  String downloadedAgo(String ago) {
    return '，$ago下载';
  }

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(int n) {
    return '$n 分钟前';
  }

  @override
  String hoursAgo(int n) {
    return '$n 小时前';
  }

  @override
  String daysAgo(int n) {
    return '$n 天前';
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
  String get settingsTitle => '设置';

  @override
  String get locationSection => '观测位置';

  @override
  String get observerLocation => '观测位置';

  @override
  String get locationGps => 'GPS 自动';

  @override
  String get locationManual => '手动';

  @override
  String get locateNow => '立即定位';

  @override
  String get locating => '正在定位…';

  @override
  String gpsFixAt(String time) {
    return '$time 定位';
  }

  @override
  String get gpsNoFix => '还没有定位，点“立即定位”或在搜索时自动定位';

  @override
  String get gpsLocateOnSearch => '搜索时自动定位';

  @override
  String get locationPrivacy =>
      '只在搜索本地可见事件、卫星凌日凌月或点“立即定位”时定位，10 分钟内的定位会直接沿用。位置只保存在本机，不会上传。';

  @override
  String get locServiceOff => '定位服务已关闭，请打开定位或改用手动位置';

  @override
  String get locDenied => '没有定位权限，请允许定位或改用手动位置';

  @override
  String get locDeniedForever => '定位权限已被拒绝，请在系统设置中允许，或改用手动位置';

  @override
  String get locTimeout => '定位超时，请到开阔处重试或改用手动位置';

  @override
  String locUnavailable(String detail) {
    return '无法定位：$detail';
  }

  @override
  String get openSystemSettings => '打开系统设置';

  @override
  String usingOldFix(String error, String time) {
    return '$error；使用 $time 的定位';
  }

  @override
  String viewResults(int count) {
    return '查看结果（$count）';
  }

  @override
  String get resultsTitle => '搜索结果';

  @override
  String get mapSection => '地图';

  @override
  String get useAmap => '使用高德地图';

  @override
  String get useAmapHint => '卫星凌日地图使用高德地图（国内更详细）；关闭则使用 OpenStreetMap。';

  @override
  String get amapConsentTitle => '使用高德地图？';

  @override
  String get amapConsentBody =>
      '卫星凌日的地图可以使用高德地图显示。高德地图 SDK 会收集设备信息、网络信息和位置信息，用于显示地图和改进服务，具体见下面的隐私政策。\n\n同意后使用高德地图；不同意则使用 OpenStreetMap。以后可以在“设置”里更改。';

  @override
  String get appPrivacyPolicy => '观象隐私政策';

  @override
  String get amapPrivacyPolicy => '高德开放平台隐私权政策';

  @override
  String get amapAgree => '同意';

  @override
  String get amapDecline => '不同意';

  @override
  String get tasksTitle => '后台任务';

  @override
  String get newTask => '提交后台任务';

  @override
  String get taskKindLong => '长跨度搜索';

  @override
  String get taskKindWatch => '持续监视';

  @override
  String get taskLongHint =>
      '用当前缓存的根数一次搜完。根数只在两周内可靠，更远的结果只能作大致参考，观测前请刷新根数重新确认。';

  @override
  String get taskWatchHint =>
      '每 4 小时刷新根数，重新搜索接下来 14 天，发现凌日凌月时通知。结果始终基于最新根数。Android 上关闭应用也会运行；其他平台需要保持应用打开。';

  @override
  String get searchDaysLabel => '搜索天数';

  @override
  String get maxRuntimeLabel => '最长计算（分钟）';

  @override
  String get watchDaysLabel => '监视天数';

  @override
  String get radiusLabel => '范围半径 km';

  @override
  String get radiusHint => '大于 0 时，也报告中心线在这个半径内经过的凌日凌月（赶到中心线上就能看到）。';

  @override
  String get stopOnHitLabel => '找到凌日凌月就结束';

  @override
  String get submit => '提交';

  @override
  String get taskSubmitted => '任务已提交，结果会出现在任务历史里';

  @override
  String get notificationDenied => '没有通知权限，结果仍会保存在任务历史里';

  @override
  String get noTasks => '还没有任务';

  @override
  String get noCachedElements => '没有可用的根数，请先在卫星页刷新根数';

  @override
  String taskLongName(int days) {
    return '长跨度搜索 · $days 天';
  }

  @override
  String taskWatchName(String until) {
    return '持续监视 · 至 $until';
  }

  @override
  String taskHitTitle(String satellite) {
    return '发现凌日凌月：$satellite';
  }

  @override
  String taskNearbyTitle(String satellite, String km) {
    return '$km km 外可见凌日凌月：$satellite';
  }

  @override
  String taskDoneTitle(String name) {
    return '任务完成：$name';
  }

  @override
  String taskTimeoutTitle(String name) {
    return '任务到时：$name';
  }

  @override
  String taskDoneBody(int hits, int total) {
    return '命中 $hits 次，共 $total 次接近';
  }

  @override
  String get statusPending => '排队中';

  @override
  String get statusRunning => '进行中';

  @override
  String get statusDone => '已完成';

  @override
  String get statusTimeout => '已到时';

  @override
  String get statusCancelled => '已取消';

  @override
  String statusFailed(String error) {
    return '失败：$error';
  }

  @override
  String get cancelTask => '取消任务';

  @override
  String get deleteTask => '删除';

  @override
  String get reportTitle => '任务报告';

  @override
  String reportParams(String sep, String radius) {
    return '角距上限 $sep°，范围半径 $radius km';
  }

  @override
  String reportSearched(String done, String total, String seconds) {
    return '已搜索 $done/$total 天，计算用时 $seconds 秒';
  }

  @override
  String reportLastRun(String time) {
    return '上次搜索 $time';
  }

  @override
  String reportCreated(String time) {
    return '提交于 $time';
  }

  @override
  String get reportHits => '命中';

  @override
  String get reportOthers => '其他接近';

  @override
  String get hitAtSite => '测站可见';

  @override
  String hitNearby(String km) {
    return '$km km 外可见';
  }

  @override
  String get beyondTwoWeeks => '超过根数两周，仅供参考';

  @override
  String get legalese => '天文事件搜索。计算结果仅供参考，观测太阳时务必做好防护。';

  @override
  String get navDashboard => '看板';

  @override
  String get navSearch => '搜索';

  @override
  String get navSatellite => '卫星';

  @override
  String get navSettings => '设置';

  @override
  String get themeMode => '外观主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeDeepSpace => '深空暗夜';

  @override
  String get themeAstroRed => '夜间红光（保护暗适应）';

  @override
  String get themeLight => '明亮浅色';

  @override
  String get dashboardTitle => '观象 · 近期看点';

  @override
  String get quickExplore => '快捷探索';

  @override
  String get quickEclipses => '近期日月食';

  @override
  String get quickEclipsesDesc => '探索未来几年的日全食、日环食与月全食';

  @override
  String get quickTransits => '行星凌日';

  @override
  String get quickTransitsDesc => '水星与金星凌日稀有天象一览';

  @override
  String get quickConjunctions => '大行星相合';

  @override
  String get quickConjunctionsDesc => '金星、木星、土星近距离相合';

  @override
  String get quickSpaceStation => '空间站凌日凌月';

  @override
  String get quickSpaceStationDesc => '天宫与国际空间站地面中心线预报';

  @override
  String get currentLocation => '观测地';

  @override
  String get curatedHighlights => '近期天象';

  @override
  String get upcomingHint =>
      '未来一年多的日月食和亮行星相合（角距 ≤ 3°），由本机星历计算；日月食为全球情况，不含肉眼几乎看不出的半影月食。';

  @override
  String get upcomingLoading => '正在计算…';

  @override
  String get upcomingNone => '没有找到';
}
