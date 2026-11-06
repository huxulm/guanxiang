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
  String ephemerisLoaded(int ms) {
    return 'Ready ($ms ms)';
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
  String get endYear => 'To year (excl.)';

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
  String get endAfterStart => 'The end year must be after the start year';

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
  String downloadedAgo(int minutes) {
    return ', downloaded $minutes min ago';
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
  String get legalese =>
      'Astronomical event search. Results are for reference only. Always protect your eyes when observing the Sun.';
}
