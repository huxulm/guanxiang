// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Guanxiang';

  @override
  String get searchTitle => 'Guanxiang';

  @override
  String get loadingEphemeris => 'Loading ephemeris…';

  @override
  String ephemerisLoadFailed(String error) {
    return 'Failed to load the ephemeris: $error';
  }

  @override
  String get tonightTitle => 'Tonight';

  @override
  String get tonightSunset => 'Sunset';

  @override
  String get tonightDusk => 'Dark';

  @override
  String get tonightDawn => 'Dawn';

  @override
  String get tonightSunrise => 'Sunrise';

  @override
  String get tonightMoonrise => 'Moonrise';

  @override
  String get tonightMoonset => 'Moonset';

  @override
  String tonightDark(int hours, int minutes) {
    return 'Fully dark for $hours h $minutes min';
  }

  @override
  String get tonightDarkHint =>
      'Dark and dawn mean astronomical twilight: the Sun 18° below the horizon';

  @override
  String get tonightPolarDay => 'Midnight sun: the Sun does not set';

  @override
  String get tonightPolarNight => 'Polar night: the Sun does not rise';

  @override
  String get tonightWhiteNight => 'It never gets fully dark tonight';

  @override
  String tonightIllumination(int percent) {
    return '$percent% lit';
  }

  @override
  String tonightNextFull(String when) {
    return 'Full moon: $when';
  }

  @override
  String tonightNextNew(String when) {
    return 'New moon: $when';
  }

  @override
  String get tonightNeedsLocation =>
      'Set your location to see tonight\'s sunset, moonrise and moon phase here';

  @override
  String get tonightSetLocation => 'Set location';

  @override
  String get diagramTitle => 'Diagram';

  @override
  String get diagramLunarCaption =>
      'North up, east left (as seen in the sky). The outer circle is Earth\'s penumbra, the inner one the umbra. The small circles show the Moon at each contact (P1 penumbral begins, U1 partial begins, U2 total begins, U3 total ends, U4 partial ends, P4 penumbral ends) and at greatest eclipse; the arrow shows its motion.';

  @override
  String get diagramSolarCaption =>
      'Earth seen from the Sun, north up. The solid line is the path of the shadow axis (local times marked); the dashed circle is the penumbra at greatest eclipse, inside which the eclipse is partial. The black dot is the umbra: where it falls on Earth, the eclipse is total.';

  @override
  String get diagramSolarCaptionAnnular =>
      'Earth seen from the Sun, north up. The solid line is the path of the shadow axis (local times marked); the dashed circle is the penumbra at greatest eclipse, inside which the eclipse is partial. The black dot is the antumbra: where it falls on Earth, the eclipse is annular.';

  @override
  String get today => 'Today';

  @override
  String get tomorrow => 'Tomorrow';

  @override
  String inDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'in $n days',
      one: 'in 1 day',
    );
    return '$_temp0';
  }

  @override
  String get subtleHint => 'barely visible';

  @override
  String get copyDetails => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get searchIdle => 'Choose, then tap Search';

  @override
  String get yearsNext10 => 'Next 10 years';

  @override
  String get yearsNext30 => 'Next 30 years';

  @override
  String yearsTo2100(int year) {
    return 'Until $year';
  }

  @override
  String yearsAll(int from, int to) {
    return 'All $from–$to';
  }

  @override
  String get kindTransit => 'Transit';

  @override
  String get kindConjunction => 'Conjunction';

  @override
  String get kindOpposition => 'Opposition';

  @override
  String get kindAppulse => 'Closest approach';

  @override
  String get kindSolarEclipse => 'Solar eclipse';

  @override
  String get kindLunarEclipse => 'Lunar eclipse';

  @override
  String get kindOccultation => 'Occultation';

  @override
  String get occAll => 'All (planets and 550 bright stars)';

  @override
  String get occPlanets => 'All planets';

  @override
  String get occStars => 'All bright stars';

  @override
  String get starSpica => 'Spica';

  @override
  String get starAntares => 'Antares';

  @override
  String get starRegulus => 'Regulus';

  @override
  String get starAldebaran => 'Aldebaran';

  @override
  String get starAlcyone => 'Alcyone (Pleiades)';

  @override
  String get occultedTarget => 'Target';

  @override
  String get eclipseHint =>
      'Eclipses are computed globally; turn on “Visible from my location” for local circumstances';

  @override
  String get planet => 'Planet';

  @override
  String get mercuryAndVenus => 'Mercury and Venus';

  @override
  String get bodyA => 'Body A';

  @override
  String get bodyB => 'Body B';

  @override
  String get maxSeparation => 'Max sep. °';

  @override
  String get startYear => 'From year';

  @override
  String get endYear => 'End year';

  @override
  String get localOnly => 'Visible from my location';

  @override
  String get localOnlyHint =>
      'Target above the horizon; except for transits, the Sun must also be below −6°';

  @override
  String get latitude => 'Latitude °';

  @override
  String get longitude => 'Longitude ° (E+)';

  @override
  String get height => 'Height m';

  @override
  String get search => 'Search';

  @override
  String get cancel => 'Cancel';

  @override
  String get satelliteTooltip => 'Satellite transits';

  @override
  String get aboutTooltip => 'About & licences';

  @override
  String get noResults => 'No results';

  @override
  String get searching => 'Searching…';

  @override
  String searchFinished(int count, int ms) {
    return '$count events in $ms ms';
  }

  @override
  String searchCancelled(int count, int ms) {
    return 'Cancelled: $count events in $ms ms';
  }

  @override
  String searchFailed(String error) {
    return 'Search failed: $error';
  }

  @override
  String get searchFailedShort => 'Search failed';

  @override
  String get invalidObserver => 'Invalid observer coordinates';

  @override
  String detailFooter(String jd) {
    return 'Times are UTC. TT Julian date $jd.';
  }

  @override
  String get enterYears => 'Enter the start and end years';

  @override
  String get endBeforeStart => 'The end year can\'t be before the start year';

  @override
  String yearsOutOfRange(int from, int to) {
    return 'The built-in ephemeris covers $from–$to only; please search within that range';
  }

  @override
  String get satTitle => 'Satellite transits';

  @override
  String get issName => 'ISS';

  @override
  String get cssName => 'Tiangong';

  @override
  String cacheOpenFailed(String error) {
    return 'Failed to open the elements cache: $error';
  }

  @override
  String get enterNorad => 'Enter a NORAD catalogue number';

  @override
  String get invalidInput => 'Invalid input';

  @override
  String get noElementsYet => 'No orbital elements yet; refresh first';

  @override
  String get computing => 'Computing…';

  @override
  String satSummary(int count, int transits, int ms) {
    return '$count approaches ($transits transits) in $ms ms';
  }

  @override
  String get noElements => 'No elements';

  @override
  String cacheEpoch(String epoch) {
    return 'Epoch $epoch UTC';
  }

  @override
  String downloadedAgo(String ago) {
    return ', downloaded $ago';
  }

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int n) {
    return '$n min ago';
  }

  @override
  String hoursAgo(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String daysAgo(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get hasPrevious => ', previous elements available';

  @override
  String get noradNumber => 'NORAD no.';

  @override
  String get addSatellite => 'Add satellite';

  @override
  String get refreshElements => 'Refresh elements';

  @override
  String get days => 'Days';

  @override
  String get startTime => 'Start (local time)';

  @override
  String get startNow => 'Now';

  @override
  String get resetToNow => 'Back to now';

  @override
  String get osmAttribution => '© OpenStreetMap contributors';

  @override
  String centerlineHintSun(String width) {
    return 'The red line (orange if there is no transit) is the centre line: the ground track 10 s either side of closest approach. From the line, the satellite crosses the centre of the Sun. Visibility half-width ≈ $width km.';
  }

  @override
  String centerlineHintMoon(String width) {
    return 'The red line (orange if there is no transit) is the centre line: the ground track 10 s either side of closest approach. From the line, the satellite crosses the centre of the Moon. Visibility half-width ≈ $width km.';
  }

  @override
  String get refreshBlocked =>
      'An earlier request failed; downloads are paused and cached elements are used';

  @override
  String refreshRecent(int minutes) {
    return 'Downloaded $minutes min ago; CelesTrak updates every 2 hours, using the cache';
  }

  @override
  String refreshNetwork(String error) {
    return '$error; using cached elements';
  }

  @override
  String refreshHttp(int status) {
    return 'CelesTrak returned $status; downloads paused for 2 hours';
  }

  @override
  String refreshInvalid(int id, String hint) {
    return 'No elements for $id: $hint';
  }

  @override
  String refreshUpdated(String epoch) {
    return 'Updated, epoch $epoch';
  }

  @override
  String refreshUnchanged(String epoch) {
    return 'Unchanged (epoch $epoch)';
  }

  @override
  String errInternal(String message) {
    return 'Internal error: $message';
  }

  @override
  String get errNetwork => 'No network connection';

  @override
  String get errTimeout => 'The request timed out; please try again later';

  @override
  String errHttp(String message) {
    return 'Network request failed: $message';
  }

  @override
  String errFormat(String message) {
    return 'Invalid data: $message';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get locationSection => 'Observer location';

  @override
  String get observerLocation => 'Observer location';

  @override
  String get locationGps => 'GPS';

  @override
  String get locationManual => 'Manual';

  @override
  String get locateNow => 'Locate now';

  @override
  String get locating => 'Locating…';

  @override
  String gpsFixAt(String time) {
    return 'Fixed at $time';
  }

  @override
  String get gpsNoFix =>
      'No fix yet. Tap “Locate now”, or it will be located when you search';

  @override
  String get gpsLocateOnSearch => 'located when you search';

  @override
  String get locationPrivacy =>
      'Location is only requested when you search for locally visible events or satellite transits, or tap “Locate now”; a fix less than 10 minutes old is reused. It stays on this device and is never uploaded.';

  @override
  String get locServiceOff =>
      'Location services are off. Turn them on or use a manual location';

  @override
  String get locDenied =>
      'Location permission denied. Allow it or use a manual location';

  @override
  String get locDeniedForever =>
      'Location permission was denied. Allow it in system settings or use a manual location';

  @override
  String get locTimeout =>
      'Location timed out. Try again in the open or use a manual location';

  @override
  String locUnavailable(String detail) {
    return 'Location unavailable: $detail';
  }

  @override
  String get openSystemSettings => 'Open system settings';

  @override
  String usingOldFix(String error, String time) {
    return '$error; using the fix from $time';
  }

  @override
  String viewResults(int count) {
    return 'View results ($count)';
  }

  @override
  String get resultsTitle => 'Results';

  @override
  String get mapSection => 'Map';

  @override
  String get useAmap => 'Use AMap (Gaode)';

  @override
  String get useAmapHint =>
      'Show satellite transit maps with AMap (more detailed in China); when off, OpenStreetMap is used.';

  @override
  String get amapConsentTitle => 'Use AMap?';

  @override
  String get amapConsentBody =>
      'Satellite transit maps can be shown with AMap (Gaode). The AMap SDK collects device, network and location information to display maps and improve its service; see the privacy policies below.\n\nIf you agree, AMap is used; otherwise OpenStreetMap is used. You can change this later in Settings.';

  @override
  String get appPrivacyPolicy => 'Guanxiang privacy policy';

  @override
  String get amapPrivacyPolicy => 'AMap Open Platform privacy policy';

  @override
  String get amapAgree => 'Agree';

  @override
  String get amapDecline => 'Decline';

  @override
  String get tasksTitle => 'Background tasks';

  @override
  String get newTask => 'New background task';

  @override
  String get taskKindLong => 'Long search';

  @override
  String get taskKindWatch => 'Watch';

  @override
  String get taskLongHint =>
      'Searches the whole span with the elements cached now. Elements are reliable for about two weeks; later results are only rough guides, so refresh and check again before observing.';

  @override
  String get taskWatchHint =>
      'Every 4 hours, refreshes the elements and searches the next 14 days; notifies you when a transit appears. Results always use the latest elements. On Android it keeps running when the app is closed; elsewhere keep the app open.';

  @override
  String get searchDaysLabel => 'Days to search';

  @override
  String get maxRuntimeLabel => 'Max compute (min)';

  @override
  String get watchDaysLabel => 'Days to watch';

  @override
  String get radiusLabel => 'Radius km';

  @override
  String get radiusHint =>
      'When above 0, also reports transits whose centre line passes within this radius (go to the centre line to see them).';

  @override
  String get stopOnHitLabel => 'Stop at the first transit';

  @override
  String get submit => 'Submit';

  @override
  String get taskSubmitted =>
      'Task submitted; results will appear in the task history';

  @override
  String get notificationDenied =>
      'Notifications are not allowed; results are still saved in the task history';

  @override
  String get noTasks => 'No tasks yet';

  @override
  String get noCachedElements =>
      'No orbital elements available; refresh them on the satellite page first';

  @override
  String taskLongName(int days) {
    return 'Long search · $days days';
  }

  @override
  String taskWatchName(String until) {
    return 'Watch · until $until';
  }

  @override
  String taskHitTitle(String satellite) {
    return 'Transit found: $satellite';
  }

  @override
  String taskNearbyTitle(String satellite, String km) {
    return 'Transit visible $km km away: $satellite';
  }

  @override
  String taskDoneTitle(String name) {
    return 'Task finished: $name';
  }

  @override
  String taskTimeoutTitle(String name) {
    return 'Task time limit reached: $name';
  }

  @override
  String taskDoneBody(int hits, int total) {
    return '$hits hits out of $total approaches';
  }

  @override
  String get statusPending => 'Queued';

  @override
  String get statusRunning => 'Running';

  @override
  String get statusDone => 'Finished';

  @override
  String get statusTimeout => 'Time limit reached';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String statusFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get cancelTask => 'Cancel task';

  @override
  String get deleteTask => 'Delete';

  @override
  String get reportTitle => 'Task report';

  @override
  String reportParams(String sep, String radius) {
    return 'Max separation $sep°, radius $radius km';
  }

  @override
  String reportSearched(String done, String total, String seconds) {
    return 'Searched $done/$total days in $seconds s of computing';
  }

  @override
  String reportLastRun(String time) {
    return 'Last searched $time';
  }

  @override
  String reportCreated(String time) {
    return 'Submitted $time';
  }

  @override
  String get reportHits => 'Hits';

  @override
  String get reportOthers => 'Other approaches';

  @override
  String get hitAtSite => 'Visible here';

  @override
  String hitNearby(String km) {
    return 'Visible $km km away';
  }

  @override
  String get beyondTwoWeeks =>
      'More than two weeks from the elements; rough guide only';

  @override
  String get legalese =>
      'Astronomical event search. Results are for reference only. Always protect your eyes when observing the Sun.';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navSearch => 'Search';

  @override
  String get navSatellite => 'Satellites';

  @override
  String get navSettings => 'Settings';

  @override
  String get themeMode => 'Theme';

  @override
  String get themeSystem => 'Follow system';

  @override
  String get themeDeepSpace => 'Deep space dark';

  @override
  String get themeAstroRed => 'Astro red (Night vision)';

  @override
  String get themeLight => 'Light';

  @override
  String get dashboardTitle => 'Guanxiang · Highlights';

  @override
  String get quickExplore => 'Quick Explore';

  @override
  String get quickEclipses => 'Upcoming Eclipses';

  @override
  String get quickEclipsesDesc => 'Solar & lunar eclipses in the coming years';

  @override
  String get quickTransits => 'Planetary Transits';

  @override
  String get quickTransitsDesc => 'Rare Mercury & Venus transits';

  @override
  String get quickConjunctions => 'Major Conjunctions';

  @override
  String get quickConjunctionsDesc => 'Close approaches of bright planets';

  @override
  String get quickSpaceStation => 'Space Station Transits';

  @override
  String get quickSpaceStationDesc => 'CSS & ISS solar and lunar transit paths';

  @override
  String get currentLocation => 'Observation Site';

  @override
  String get curatedHighlights => 'Upcoming events';

  @override
  String get upcomingHint =>
      'Eclipses and close pairings of bright planets (within 3°) over the next year or so, computed on this device. Eclipses are global; penumbral lunar eclipses, which are barely visible, are left out.';

  @override
  String get upcomingLoading => 'Computing…';

  @override
  String get upcomingNone => 'Nothing found';

  @override
  String get lunarPhasesTitle => 'Eclipse phases';

  @override
  String lunarDurationTotal(String duration) {
    return 'Totality $duration';
  }

  @override
  String lunarDurationUmbral(String duration) {
    return 'Umbral $duration';
  }

  @override
  String lunarDurationPenumbral(String duration) {
    return 'Penumbral $duration';
  }

  @override
  String durationHm(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String durationM(int minutes) {
    return '$minutes min';
  }

  @override
  String lunarSaros(String saros) {
    return 'Saros $saros';
  }

  @override
  String get lunarHorizonHint => 'Hatched: the Moon is below the horizon';

  @override
  String get lunarLocalTitle => 'From your location';

  @override
  String get lunarTimesTitle => 'Phase times';

  @override
  String get lunarVisFull => 'Visible from start to end';

  @override
  String get lunarVisRises => 'The Moon rises with the eclipse under way';

  @override
  String get lunarVisSets => 'The Moon sets before the eclipse ends';

  @override
  String get lunarVisRisesAndSets =>
      'The Moon rises and sets during the eclipse; only part is visible';

  @override
  String get lunarVisHidden => 'Not visible: the Moon is below the horizon';

  @override
  String get lunarTotalityVisible =>
      'The Moon is above the horizon during totality';

  @override
  String get lunarTotalityHidden =>
      'The Moon is below the horizon during totality';

  @override
  String lunarMoonrise(String time) {
    return 'Moonrise $time';
  }

  @override
  String lunarMoonset(String time) {
    return 'Moonset $time';
  }

  @override
  String get lunarColPhase => 'Phase';

  @override
  String lunarColTime(String zone) {
    return 'Time ($zone)';
  }

  @override
  String get lunarColAlt => 'Alt';

  @override
  String get lunarColAz => 'Az';

  @override
  String get lunarColSky => 'Sky';

  @override
  String get lunarSkyDay => 'Day';

  @override
  String get lunarSkyTwilight => 'Twilight';

  @override
  String get lunarSkyNight => 'Night';

  @override
  String get compassPoints =>
      'N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW';

  @override
  String get lunarNeedsLocation =>
      'Set your location to see the Moon\'s altitude and direction at each phase, and whether the eclipse is visible from there';

  @override
  String get lunarStateBefore => 'Not started yet';

  @override
  String get lunarStatePenumbral => 'Penumbral phase';

  @override
  String get lunarStatePartial => 'Partial phase';

  @override
  String get lunarStateTotal => 'Totality';

  @override
  String get lunarStateAfter => 'Eclipse over';

  @override
  String lunarMoonAlt(int alt) {
    return 'Moon altitude $alt°';
  }

  @override
  String get lunarMoonDown => 'Moon below the horizon';

  @override
  String get lunarSliderLabel => 'Time';

  @override
  String get lunarDiagramCaption =>
      'North up, east left (as seen in the sky). The outer circle is Earth\'s penumbra, the inner one the umbra. The small circles show the Moon at each contact (P1 penumbral begins, U1 partial begins, U2 total begins, U3 total ends, U4 partial ends, P4 penumbral ends); the arrow shows its motion. Drag the slider or tap a phase to see where the Moon is and how it looks at that moment.';

  @override
  String get lunarDanjonNote =>
      'The simulated Moon is only a guide: how dark and how red the Moon looks during totality depends on clouds and volcanic dust in Earth\'s atmosphere and cannot be predicted (observers rate it on the Danjon scale, from L0, nearly invisible, to L4, bright copper-orange).';
}
