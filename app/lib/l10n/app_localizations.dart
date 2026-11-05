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

  /// No description provided for @ephemerisLoaded.
  ///
  /// In zh, this message translates to:
  /// **'星历加载 {ms} ms'**
  String ephemerisLoaded(int ms);

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
  /// **'结束年（不含）'**
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

  /// No description provided for @endAfterStart.
  ///
  /// In zh, this message translates to:
  /// **'结束年份必须晚于起始年份'**
  String get endAfterStart;

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
  /// **'，{minutes} 分钟前下载'**
  String downloadedAgo(int minutes);

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

  /// No description provided for @searchFromNow.
  ///
  /// In zh, this message translates to:
  /// **'从现在起搜索'**
  String get searchFromNow;

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

  /// No description provided for @legalese.
  ///
  /// In zh, this message translates to:
  /// **'天文事件搜索。计算结果仅供参考，观测太阳时务必做好防护。'**
  String get legalese;
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
