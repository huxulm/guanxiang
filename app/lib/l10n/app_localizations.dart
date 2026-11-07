import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'观象'**
  String get appTitle;

  /// No description provided for @searchTitle.
  ///
  /// In zh, this message translates to:
  /// **'观象 · 天文事件搜索'**
  String get searchTitle;

  /// No description provided for @loadingEphemeris.
  ///
  /// In zh, this message translates to:
  /// **'正在加载星历…'**
  String get loadingEphemeris;

  /// No description provided for @ephemerisLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'星历加载失败：{error}'**
  String ephemerisLoadFailed(String error);

  /// No description provided for @tonightTitle.
  ///
  /// In zh, this message translates to:
  /// **'今晚'**
  String get tonightTitle;

  /// No description provided for @tonightSunset.
  ///
  /// In zh, this message translates to:
  /// **'日落'**
  String get tonightSunset;

  /// No description provided for @tonightDusk.
  ///
  /// In zh, this message translates to:
  /// **'天黑'**
  String get tonightDusk;

  /// No description provided for @tonightDawn.
  ///
  /// In zh, this message translates to:
  /// **'天亮'**
  String get tonightDawn;

  /// No description provided for @tonightSunrise.
  ///
  /// In zh, this message translates to:
  /// **'日出'**
  String get tonightSunrise;

  /// No description provided for @tonightMoonrise.
  ///
  /// In zh, this message translates to:
  /// **'月出'**
  String get tonightMoonrise;

  /// No description provided for @tonightMoonset.
  ///
  /// In zh, this message translates to:
  /// **'月落'**
  String get tonightMoonset;

  /// No description provided for @tonightDark.
  ///
  /// In zh, this message translates to:
  /// **'完全天黑 {hours} 小时 {minutes} 分'**
  String tonightDark(int hours, int minutes);

  /// No description provided for @tonightDarkHint.
  ///
  /// In zh, this message translates to:
  /// **'天黑、天亮指天文晨昏：太阳在地平线下 18°'**
  String get tonightDarkHint;

  /// No description provided for @tonightPolarDay.
  ///
  /// In zh, this message translates to:
  /// **'极昼：太阳整天不落'**
  String get tonightPolarDay;

  /// No description provided for @tonightPolarNight.
  ///
  /// In zh, this message translates to:
  /// **'极夜：太阳整天不升起'**
  String get tonightPolarNight;

  /// No description provided for @tonightWhiteNight.
  ///
  /// In zh, this message translates to:
  /// **'整晚都没有完全天黑'**
  String get tonightWhiteNight;

  /// No description provided for @tonightIllumination.
  ///
  /// In zh, this message translates to:
  /// **'照亮 {percent}%'**
  String tonightIllumination(int percent);

  /// No description provided for @tonightNextFull.
  ///
  /// In zh, this message translates to:
  /// **'满月：{when}'**
  String tonightNextFull(String when);

  /// No description provided for @tonightNextNew.
  ///
  /// In zh, this message translates to:
  /// **'新月：{when}'**
  String tonightNextNew(String when);

  /// No description provided for @tonightNeedsLocation.
  ///
  /// In zh, this message translates to:
  /// **'设置观测地后，这里显示今晚的日月出没和月相'**
  String get tonightNeedsLocation;

  /// No description provided for @tonightSetLocation.
  ///
  /// In zh, this message translates to:
  /// **'设置观测地'**
  String get tonightSetLocation;

  /// No description provided for @diagramTitle.
  ///
  /// In zh, this message translates to:
  /// **'示意图'**
  String get diagramTitle;

  /// No description provided for @diagramLunarCaption.
  ///
  /// In zh, this message translates to:
  /// **'北在上、东在左（抬头所见）。外圈是地球的半影，内圈是本影；小圆是月球在各接触时刻（P1 半影食始、U1 初亏、U2 食既、U3 生光、U4 复圆、P4 半影食终）和食甚时的位置，箭头是月球运动的方向。'**
  String get diagramLunarCaption;

  /// No description provided for @diagramSolarCaption.
  ///
  /// In zh, this message translates to:
  /// **'从太阳方向看地球，北在上。实线是影子中心扫过的轨迹（标注本地时间），虚线圆是食甚时的半影范围，圆内能看到偏食；黑点是本影，落在地球上时，经过的地方能看到全食。'**
  String get diagramSolarCaption;

  /// No description provided for @diagramSolarCaptionAnnular.
  ///
  /// In zh, this message translates to:
  /// **'从太阳方向看地球，北在上。实线是影子中心扫过的轨迹（标注本地时间），虚线圆是食甚时的半影范围，圆内能看到偏食；黑点是伪本影，落在地球上时，经过的地方能看到环食。'**
  String get diagramSolarCaptionAnnular;

  /// No description provided for @today.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get today;

  /// No description provided for @tomorrow.
  ///
  /// In zh, this message translates to:
  /// **'明天'**
  String get tomorrow;

  /// No description provided for @inDays.
  ///
  /// In zh, this message translates to:
  /// **'{n} 天后'**
  String inDays(int n);

  /// No description provided for @subtleHint.
  ///
  /// In zh, this message translates to:
  /// **'肉眼几乎看不出'**
  String get subtleHint;

  /// No description provided for @copyDetails.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copyDetails;

  /// No description provided for @copied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get copied;

  /// No description provided for @searchIdle.
  ///
  /// In zh, this message translates to:
  /// **'选好条件后点“搜索”'**
  String get searchIdle;

  /// No description provided for @yearsNext10.
  ///
  /// In zh, this message translates to:
  /// **'未来 10 年'**
  String get yearsNext10;

  /// No description provided for @yearsNext30.
  ///
  /// In zh, this message translates to:
  /// **'未来 30 年'**
  String get yearsNext30;

  /// No description provided for @yearsTo2100.
  ///
  /// In zh, this message translates to:
  /// **'到 {year} 年'**
  String yearsTo2100(int year);

  /// No description provided for @yearsAll.
  ///
  /// In zh, this message translates to:
  /// **'全部 {from}–{to}'**
  String yearsAll(int from, int to);

  /// No description provided for @kindTransit.
  ///
  /// In zh, this message translates to:
  /// **'凌日'**
  String get kindTransit;

  /// No description provided for @kindConjunction.
  ///
  /// In zh, this message translates to:
  /// **'合'**
  String get kindConjunction;

  /// No description provided for @kindOpposition.
  ///
  /// In zh, this message translates to:
  /// **'冲'**
  String get kindOpposition;

  /// No description provided for @kindAppulse.
  ///
  /// In zh, this message translates to:
  /// **'角距极小'**
  String get kindAppulse;

  /// No description provided for @kindSolarEclipse.
  ///
  /// In zh, this message translates to:
  /// **'日食'**
  String get kindSolarEclipse;

  /// No description provided for @kindLunarEclipse.
  ///
  /// In zh, this message translates to:
  /// **'月食'**
  String get kindLunarEclipse;

  /// No description provided for @kindOccultation.
  ///
  /// In zh, this message translates to:
  /// **'月掩星'**
  String get kindOccultation;

  /// No description provided for @occAll.
  ///
  /// In zh, this message translates to:
  /// **'全部（行星和 550 颗亮星）'**
  String get occAll;

  /// No description provided for @occPlanets.
  ///
  /// In zh, this message translates to:
  /// **'全部行星'**
  String get occPlanets;

  /// No description provided for @occStars.
  ///
  /// In zh, this message translates to:
  /// **'全部亮星'**
  String get occStars;

  /// No description provided for @starSpica.
  ///
  /// In zh, this message translates to:
  /// **'角宿一'**
  String get starSpica;

  /// No description provided for @starAntares.
  ///
  /// In zh, this message translates to:
  /// **'心宿二'**
  String get starAntares;

  /// No description provided for @starRegulus.
  ///
  /// In zh, this message translates to:
  /// **'轩辕十四'**
  String get starRegulus;

  /// No description provided for @starAldebaran.
  ///
  /// In zh, this message translates to:
  /// **'毕宿五'**
  String get starAldebaran;

  /// No description provided for @starAlcyone.
  ///
  /// In zh, this message translates to:
  /// **'昴宿六（昴星团）'**
  String get starAlcyone;

  /// No description provided for @occultedTarget.
  ///
  /// In zh, this message translates to:
  /// **'被掩目标'**
  String get occultedTarget;

  /// No description provided for @eclipseHint.
  ///
  /// In zh, this message translates to:
  /// **'日月食按地心计算；打开“只显示本地可见”可得到本地情况'**
  String get eclipseHint;

  /// No description provided for @planet.
  ///
  /// In zh, this message translates to:
  /// **'行星'**
  String get planet;

  /// No description provided for @mercuryAndVenus.
  ///
  /// In zh, this message translates to:
  /// **'水星和金星'**
  String get mercuryAndVenus;

  /// No description provided for @bodyA.
  ///
  /// In zh, this message translates to:
  /// **'天体 A'**
  String get bodyA;

  /// No description provided for @bodyB.
  ///
  /// In zh, this message translates to:
  /// **'天体 B'**
  String get bodyB;

  /// No description provided for @maxSeparation.
  ///
  /// In zh, this message translates to:
  /// **'角距上限°'**
  String get maxSeparation;

  /// No description provided for @startYear.
  ///
  /// In zh, this message translates to:
  /// **'起始年'**
  String get startYear;

  /// No description provided for @endYear.
  ///
  /// In zh, this message translates to:
  /// **'结束年'**
  String get endYear;

  /// No description provided for @localOnly.
  ///
  /// In zh, this message translates to:
  /// **'只显示本地可见'**
  String get localOnly;

  /// No description provided for @localOnlyHint.
  ///
  /// In zh, this message translates to:
  /// **'目标在地平线上；非凌日事件还要求太阳低于 −6°'**
  String get localOnlyHint;

  /// No description provided for @latitude.
  ///
  /// In zh, this message translates to:
  /// **'纬度°'**
  String get latitude;

  /// No description provided for @longitude.
  ///
  /// In zh, this message translates to:
  /// **'经度°（东正）'**
  String get longitude;

  /// No description provided for @height.
  ///
  /// In zh, this message translates to:
  /// **'高度 m'**
  String get height;

  /// No description provided for @search.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get search;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @satelliteTooltip.
  ///
  /// In zh, this message translates to:
  /// **'卫星凌日、凌月'**
  String get satelliteTooltip;

  /// No description provided for @aboutTooltip.
  ///
  /// In zh, this message translates to:
  /// **'关于与许可'**
  String get aboutTooltip;

  /// No description provided for @noResults.
  ///
  /// In zh, this message translates to:
  /// **'暂无结果'**
  String get noResults;

  /// No description provided for @searching.
  ///
  /// In zh, this message translates to:
  /// **'搜索中…'**
  String get searching;

  /// No description provided for @searchFinished.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 个事件，用时 {ms} ms'**
  String searchFinished(int count, int ms);

  /// No description provided for @searchCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消，共 {count} 个事件，用时 {ms} ms'**
  String searchCancelled(int count, int ms);

  /// No description provided for @searchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败：{error}'**
  String searchFailed(String error);

  /// No description provided for @searchFailedShort.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败'**
  String get searchFailedShort;

  /// No description provided for @invalidObserver.
  ///
  /// In zh, this message translates to:
  /// **'测站坐标无效'**
  String get invalidObserver;

  /// No description provided for @detailFooter.
  ///
  /// In zh, this message translates to:
  /// **'时刻为 UTC。TT 儒略日 {jd}。'**
  String detailFooter(String jd);

  /// No description provided for @enterYears.
  ///
  /// In zh, this message translates to:
  /// **'请输入起止年份'**
  String get enterYears;

  /// No description provided for @endBeforeStart.
  ///
  /// In zh, this message translates to:
  /// **'结束年份不能早于起始年份'**
  String get endBeforeStart;

  /// No description provided for @yearsOutOfRange.
  ///
  /// In zh, this message translates to:
  /// **'内置星历只覆盖 {from}–{to} 年，请在这个范围内搜索'**
  String yearsOutOfRange(int from, int to);

  /// No description provided for @satTitle.
  ///
  /// In zh, this message translates to:
  /// **'卫星凌日、凌月'**
  String get satTitle;

  /// No description provided for @issName.
  ///
  /// In zh, this message translates to:
  /// **'国际空间站'**
  String get issName;

  /// No description provided for @cssName.
  ///
  /// In zh, this message translates to:
  /// **'天宫空间站'**
  String get cssName;

  /// No description provided for @cacheOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'打开根数缓存失败：{error}'**
  String cacheOpenFailed(String error);

  /// No description provided for @enterNorad.
  ///
  /// In zh, this message translates to:
  /// **'请输入 NORAD 编号'**
  String get enterNorad;

  /// No description provided for @invalidInput.
  ///
  /// In zh, this message translates to:
  /// **'输入无效'**
  String get invalidInput;

  /// No description provided for @noElementsYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有根数，请先刷新'**
  String get noElementsYet;

  /// No description provided for @computing.
  ///
  /// In zh, this message translates to:
  /// **'计算中…'**
  String get computing;

  /// No description provided for @satSummary.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 次接近（{transits} 次凌日凌月），用时 {ms} ms'**
  String satSummary(int count, int transits, int ms);

  /// No description provided for @noElements.
  ///
  /// In zh, this message translates to:
  /// **'无根数'**
  String get noElements;

  /// No description provided for @cacheEpoch.
  ///
  /// In zh, this message translates to:
  /// **'历元 {epoch} UTC'**
  String cacheEpoch(String epoch);

  /// No description provided for @downloadedAgo.
  ///
  /// In zh, this message translates to:
  /// **'，{ago}下载'**
  String downloadedAgo(String ago);

  /// No description provided for @justNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{n} 分钟前'**
  String minutesAgo(int n);

  /// No description provided for @hoursAgo.
  ///
  /// In zh, this message translates to:
  /// **'{n} 小时前'**
  String hoursAgo(int n);

  /// No description provided for @daysAgo.
  ///
  /// In zh, this message translates to:
  /// **'{n} 天前'**
  String daysAgo(int n);

  /// No description provided for @hasPrevious.
  ///
  /// In zh, this message translates to:
  /// **'，有旧根数可比较'**
  String get hasPrevious;

  /// No description provided for @noradNumber.
  ///
  /// In zh, this message translates to:
  /// **'NORAD 编号'**
  String get noradNumber;

  /// No description provided for @addSatellite.
  ///
  /// In zh, this message translates to:
  /// **'添加卫星'**
  String get addSatellite;

  /// No description provided for @refreshElements.
  ///
  /// In zh, this message translates to:
  /// **'刷新根数'**
  String get refreshElements;

  /// No description provided for @days.
  ///
  /// In zh, this message translates to:
  /// **'天数'**
  String get days;

  /// No description provided for @startTime.
  ///
  /// In zh, this message translates to:
  /// **'起始时间（本地）'**
  String get startTime;

  /// No description provided for @startNow.
  ///
  /// In zh, this message translates to:
  /// **'现在'**
  String get startNow;

  /// No description provided for @resetToNow.
  ///
  /// In zh, this message translates to:
  /// **'改回现在'**
  String get resetToNow;

  /// No description provided for @osmAttribution.
  ///
  /// In zh, this message translates to:
  /// **'© OpenStreetMap 贡献者'**
  String get osmAttribution;

  /// No description provided for @centerlineHintSun.
  ///
  /// In zh, this message translates to:
  /// **'红线（未凌时为橙线）是中心线：最近时刻前后各 10 秒的地面轨迹，站在线上看到卫星正好穿过日心。可见带半宽约 {width} km。'**
  String centerlineHintSun(String width);

  /// No description provided for @centerlineHintMoon.
  ///
  /// In zh, this message translates to:
  /// **'红线（未凌时为橙线）是中心线：最近时刻前后各 10 秒的地面轨迹，站在线上看到卫星正好穿过月心。可见带半宽约 {width} km。'**
  String centerlineHintMoon(String width);

  /// No description provided for @refreshBlocked.
  ///
  /// In zh, this message translates to:
  /// **'之前的请求出错，暂停下载，使用缓存的根数'**
  String get refreshBlocked;

  /// No description provided for @refreshRecent.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟前已下载，CelesTrak 每 2 小时才更新，使用缓存'**
  String refreshRecent(int minutes);

  /// No description provided for @refreshNetwork.
  ///
  /// In zh, this message translates to:
  /// **'{error}，使用缓存的根数'**
  String refreshNetwork(String error);

  /// No description provided for @refreshHttp.
  ///
  /// In zh, this message translates to:
  /// **'CelesTrak 返回 {status}，暂停下载 2 小时'**
  String refreshHttp(int status);

  /// No description provided for @refreshInvalid.
  ///
  /// In zh, this message translates to:
  /// **'没有拿到编号 {id} 的根数：{hint}'**
  String refreshInvalid(int id, String hint);

  /// No description provided for @refreshUpdated.
  ///
  /// In zh, this message translates to:
  /// **'已更新，根数历元 {epoch}'**
  String refreshUpdated(String epoch);

  /// No description provided for @refreshUnchanged.
  ///
  /// In zh, this message translates to:
  /// **'根数没有变化（历元 {epoch}）'**
  String refreshUnchanged(String epoch);

  /// No description provided for @errInternal.
  ///
  /// In zh, this message translates to:
  /// **'内部错误：{message}'**
  String errInternal(String message);

  /// No description provided for @errNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络不可用，请检查网络连接'**
  String get errNetwork;

  /// No description provided for @errTimeout.
  ///
  /// In zh, this message translates to:
  /// **'请求超时，请稍后再试'**
  String get errTimeout;

  /// No description provided for @errHttp.
  ///
  /// In zh, this message translates to:
  /// **'网络请求失败：{message}'**
  String errHttp(String message);

  /// No description provided for @errFormat.
  ///
  /// In zh, this message translates to:
  /// **'数据格式错误：{message}'**
  String errFormat(String message);

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @locationSection.
  ///
  /// In zh, this message translates to:
  /// **'观测位置'**
  String get locationSection;

  /// No description provided for @observerLocation.
  ///
  /// In zh, this message translates to:
  /// **'观测位置'**
  String get observerLocation;

  /// No description provided for @locationGps.
  ///
  /// In zh, this message translates to:
  /// **'GPS 自动'**
  String get locationGps;

  /// No description provided for @locationManual.
  ///
  /// In zh, this message translates to:
  /// **'手动'**
  String get locationManual;

  /// No description provided for @locateNow.
  ///
  /// In zh, this message translates to:
  /// **'立即定位'**
  String get locateNow;

  /// No description provided for @locating.
  ///
  /// In zh, this message translates to:
  /// **'正在定位…'**
  String get locating;

  /// No description provided for @gpsFixAt.
  ///
  /// In zh, this message translates to:
  /// **'{time} 定位'**
  String gpsFixAt(String time);

  /// No description provided for @gpsNoFix.
  ///
  /// In zh, this message translates to:
  /// **'还没有定位，点“立即定位”或在搜索时自动定位'**
  String get gpsNoFix;

  /// No description provided for @gpsLocateOnSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索时自动定位'**
  String get gpsLocateOnSearch;

  /// No description provided for @locationPrivacy.
  ///
  /// In zh, this message translates to:
  /// **'只在搜索本地可见事件、卫星凌日凌月或点“立即定位”时定位，10 分钟内的定位会直接沿用。位置只保存在本机，不会上传。'**
  String get locationPrivacy;

  /// No description provided for @locServiceOff.
  ///
  /// In zh, this message translates to:
  /// **'定位服务已关闭，请打开定位或改用手动位置'**
  String get locServiceOff;

  /// No description provided for @locDenied.
  ///
  /// In zh, this message translates to:
  /// **'没有定位权限，请允许定位或改用手动位置'**
  String get locDenied;

  /// No description provided for @locDeniedForever.
  ///
  /// In zh, this message translates to:
  /// **'定位权限已被拒绝，请在系统设置中允许，或改用手动位置'**
  String get locDeniedForever;

  /// No description provided for @locTimeout.
  ///
  /// In zh, this message translates to:
  /// **'定位超时，请到开阔处重试或改用手动位置'**
  String get locTimeout;

  /// No description provided for @locUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法定位：{detail}'**
  String locUnavailable(String detail);

  /// No description provided for @openSystemSettings.
  ///
  /// In zh, this message translates to:
  /// **'打开系统设置'**
  String get openSystemSettings;

  /// No description provided for @usingOldFix.
  ///
  /// In zh, this message translates to:
  /// **'{error}；使用 {time} 的定位'**
  String usingOldFix(String error, String time);

  /// No description provided for @viewResults.
  ///
  /// In zh, this message translates to:
  /// **'查看结果（{count}）'**
  String viewResults(int count);

  /// No description provided for @resultsTitle.
  ///
  /// In zh, this message translates to:
  /// **'搜索结果'**
  String get resultsTitle;

  /// No description provided for @mapSection.
  ///
  /// In zh, this message translates to:
  /// **'地图'**
  String get mapSection;

  /// No description provided for @useAmap.
  ///
  /// In zh, this message translates to:
  /// **'使用高德地图'**
  String get useAmap;

  /// No description provided for @useAmapHint.
  ///
  /// In zh, this message translates to:
  /// **'卫星凌日地图使用高德地图（国内更详细）；关闭则使用 OpenStreetMap。'**
  String get useAmapHint;

  /// No description provided for @amapConsentTitle.
  ///
  /// In zh, this message translates to:
  /// **'使用高德地图？'**
  String get amapConsentTitle;

  /// No description provided for @amapConsentBody.
  ///
  /// In zh, this message translates to:
  /// **'卫星凌日的地图可以使用高德地图显示。高德地图 SDK 会收集设备信息、网络信息和位置信息，用于显示地图和改进服务，具体见下面的隐私政策。\n\n同意后使用高德地图；不同意则使用 OpenStreetMap。以后可以在“设置”里更改。'**
  String get amapConsentBody;

  /// No description provided for @appPrivacyPolicy.
  ///
  /// In zh, this message translates to:
  /// **'观象隐私政策'**
  String get appPrivacyPolicy;

  /// No description provided for @amapPrivacyPolicy.
  ///
  /// In zh, this message translates to:
  /// **'高德开放平台隐私权政策'**
  String get amapPrivacyPolicy;

  /// No description provided for @amapAgree.
  ///
  /// In zh, this message translates to:
  /// **'同意'**
  String get amapAgree;

  /// No description provided for @amapDecline.
  ///
  /// In zh, this message translates to:
  /// **'不同意'**
  String get amapDecline;

  /// No description provided for @tasksTitle.
  ///
  /// In zh, this message translates to:
  /// **'后台任务'**
  String get tasksTitle;

  /// No description provided for @newTask.
  ///
  /// In zh, this message translates to:
  /// **'提交后台任务'**
  String get newTask;

  /// No description provided for @taskKindLong.
  ///
  /// In zh, this message translates to:
  /// **'长跨度搜索'**
  String get taskKindLong;

  /// No description provided for @taskKindWatch.
  ///
  /// In zh, this message translates to:
  /// **'持续监视'**
  String get taskKindWatch;

  /// No description provided for @taskLongHint.
  ///
  /// In zh, this message translates to:
  /// **'用当前缓存的根数一次搜完。根数只在两周内可靠，更远的结果只能作大致参考，观测前请刷新根数重新确认。'**
  String get taskLongHint;

  /// No description provided for @taskWatchHint.
  ///
  /// In zh, this message translates to:
  /// **'每 4 小时刷新根数，重新搜索接下来 14 天，发现凌日凌月时通知。结果始终基于最新根数。Android 上关闭应用也会运行；其他平台需要保持应用打开。'**
  String get taskWatchHint;

  /// No description provided for @searchDaysLabel.
  ///
  /// In zh, this message translates to:
  /// **'搜索天数'**
  String get searchDaysLabel;

  /// No description provided for @maxRuntimeLabel.
  ///
  /// In zh, this message translates to:
  /// **'最长计算（分钟）'**
  String get maxRuntimeLabel;

  /// No description provided for @watchDaysLabel.
  ///
  /// In zh, this message translates to:
  /// **'监视天数'**
  String get watchDaysLabel;

  /// No description provided for @radiusLabel.
  ///
  /// In zh, this message translates to:
  /// **'范围半径 km'**
  String get radiusLabel;

  /// No description provided for @radiusHint.
  ///
  /// In zh, this message translates to:
  /// **'大于 0 时，也报告中心线在这个半径内经过的凌日凌月（赶到中心线上就能看到）。'**
  String get radiusHint;

  /// No description provided for @stopOnHitLabel.
  ///
  /// In zh, this message translates to:
  /// **'找到凌日凌月就结束'**
  String get stopOnHitLabel;

  /// No description provided for @submit.
  ///
  /// In zh, this message translates to:
  /// **'提交'**
  String get submit;

  /// No description provided for @taskSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'任务已提交，结果会出现在任务历史里'**
  String get taskSubmitted;

  /// No description provided for @notificationDenied.
  ///
  /// In zh, this message translates to:
  /// **'没有通知权限，结果仍会保存在任务历史里'**
  String get notificationDenied;

  /// No description provided for @noTasks.
  ///
  /// In zh, this message translates to:
  /// **'还没有任务'**
  String get noTasks;

  /// No description provided for @noCachedElements.
  ///
  /// In zh, this message translates to:
  /// **'没有可用的根数，请先在卫星页刷新根数'**
  String get noCachedElements;

  /// No description provided for @taskLongName.
  ///
  /// In zh, this message translates to:
  /// **'长跨度搜索 · {days} 天'**
  String taskLongName(int days);

  /// No description provided for @taskWatchName.
  ///
  /// In zh, this message translates to:
  /// **'持续监视 · 至 {until}'**
  String taskWatchName(String until);

  /// No description provided for @taskHitTitle.
  ///
  /// In zh, this message translates to:
  /// **'发现凌日凌月：{satellite}'**
  String taskHitTitle(String satellite);

  /// No description provided for @taskNearbyTitle.
  ///
  /// In zh, this message translates to:
  /// **'{km} km 外可见凌日凌月：{satellite}'**
  String taskNearbyTitle(String satellite, String km);

  /// No description provided for @taskDoneTitle.
  ///
  /// In zh, this message translates to:
  /// **'任务完成：{name}'**
  String taskDoneTitle(String name);

  /// No description provided for @taskTimeoutTitle.
  ///
  /// In zh, this message translates to:
  /// **'任务到时：{name}'**
  String taskTimeoutTitle(String name);

  /// No description provided for @taskDoneBody.
  ///
  /// In zh, this message translates to:
  /// **'命中 {hits} 次，共 {total} 次接近'**
  String taskDoneBody(int hits, int total);

  /// No description provided for @statusPending.
  ///
  /// In zh, this message translates to:
  /// **'排队中'**
  String get statusPending;

  /// No description provided for @statusRunning.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get statusRunning;

  /// No description provided for @statusDone.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get statusDone;

  /// No description provided for @statusTimeout.
  ///
  /// In zh, this message translates to:
  /// **'已到时'**
  String get statusTimeout;

  /// No description provided for @statusCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get statusCancelled;

  /// No description provided for @statusFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败：{error}'**
  String statusFailed(String error);

  /// No description provided for @cancelTask.
  ///
  /// In zh, this message translates to:
  /// **'取消任务'**
  String get cancelTask;

  /// No description provided for @deleteTask.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get deleteTask;

  /// No description provided for @reportTitle.
  ///
  /// In zh, this message translates to:
  /// **'任务报告'**
  String get reportTitle;

  /// No description provided for @reportParams.
  ///
  /// In zh, this message translates to:
  /// **'角距上限 {sep}°，范围半径 {radius} km'**
  String reportParams(String sep, String radius);

  /// No description provided for @reportSearched.
  ///
  /// In zh, this message translates to:
  /// **'已搜索 {done}/{total} 天，计算用时 {seconds} 秒'**
  String reportSearched(String done, String total, String seconds);

  /// No description provided for @reportLastRun.
  ///
  /// In zh, this message translates to:
  /// **'上次搜索 {time}'**
  String reportLastRun(String time);

  /// No description provided for @reportCreated.
  ///
  /// In zh, this message translates to:
  /// **'提交于 {time}'**
  String reportCreated(String time);

  /// No description provided for @reportHits.
  ///
  /// In zh, this message translates to:
  /// **'命中'**
  String get reportHits;

  /// No description provided for @reportOthers.
  ///
  /// In zh, this message translates to:
  /// **'其他接近'**
  String get reportOthers;

  /// No description provided for @hitAtSite.
  ///
  /// In zh, this message translates to:
  /// **'测站可见'**
  String get hitAtSite;

  /// No description provided for @hitNearby.
  ///
  /// In zh, this message translates to:
  /// **'{km} km 外可见'**
  String hitNearby(String km);

  /// No description provided for @beyondTwoWeeks.
  ///
  /// In zh, this message translates to:
  /// **'超过根数两周，仅供参考'**
  String get beyondTwoWeeks;

  /// No description provided for @legalese.
  ///
  /// In zh, this message translates to:
  /// **'天文事件搜索。计算结果仅供参考，观测太阳时务必做好防护。'**
  String get legalese;

  /// No description provided for @navDashboard.
  ///
  /// In zh, this message translates to:
  /// **'看板'**
  String get navDashboard;

  /// No description provided for @navSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get navSearch;

  /// No description provided for @navSatellite.
  ///
  /// In zh, this message translates to:
  /// **'卫星'**
  String get navSatellite;

  /// No description provided for @navSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// No description provided for @themeMode.
  ///
  /// In zh, this message translates to:
  /// **'外观主题'**
  String get themeMode;

  /// No description provided for @themeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeSystem;

  /// No description provided for @themeDeepSpace.
  ///
  /// In zh, this message translates to:
  /// **'深空暗夜'**
  String get themeDeepSpace;

  /// No description provided for @themeAstroRed.
  ///
  /// In zh, this message translates to:
  /// **'夜间红光（保护暗适应）'**
  String get themeAstroRed;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'明亮浅色'**
  String get themeLight;

  /// No description provided for @dashboardTitle.
  ///
  /// In zh, this message translates to:
  /// **'观象 · 近期看点'**
  String get dashboardTitle;

  /// No description provided for @quickExplore.
  ///
  /// In zh, this message translates to:
  /// **'快捷探索'**
  String get quickExplore;

  /// No description provided for @quickEclipses.
  ///
  /// In zh, this message translates to:
  /// **'近期日月食'**
  String get quickEclipses;

  /// No description provided for @quickEclipsesDesc.
  ///
  /// In zh, this message translates to:
  /// **'探索未来几年的日全食、日环食与月全食'**
  String get quickEclipsesDesc;

  /// No description provided for @quickTransits.
  ///
  /// In zh, this message translates to:
  /// **'行星凌日'**
  String get quickTransits;

  /// No description provided for @quickTransitsDesc.
  ///
  /// In zh, this message translates to:
  /// **'水星与金星凌日稀有天象一览'**
  String get quickTransitsDesc;

  /// No description provided for @quickConjunctions.
  ///
  /// In zh, this message translates to:
  /// **'大行星相合'**
  String get quickConjunctions;

  /// No description provided for @quickConjunctionsDesc.
  ///
  /// In zh, this message translates to:
  /// **'金星、木星、土星近距离相合'**
  String get quickConjunctionsDesc;

  /// No description provided for @quickSpaceStation.
  ///
  /// In zh, this message translates to:
  /// **'空间站凌日凌月'**
  String get quickSpaceStation;

  /// No description provided for @quickSpaceStationDesc.
  ///
  /// In zh, this message translates to:
  /// **'天宫与国际空间站地面中心线预报'**
  String get quickSpaceStationDesc;

  /// No description provided for @currentLocation.
  ///
  /// In zh, this message translates to:
  /// **'观测地'**
  String get currentLocation;

  /// No description provided for @curatedHighlights.
  ///
  /// In zh, this message translates to:
  /// **'近期天象'**
  String get curatedHighlights;

  /// No description provided for @upcomingHint.
  ///
  /// In zh, this message translates to:
  /// **'未来一年多的日月食和亮行星相合（角距 ≤ 3°），由本机星历计算；日月食为全球情况，不含肉眼几乎看不出的半影月食。'**
  String get upcomingHint;

  /// No description provided for @upcomingLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在计算…'**
  String get upcomingLoading;

  /// No description provided for @upcomingNone.
  ///
  /// In zh, this message translates to:
  /// **'没有找到'**
  String get upcomingNone;

  /// No description provided for @lunarPhasesTitle.
  ///
  /// In zh, this message translates to:
  /// **'食相'**
  String get lunarPhasesTitle;

  /// No description provided for @lunarDurationTotal.
  ///
  /// In zh, this message translates to:
  /// **'全食 {duration}'**
  String lunarDurationTotal(String duration);

  /// No description provided for @lunarDurationUmbral.
  ///
  /// In zh, this message translates to:
  /// **'本影食 {duration}'**
  String lunarDurationUmbral(String duration);

  /// No description provided for @lunarDurationPenumbral.
  ///
  /// In zh, this message translates to:
  /// **'半影食 {duration}'**
  String lunarDurationPenumbral(String duration);

  /// No description provided for @durationHm.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小时 {minutes} 分'**
  String durationHm(int hours, int minutes);

  /// No description provided for @durationM.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String durationM(int minutes);

  /// No description provided for @lunarSaros.
  ///
  /// In zh, this message translates to:
  /// **'沙罗序列 {saros}'**
  String lunarSaros(String saros);

  /// No description provided for @lunarHorizonHint.
  ///
  /// In zh, this message translates to:
  /// **'斜线部分月亮在地平线以下'**
  String get lunarHorizonHint;

  /// No description provided for @lunarLocalTitle.
  ///
  /// In zh, this message translates to:
  /// **'在你所在地'**
  String get lunarLocalTitle;

  /// No description provided for @lunarTimesTitle.
  ///
  /// In zh, this message translates to:
  /// **'各食相时刻'**
  String get lunarTimesTitle;

  /// No description provided for @lunarVisFull.
  ///
  /// In zh, this message translates to:
  /// **'全程可见'**
  String get lunarVisFull;

  /// No description provided for @lunarVisRises.
  ///
  /// In zh, this message translates to:
  /// **'月出时月食已经开始'**
  String get lunarVisRises;

  /// No description provided for @lunarVisSets.
  ///
  /// In zh, this message translates to:
  /// **'月落时月食还没结束'**
  String get lunarVisSets;

  /// No description provided for @lunarVisRisesAndSets.
  ///
  /// In zh, this message translates to:
  /// **'食中月亮有出有落，只能看到一部分'**
  String get lunarVisRisesAndSets;

  /// No description provided for @lunarVisHidden.
  ///
  /// In zh, this message translates to:
  /// **'月亮在地平线以下，看不到'**
  String get lunarVisHidden;

  /// No description provided for @lunarTotalityVisible.
  ///
  /// In zh, this message translates to:
  /// **'全食阶段月亮在地平线以上'**
  String get lunarTotalityVisible;

  /// No description provided for @lunarTotalityHidden.
  ///
  /// In zh, this message translates to:
  /// **'全食阶段月亮在地平线以下'**
  String get lunarTotalityHidden;

  /// No description provided for @lunarMoonrise.
  ///
  /// In zh, this message translates to:
  /// **'月出 {time}'**
  String lunarMoonrise(String time);

  /// No description provided for @lunarMoonset.
  ///
  /// In zh, this message translates to:
  /// **'月落 {time}'**
  String lunarMoonset(String time);

  /// No description provided for @lunarColPhase.
  ///
  /// In zh, this message translates to:
  /// **'食相'**
  String get lunarColPhase;

  /// No description provided for @lunarColTime.
  ///
  /// In zh, this message translates to:
  /// **'时刻（{zone}）'**
  String lunarColTime(String zone);

  /// No description provided for @lunarColAlt.
  ///
  /// In zh, this message translates to:
  /// **'高度'**
  String get lunarColAlt;

  /// No description provided for @lunarColAz.
  ///
  /// In zh, this message translates to:
  /// **'方位'**
  String get lunarColAz;

  /// No description provided for @lunarColSky.
  ///
  /// In zh, this message translates to:
  /// **'天色'**
  String get lunarColSky;

  /// No description provided for @lunarSkyDay.
  ///
  /// In zh, this message translates to:
  /// **'白天'**
  String get lunarSkyDay;

  /// No description provided for @lunarSkyTwilight.
  ///
  /// In zh, this message translates to:
  /// **'晨昏'**
  String get lunarSkyTwilight;

  /// No description provided for @lunarSkyNight.
  ///
  /// In zh, this message translates to:
  /// **'夜间'**
  String get lunarSkyNight;

  /// No description provided for @compassPoints.
  ///
  /// In zh, this message translates to:
  /// **'北 北东北 东北 东东北 东 东东南 东南 南东南 南 南西南 西南 西西南 西 西西北 西北 北西北'**
  String get compassPoints;

  /// No description provided for @lunarNeedsLocation.
  ///
  /// In zh, this message translates to:
  /// **'设置观测地后，这里显示每个食相时月亮的高度和方向，以及在你那里能不能看到'**
  String get lunarNeedsLocation;

  /// No description provided for @lunarStateBefore.
  ///
  /// In zh, this message translates to:
  /// **'月食还没开始'**
  String get lunarStateBefore;

  /// No description provided for @lunarStatePenumbral.
  ///
  /// In zh, this message translates to:
  /// **'半影食中'**
  String get lunarStatePenumbral;

  /// No description provided for @lunarStatePartial.
  ///
  /// In zh, this message translates to:
  /// **'偏食中'**
  String get lunarStatePartial;

  /// No description provided for @lunarStateTotal.
  ///
  /// In zh, this message translates to:
  /// **'全食中'**
  String get lunarStateTotal;

  /// No description provided for @lunarStateAfter.
  ///
  /// In zh, this message translates to:
  /// **'月食已结束'**
  String get lunarStateAfter;

  /// No description provided for @lunarMoonAlt.
  ///
  /// In zh, this message translates to:
  /// **'月亮高度 {alt}°'**
  String lunarMoonAlt(int alt);

  /// No description provided for @lunarMoonDown.
  ///
  /// In zh, this message translates to:
  /// **'月亮在地平线下'**
  String get lunarMoonDown;

  /// No description provided for @lunarSliderLabel.
  ///
  /// In zh, this message translates to:
  /// **'时刻'**
  String get lunarSliderLabel;

  /// No description provided for @lunarDiagramCaption.
  ///
  /// In zh, this message translates to:
  /// **'北在上、东在左（抬头所见）。外圈是地球的半影，内圈是本影；小圆是月球在各接触时刻（P1 半影食始、U1 初亏、U2 食既、U3 生光、U4 复圆、P4 半影食终）的位置，箭头是月球运动的方向。拖动滑块或点下面的食相，看月球在那一刻的位置和样子。'**
  String get lunarDiagramCaption;

  /// No description provided for @lunarDanjonNote.
  ///
  /// In zh, this message translates to:
  /// **'月面模拟只是示意：全食时月亮有多暗、偏红还是偏橙，取决于地球大气里的云和火山灰，没法预报（天文上用丹戎等级 L0–L4 记录，L0 几乎看不见，L4 是明亮的橙红色）。'**
  String get lunarDanjonNote;

  /// No description provided for @lunarMapTitle.
  ///
  /// In zh, this message translates to:
  /// **'全球可见区域'**
  String get lunarMapTitle;

  /// No description provided for @lunarMapFull.
  ///
  /// In zh, this message translates to:
  /// **'全程可见'**
  String get lunarMapFull;

  /// No description provided for @lunarMapRises.
  ///
  /// In zh, this message translates to:
  /// **'月出时已开始'**
  String get lunarMapRises;

  /// No description provided for @lunarMapSets.
  ///
  /// In zh, this message translates to:
  /// **'月落时未结束'**
  String get lunarMapSets;

  /// No description provided for @lunarMapHidden.
  ///
  /// In zh, this message translates to:
  /// **'看不到'**
  String get lunarMapHidden;

  /// No description provided for @lunarMapCaption.
  ///
  /// In zh, this message translates to:
  /// **'按本影食（初亏到复圆）划分，半影月食按半影食始到半影食终。曲线是各接触时刻月亮正好在地平线上的地方，★ 是食甚时月亮在天顶的地方，圆点是你的观测地。按地心计算，没有计入大气折射和视差，边界附近可能差 1° 左右。'**
  String get lunarMapCaption;

  /// No description provided for @lunarTipsTitle.
  ///
  /// In zh, this message translates to:
  /// **'观测与拍摄'**
  String get lunarTipsTitle;

  /// No description provided for @lunarTipEyes.
  ///
  /// In zh, this message translates to:
  /// **'月食直接用眼睛看就很安全，不需要任何滤光片。双筒望远镜或小望远镜里，月面的颜色和明暗变化更明显。'**
  String get lunarTipEyes;

  /// No description provided for @lunarTipPhoto.
  ///
  /// In zh, this message translates to:
  /// **'拍摄参考：偏食阶段月亮的亮部仍然很亮，可以从 ISO 100、1/250 s、f/8 开始试；全食阶段暗很多，可以从 ISO 800–1600、1–4 s 开始，要用三脚架，焦距较长时最好用赤道仪跟踪，否则月亮会拖线。'**
  String get lunarTipPhoto;

  /// No description provided for @lunarTipBracket.
  ///
  /// In zh, this message translates to:
  /// **'全食阶段的亮度没法预报，最好每隔几分钟换几档曝光多拍几张；初亏前先拍一张没被遮住的满月，方便对比。'**
  String get lunarTipBracket;

  /// No description provided for @lunarTipSolar.
  ///
  /// In zh, this message translates to:
  /// **'注意：日食不一样，看日食必须用符合 ISO 12312-2 的滤光膜或日食眼镜。'**
  String get lunarTipSolar;

  /// No description provided for @solarKindTotal.
  ///
  /// In zh, this message translates to:
  /// **'全食'**
  String get solarKindTotal;

  /// No description provided for @solarKindAnnular.
  ///
  /// In zh, this message translates to:
  /// **'环食'**
  String get solarKindAnnular;

  /// No description provided for @solarKindPartial.
  ///
  /// In zh, this message translates to:
  /// **'偏食'**
  String get solarKindPartial;

  /// No description provided for @solarVisFull.
  ///
  /// In zh, this message translates to:
  /// **'全程可见'**
  String get solarVisFull;

  /// No description provided for @solarVisRises.
  ///
  /// In zh, this message translates to:
  /// **'日出时日食已经开始'**
  String get solarVisRises;

  /// No description provided for @solarVisSets.
  ///
  /// In zh, this message translates to:
  /// **'日落时日食还没结束'**
  String get solarVisSets;

  /// No description provided for @solarVisRisesAndSets.
  ///
  /// In zh, this message translates to:
  /// **'食中太阳有升有落，只能看到一部分'**
  String get solarVisRisesAndSets;

  /// No description provided for @solarVisHidden.
  ///
  /// In zh, this message translates to:
  /// **'日食发生时太阳在地平线下，看不到'**
  String get solarVisHidden;

  /// No description provided for @solarVisNone.
  ///
  /// In zh, this message translates to:
  /// **'这里看不到这次日食'**
  String get solarVisNone;

  /// No description provided for @solarCentralDuration.
  ///
  /// In zh, this message translates to:
  /// **'{kind} {duration}'**
  String solarCentralDuration(String kind, String duration);

  /// No description provided for @solarMagnitude.
  ///
  /// In zh, this message translates to:
  /// **'食分 {value}'**
  String solarMagnitude(String value);

  /// No description provided for @solarObscuration.
  ///
  /// In zh, this message translates to:
  /// **'食面积 {percent}%'**
  String solarObscuration(String percent);

  /// No description provided for @durationMs.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分 {seconds} 秒'**
  String durationMs(int minutes, int seconds);

  /// No description provided for @solarInsidePath.
  ///
  /// In zh, this message translates to:
  /// **'你在{kind}带内，离中心线 {km} km'**
  String solarInsidePath(String kind, int km);

  /// No description provided for @solarOutsidePath.
  ///
  /// In zh, this message translates to:
  /// **'中心线在你的{dir}方，最近 {km} km'**
  String solarOutsidePath(String dir, int km);

  /// No description provided for @solarNeedsLocation.
  ///
  /// In zh, this message translates to:
  /// **'设置观测地后，这里显示你那里看到的日食：类型、食分、各食相时刻，以及太阳的高度和方向'**
  String get solarNeedsLocation;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
