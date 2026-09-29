import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const bg = Color(0xFF070A12);
const panel = Color(0xFF0D1422);
const panel2 = Color(0xFF111A2B);
const card = Color(0xFF10192A);
const line = Color(0xFF1F2B41);
const muted = Color(0xFF8290AA);
const text = Color(0xFFEEF3FF);
const accent = Color(0xFF8B5CF6);
const pink = Color(0xFFEC4899);
const green = Color(0xFF31D07D);
const gold = Color(0xFFF5C96B);

String s(dynamic v) => v?.toString() ?? '';
String safeTitle(Map<String, dynamic> m) {
  final t = (m['title'] as Map?)?.cast<String, dynamic>() ?? {};
  return s(t['english']).isNotEmpty ? s(t['english']) : (s(t['romaji']).isNotEmpty ? s(t['romaji']) : s(t['native']));
}
String posterUrl(Map<String, dynamic> m) => s((m['coverImage'] as Map?)?['extraLarge'] ?? (m['coverImage'] as Map?)?['large'] ?? (m['coverImage'] as Map?)?['medium']);
String formatLabel(String format) => format == 'MOVIE' ? 'Movie' : (format.isEmpty ? 'TV' : format);
int effectiveTotal(Map<String, dynamic> m, LibraryEntry? x) {
  final n = int.tryParse(s(m['episodes'])) ?? 0;
  final next = int.tryParse(s((m['nextAiringEpisode'] as Map?)?['episode'])) ?? 0;
  return n > 0 ? n : (next > 1 ? next - 1 : (x?.total ?? 0));
}

class LibraryEntry {
  int id;
  String title;
  String poster;
  int total;
  int duration;
  String status;
  List<int> watched;
  int nextAiring;
  String airingStatus;
  bool mature;
  int updated;
  LibraryEntry({required this.id, required this.title, required this.poster, this.total = 0, this.duration = 24, this.status = 'WATCHING', List<int>? watched, this.nextAiring = 0, this.airingStatus = '', this.mature = false, this.updated = 0}) : watched = watched ?? [];
  double get progress => total > 0 ? min(100, watched.length / total * 100) : 0;
  int get watchMinutes => watched.length * max(1, duration);
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'poster': poster, 'total': total, 'duration': duration, 'status': status, 'watched': watched, 'nextAiring': nextAiring, 'airingStatus': airingStatus, 'mature': mature, 'updated': updated};
  factory LibraryEntry.fromJson(Map<String, dynamic> j) => LibraryEntry(id: int.tryParse(s(j['id'])) ?? 0, title: s(j['title']), poster: s(j['poster']), total: int.tryParse(s(j['total'])) ?? 0, duration: int.tryParse(s(j['duration'])) ?? 24, status: s(j['status']).isEmpty ? 'WATCHING' : s(j['status']), watched: (j['watched'] as List?)?.map((e) => int.tryParse(s(e)) ?? 0).where((e) => e > 0).toList() ?? [], nextAiring: int.tryParse(s(j['nextAiring'])) ?? 0, airingStatus: s(j['airingStatus']), mature: j['mature'] == true, updated: int.tryParse(s(j['updated'])) ?? 0);
}

class AniListApi {
  static const endpoint = 'https://graphql.anilist.co';
  static const catalogQuery = r'''query($page:Int,$perPage:Int,$search:String,$genre:String,$format:MediaFormat,$status:MediaStatus,$year:Int,$sort:[MediaSort]){Page(page:$page,perPage:$perPage){pageInfo{hasNextPage,total}media(type:ANIME,search:$search,genre:$genre,format:$format,status:$status,seasonYear:$year,sort:$sort,isAdult:false){id,title{romaji english native},coverImage{extraLarge large medium},bannerImage,description(asHtml:false),episodes,duration,status,format,startDate{year month day},endDate{year month day},genres,tags{name isAdult},averageScore,popularity,favourites,isAdult,nextAiringEpisode{episode airingAt},season,seasonYear,studios(isMain:true){nodes{name}}}}}''';
  static const matureCatalogQuery = r'''query($page:Int,$perPage:Int,$search:String,$genre:String,$sort:[MediaSort]){Page(page:$page,perPage:$perPage){pageInfo{hasNextPage,total}media(type:ANIME,search:$search,genre:$genre,sort:$sort,isAdult:true){id,title{romaji english native},coverImage{extraLarge large medium},bannerImage,description(asHtml:false),episodes,duration,status,format,startDate{year month day},endDate{year month day},genres,tags{name isAdult},averageScore,popularity,favourites,isAdult,nextAiringEpisode{episode airingAt},season,seasonYear,studios(isMain:true){nodes{name}}}}}''';
  static const detailQuery = r'''query($id:Int!){Media(id:$id){id,title{romaji english native},coverImage{extraLarge large medium},bannerImage,description(asHtml:false),episodes,duration,status,format,startDate{year month day},endDate{year month day},genres,tags{name isAdult},averageScore,popularity,favourites,isAdult,nextAiringEpisode{episode airingAt},streamingEpisodes{title thumbnail url site},season,seasonYear,studios(isMain:true){nodes{name}}}}''';
  static const scheduleQuery = r'''query($page:Int,$perPage:Int,$from:Int,$to:Int){Page(page:$page,perPage:$perPage){pageInfo{hasNextPage}airingSchedules(airingAt_greater:$from,airingAt_lesser:$to){id,airingAt,episode,media{id,title{romaji english native},coverImage{extraLarge large medium},description(asHtml:false),episodes,duration,status,format,genres,tags{name isAdult},averageScore,popularity,isAdult,nextAiringEpisode{episode airingAt},season,seasonYear,studios(isMain:true){nodes{name}}}}}}''';

  Future<Map<String, dynamic>> gql(String query, [Map<String, dynamic>? variables]) async {
    final r = await http.post(Uri.parse(endpoint), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'query': query, 'variables': variables ?? {}}));
    final j = jsonDecode(r.body);
    if (r.statusCode < 200 || r.statusCode >= 300 || (j['errors'] as List?)?.isNotEmpty == true) throw Exception(j['errors']?[0]?['message'] ?? 'AniList HTTP ${r.statusCode}');
    return (j['data'] as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> catalog({int page = 1, int perPage = 25, String search = '', String genre = '', String format = '', String status = '', int? year, String sort = 'POPULARITY_DESC', bool adult = false}) async {
    try {
      final query = adult ? matureCatalogQuery : catalogQuery;
      final vars = <String,dynamic>{'page':page,'perPage':perPage,'search':search.isEmpty?null:search,'genre':genre.isEmpty?null:genre,'sort':[sort]};
      if (!adult) { vars['format']=format.isEmpty?null:format; vars['status']=status.isEmpty?null:status; vars['year']=year; }
      final d = await gql(query, vars);
      return ((d['Page'] as Map?)?['media'] as List? ?? []).map((e) => (e as Map).cast<String, dynamic>()).where((m) => adult ? matureMedia(m) : safeMedia(m)).toList();
    } catch (e) {
      if (adult || (search.isNotEmpty || genre.isNotEmpty || format.isNotEmpty || status.isNotEmpty || year != null)) rethrow;
      return await jikanPopularFallback();
    }
  }

  Future<List<Map<String,dynamic>>> jikanPopularFallback({String search=''}) async {
    final uri = search.isEmpty
        ? Uri.parse('https://api.jikan.moe/v4/top/anime?filter=bypopularity&limit=25')
        : Uri.parse('https://api.jikan.moe/v4/anime?q=${Uri.encodeQueryComponent(search)}&limit=25');
    final r = await http.get(uri);
    if (r.statusCode < 200 || r.statusCode >= 300) throw Exception('Anime catalog unavailable (${r.statusCode}).');
    final arr = (jsonDecode(r.body)['data'] as List? ?? []);
    return arr.whereType<Map>().map((x) {
      final image = ((x['images'] as Map?)?['jpg'] as Map?)?['image_url'];
      final titleValue = s(x['title']);
      return <String,dynamic>{
        'id': int.tryParse(s(x['mal_id'])) ?? 0,
        'title': {'romaji': titleValue, 'english': titleValue},
        'coverImage': {'extraLarge': s(image), 'large': s(image), 'medium': s(image)},
        'episodes': x['episodes'],
        'duration': int.tryParse(RegExp(r'([0-9]+)').firstMatch(s(x['duration']))?.group(1) ?? '') ?? 24,
        'status': s(x['status']).toUpperCase().contains('AIRING') ? 'RELEASING' : (s(x['status']).isEmpty ? 'FINISHED' : 'FINISHED'),
        'format': s(x['type']).toUpperCase(),
        'averageScore': x['score'] == null ? null : ((x['score'] as num) * 10).round(),
        'genres': const <String>[],
        'tags': const <Map<String,dynamic>>[],
        'isAdult': false,
        'source': 'jikan',
      };
    }).where((m)=>s((m['title'] as Map)['romaji']).isNotEmpty && s(m['coverImage'] is Map ? (m['coverImage'] as Map)['large'] : '').isNotEmpty).toList();
  }

  Future<Map<String, dynamic>> jikanDetails(int malId) async {
    final r = await http.get(Uri.parse('https://api.jikan.moe/v4/anime/$malId/full'));
    if (r.statusCode < 200 || r.statusCode >= 300) throw Exception('Anime details unavailable (${r.statusCode}).');
    final x = (jsonDecode(r.body)['data'] as Map).cast<String,dynamic>();
    final image = ((x['images'] as Map?)?['jpg'] as Map?)?['large_image_url'] ?? ((x['images'] as Map?)?['jpg'] as Map?)?['image_url'];
    return {
      'id': malId,
      'source': 'jikan',
      'title': {'romaji': s(x['title']), 'english': s(x['title_english']).isNotEmpty ? s(x['title_english']) : s(x['title'])},
      'coverImage': {'extraLarge': s(image), 'large': s(image), 'medium': s(image)},
      'description': s(x['synopsis']),
      'episodes': x['episodes'],
      'duration': int.tryParse(RegExp(r'([0-9]+)').firstMatch(s(x['duration']))?.group(1) ?? '') ?? 24,
      'status': s(x['status']).toUpperCase().contains('AIRING') ? 'RELEASING' : 'FINISHED',
      'format': s(x['type']).toUpperCase(),
      'genres': (x['genres'] as List? ?? []).whereType<Map>().map((e)=>s(e['name'])).toList(),
      'tags': const <Map<String,dynamic>>[],
      'averageScore': x['score'] == null ? null : ((x['score'] as num) * 10).round(),
      'isAdult': false,
      'nextAiringEpisode': null,
    };
  }
  Future<Map<String, dynamic>> details(int id) async => (await gql(detailQuery, {'id': id}))['Media'].cast<String, dynamic>();
  Future<List<Map<String, dynamic>>> schedule(DateTime start, DateTime end, {bool adult = false}) async {
    final from = start.millisecondsSinceEpoch ~/ 1000;
    final to = end.millisecondsSinceEpoch ~/ 1000;
    final all = <Map<String, dynamic>>[];
    for (var page = 1; page <= 12; page++) {
      final d = await gql(scheduleQuery, {'page': page, 'perPage': 25, 'from': from, 'to': to});
      final p = (d['Page'] as Map?)?.cast<String, dynamic>() ?? {};
      final arr = (p['airingSchedules'] as List? ?? []).map((e) => (e as Map).cast<String, dynamic>());
      for (final row in arr) {
        final m = (row['media'] as Map?)?.cast<String, dynamic>();
        if (m != null && (adult ? matureMedia(m) : safeMedia(m))) all.add({...row, 'media': m});
      }
      if (p['pageInfo']?['hasNextPage'] != true) break;
    }
    return all;
  }
}

bool safeMedia(Map<String, dynamic> m) {
  if (m['isAdult'] == true) return false;
  final gs = (m['genres'] as List? ?? []).map(s).toList();
  if (gs.any((g) => RegExp(r'^ecchi$|^hentai$', caseSensitive: false).hasMatch(g))) return false;
  final tags = (m['tags'] as List? ?? []).whereType<Map>();
  return !tags.any((t) => t['isAdult'] == true);
}
bool matureMedia(Map<String, dynamic> m) => m['isAdult'] == true || ((m['tags'] as List? ?? []).whereType<Map>().any((t) => t['isAdult'] == true));

class AnimeVaultStore extends ChangeNotifier {
  final api = AniListApi();
  SharedPreferences? prefs;
  Map<int, LibraryEntry> library = {};
  Set<int> favorites = {};
  bool matureEnabled = true;
  bool streamingEnabled = true;
  bool matureStreamingEnabled = false;
  bool is18Confirmed = false;
  final Map<int, Map<String, dynamic>> cache = {};
  final Map<int, String> customProviders = {};
  /// Persisted external viewing-provider URL templates. These are seeded from
  /// the uploaded web app's normal provider set and can be edited once in
  /// Settings. They stay on-device across app restarts.
  List<String> providerUrls = <String>[
    'https://www.crunchyroll.com/search?q={title}',
    'https://www.youtube.com/results?search_query={title}+episode+{episode}+official',
    'https://www.youtube.com/results?search_query=Muse+India+{title}+episode+{episode}',
    'https://www.youtube.com/results?search_query=Ani-One+{title}+episode+{episode}',
    'https://www.primevideo.com/search/ref=atv_nb_sr?phrase={title}+episode+{episode}',
    'https://www.netflix.com/search?q={title}',
    'https://www.justwatch.com/in/search?q={title}',
    '',
  ];
  int page = 1;
  String search = '';
  String genre = '';
  String format = '';
  String status = '';
  String sort = 'POPULARITY_DESC';
  int? year;
  List<Map<String, dynamic>> discover = [];
  List<Map<String, dynamic>> popular = [];
  List<Map<String, dynamic>> scheduleRows = [];
  DateTime scheduleDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  Map<String, dynamic>? selected;
  int tab = 0;
  bool loading = false;
  String toastText = '';
  bool adultSection = false;
  String lastApiError = '';

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    final lj = prefs?.getString('animevault_library');
    if (lj != null) {
      final raw = jsonDecode(lj) as Map<String, dynamic>;
      library = raw.map((k, v) => MapEntry(int.parse(k), LibraryEntry.fromJson((v as Map).cast<String, dynamic>())));
    }
    favorites = (prefs?.getStringList('animevault_favorites') ?? []).map((e) => int.tryParse(e) ?? 0).where((e) => e > 0).toSet();
    matureEnabled = prefs?.getBool('matureEnabled') ?? true;
    streamingEnabled = prefs?.getBool('streamingEnabled') ?? true;
    matureStreamingEnabled = prefs?.getBool('matureStreamingEnabled') ?? false;
    is18Confirmed = prefs?.getBool('is18Confirmed') ?? false;
    final savedProviders = prefs?.getStringList('providerUrls') ?? [];
    if (savedProviders.isNotEmpty) {
      for (var i = 0; i < min(8, savedProviders.length); i++) {
        providerUrls[i] = savedProviders[i];
      }
    } else {
      // First run: seed the provider set once, then persist it so the user
      // never has to re-enter the links after reopening the app.
      await prefs?.setStringList('providerUrls', providerUrls);
    }
    await loadHome();
  }

  Future<void> persist() async {
    await prefs?.setString('animevault_library', jsonEncode(library.map((k, v) => MapEntry('$k', v.toJson()))));
    await prefs?.setStringList('animevault_favorites', favorites.map((e) => '$e').toList());
    await prefs?.setBool('matureEnabled', matureEnabled);
    await prefs?.setBool('streamingEnabled', streamingEnabled);
    await prefs?.setBool('matureStreamingEnabled', matureStreamingEnabled);
    await prefs?.setBool('is18Confirmed', is18Confirmed);
    await prefs?.setStringList('providerUrls', providerUrls);
  }

  Future<void> loadHome() async {
    loading = true; notifyListeners();
    try {
      lastApiError = '';
      popular = await api.catalog(page: 1, perPage: 12);
      discover = List<Map<String, dynamic>>.from(popular);
      for (final m in popular) {
        final id = int.tryParse(s(m['id'])) ?? 0;
        if (id != 0) cache[id] = m;
      }
    } catch (e) {
      lastApiError = e.toString();
      popular = [];
      discover = [];
    }
    loading = false; notifyListeners();
  }

  Future<void> loadDiscover({bool reset = true}) async {
    final noFilters = search.trim().isEmpty && genre.isEmpty && format.isEmpty && status.isEmpty && year == null && !adultSection;
    if (reset) {
      page = 1;
      if (!(noFilters && popular.isNotEmpty)) discover = [];
    }
    if (noFilters && page == 1 && popular.isNotEmpty) {
      discover = List<Map<String, dynamic>>.from(popular);
      lastApiError = '';
      loading = false;
      notifyListeners();
      return;
    }
    loading = true; notifyListeners();
    try {
      lastApiError = '';
      final rows = await api.catalog(page: page, search: search, genre: genre, format: format, status: status, year: year, sort: sort, adult: adultSection);
      if (reset) discover = [];
      discover.addAll(rows);
      for (final m in rows) {
        final id = int.tryParse(s(m['id'])) ?? 0;
        if (id != 0) cache[id] = m;
      }
      if (rows.isEmpty && reset) lastApiError = 'No anime matched the current search or filters.';
    } catch (e) {
      lastApiError = e.toString();
      if (reset) discover = [];
    }
    loading = false; notifyListeners();
  }

  Future<void> loadSchedule() async {
    loading = true; notifyListeners();
    try {
      scheduleRows = await api.schedule(scheduleDay, scheduleDay.add(const Duration(days: 1)), adult: adultSection);
      scheduleRows.sort((a, b) => (a['airingAt'] as num).compareTo(b['airingAt'] as num));
      for (final r in scheduleRows) cache[(r['media'] as Map)['id'] as int] = (r['media'] as Map).cast<String, dynamic>();
    } catch (_) {}
    loading = false; notifyListeners();
  }

  Future<Map<String, dynamic>?> loadDetails(int id) async {
    loading = true; notifyListeners();
    try {
      final cached = cache[id];
      final m = cached != null && s(cached['source']) == 'jikan' ? await api.jikanDetails(id) : await api.details(id);
      cache[id] = m;
      selected = m;
      syncEntry(m);
      loading = false; notifyListeners();
      return m;
    } catch (e) {
      lastApiError = e.toString();
      loading = false; notifyListeners();
      return null;
    }
  }

  void syncEntry(Map<String, dynamic> m) {
    final id = m['id'] as int;
    final e = library[id];
    if (e == null) return;
    e.title = safeTitle(m); e.poster = posterUrl(m); e.total = effectiveTotal(m, e); e.duration = int.tryParse(s(m['duration'])) ?? e.duration; e.nextAiring = int.tryParse(s((m['nextAiringEpisode'] as Map?)?['episode'])) ?? 0; e.airingStatus = s(m['status']); e.updated = DateTime.now().millisecondsSinceEpoch;
    persist();
  }

  void addToLibrary(Map<String, dynamic> m, String status) {
    final id = m['id'] as int;
    final old = library[id];
    final e = old ?? LibraryEntry(id: id, title: safeTitle(m), poster: posterUrl(m), duration: int.tryParse(s(m['duration'])) ?? 24);
    e.title = safeTitle(m); e.poster = posterUrl(m); e.total = effectiveTotal(m, e); e.duration = int.tryParse(s(m['duration'])) ?? e.duration; e.status = status; e.nextAiring = int.tryParse(s((m['nextAiringEpisode'] as Map?)?['episode'])) ?? 0; e.airingStatus = s(m['status']); e.mature = matureMedia(m); e.updated = DateTime.now().millisecondsSinceEpoch;
    if (status == 'COMPLETED' && e.total > 0) e.watched = List.generate(e.total, (i) => i + 1);
    library[id] = e; persist(); notifyListeners();
  }

  void setStatus(int id, String status) {
    final x = library[id];
    if (x == null) return;
    x.status = status;
    if (status == 'COMPLETED' && x.total > 0) x.watched = List.generate(x.total, (i) => i + 1);
    if (status == 'WATCHING' && x.total > 0 && x.watched.length >= x.total) x.watched = x.watched.where((e) => e < x.total).toList();
    x.updated = DateTime.now().millisecondsSinceEpoch;
    persist();
    notifyListeners();
  }

  void markNext(int id) {
    final x = library[id];
    if (x == null) return;
    final next = nextEpisode(id);
    if (x.total > 0 && next > x.total) return;
    markThrough(id, next);
  }

  void setFavorite(int id) { favorites.contains(id) ? favorites.remove(id) : favorites.add(id); persist(); notifyListeners(); }
  void toggleEpisode(int id, int ep) {
    final x = library[id]; if (x == null) return;
    if (x.watched.contains(ep)) { x.watched.remove(ep); } else { for (var i = 1; i <= ep; i++) { if (!x.watched.contains(i)) x.watched.add(i); } }
    x.watched.sort();
    if (x.total > 0 && x.watched.length >= x.total) x.status = 'COMPLETED'; else if (x.status == 'COMPLETED') x.status = 'WATCHING';
    x.updated = DateTime.now().millisecondsSinceEpoch; persist(); notifyListeners();
  }
  void markThrough(int id, int ep) { final x = library[id]; if (x == null) return; for (var i = 1; i <= ep; i++) { if (!x.watched.contains(i)) x.watched.add(i); } x.watched.sort(); if (x.total > 0 && x.watched.length >= x.total) x.status = 'COMPLETED'; else x.status = 'WATCHING'; x.updated = DateTime.now().millisecondsSinceEpoch; persist(); notifyListeners(); }
  int nextEpisode(int id) { final x = library[id]; if (x == null) return 1; var n = 1; while (x.watched.contains(n)) n++; return n; }

  List<LibraryEntry> libraryBy(String section) {
    final xs = library.values.toList();
    if (section == 'completed') return xs.where((x) => x.status == 'COMPLETED').toList();
    if (section == 'favorites') return xs.where((x) => favorites.contains(x.id)).toList();
    if (section == 'ongoing') return xs.where((x) => x.nextAiring > 0 || x.airingStatus == 'RELEASING' || (x.status == 'WATCHING' && x.nextAiring > 0)).toList();
    return xs.where((x) => x.status != 'COMPLETED').toList();
  }

  int watchedEpisodes() => library.values.fold(0, (a, e) => a + e.watched.length);
  double watchHours() => library.values.fold(0.0, (a, e) => a + e.watchMinutes / 60.0);

  Future<void> exportJson() async { final data = jsonEncode({'library': library.map((k,v)=>MapEntry('$k',v.toJson())), 'favorites': favorites.toList(), 'matureEnabled': matureEnabled, 'streamingEnabled': streamingEnabled, 'matureStreamingEnabled': matureStreamingEnabled, 'is18Confirmed': is18Confirmed, 'exportedAt': DateTime.now().toIso8601String()}); await SharePlus.instance.share(ShareParams(files: [XFile.fromData(Uint8List.fromList(utf8.encode(data)), mimeType: 'application/json', name: 'animevault-backup.json')])); }
  Future<void> importJson() async { final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: ['json']); if (result?.files.single.bytes == null) return; final j = jsonDecode(utf8.decode(result!.files.single.bytes!)) as Map<String,dynamic>; final raw = (j['library'] as Map?)?.cast<String,dynamic>() ?? {}; library = raw.map((k,v)=>MapEntry(int.parse(k), LibraryEntry.fromJson((v as Map).cast<String,dynamic>()))); favorites = ((j['favorites'] as List?) ?? []).map((e)=>int.tryParse(s(e)) ?? 0).where((e)=>e>0).toSet(); await persist(); notifyListeners(); }
  String csv() { final rows = <String>[['Anime','Status','Watched_Episodes','Total_Episodes','Progress_Pct','Watch_Time_Hours','Favorite','Mature_Section','Last_Updated'].join(',')]; final list = library.values.toList()..sort((a,b)=>a.title.compareTo(b.title)); for (final e in list) { rows.add([e.title,e.status,e.watched.length,e.total,e.progress.round(),(e.watchMinutes/60).toStringAsFixed(2),favorites.contains(e.id)?'Yes':'No',e.mature?'18+ / Adult':'',DateTime.fromMillisecondsSinceEpoch(e.updated).toIso8601String()].map((v)=>'"${s(v).replaceAll('"','""')}"').join(',')); } return '\ufeff${rows.join('\n')}'; }
  Future<void> exportCsv() async { await SharePlus.instance.share(ShareParams(files: [XFile.fromData(Uint8List.fromList(utf8.encode(csv())), mimeType: 'text/csv', name: 'animevault_library.csv')])); }
  Future<void> exportPdf() async { final doc = pw.Document(); final rows = library.values.toList()..sort((a,b)=>a.title.compareTo(b.title)); doc.addPage(pw.MultiPage(build: (_) => [pw.Header(level: 0, text: 'AnimeVault Watch Report'), pw.Text('Generated ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}'), pw.SizedBox(height: 12), pw.Table.fromTextArray(headers:['Anime','Status','Watched','Total','Progress','Watch time'], data:rows.map((e)=>[e.title,e.status,'${e.watched.length}','${e.total}','${e.progress.round()}%','${(e.watchMinutes/60).toStringAsFixed(1)}h']).toList())])); await Printing.sharePdf(bytes: await doc.save(), filename: 'animevault_watch_report.pdf'); }

  Future<List<String>> enrich(Map<String,dynamic> m) async {
    final out=<String>[]; final t=Uri.encodeComponent(safeTitle(m));
    try { final r=await http.get(Uri.parse('https://api.jikan.moe/v4/anime?q=$t&limit=1')); if(r.statusCode==200){final d=jsonDecode(r.body); if((d['data'] as List?)?.isNotEmpty==true){final a=d['data'][0]; out.add('Jikan: ${a['score']!=null?'score ${a['score']}':'metadata ready'}');}} } catch(_){ }
    try { final r=await http.get(Uri.parse('https://kitsu.io/api/edge/anime?filter[text]=$t&page[limit]=1')); if(r.statusCode==200){final list=(jsonDecode(r.body)['data'] as List?) ?? []; if(list.isNotEmpty){final at=(list.first as Map)['attributes'] as Map; out.add('Kitsu: ${at['averageRating'] ?? at['status'] ?? 'metadata ready'}');}} } catch(_){ }
    try { final r=await http.get(Uri.parse('https://api.animechan.io/v1/quotes/random?anime=$t')); if(r.statusCode==200){final d=jsonDecode(r.body); final q=d['data']?['content']; if(q!=null) out.add('AnimeChan: ${s(q)}');}} catch(_){ }
    try { final slug=safeTitle(m).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'),'_').replaceAll(RegExp(r'^_|_$'),''); final r=await http.get(Uri.parse('https://anime-facts-rest-api.herokuapp.com/api/v1/${Uri.encodeComponent(slug)}')); if(r.statusCode==200){final list=(jsonDecode(r.body)['data'] as List?) ?? []; if(list.isNotEmpty){final q=(list.first as Map)['fact']; if(q!=null) out.add('AnimeFacts: ${s(q)}');}}} catch(_){ }
    try { final r=await http.get(Uri.parse('https://nekos.best/api/v2/neko')); if(r.statusCode==200) out.add('NekosBest: SFW image ready'); } catch(_){ }
    try { final r=await http.get(Uri.parse('https://api.waifu.im/search?is_nsfw=false')); if(r.statusCode==200) out.add('Waifu.im: SFW artwork ready'); } catch(_){ }
    out.add('AniList: primary metadata, schedule and exact episode links when supplied');
    out.add('Trace.moe: screenshot identification can be added with a public image URL');
    return out;
  }
}

class AnimeVaultApp extends StatelessWidget {
  const AnimeVaultApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(title:'AnimeVault',debugShowCheckedModeBanner:false,theme:ThemeData(brightness:Brightness.dark,scaffoldBackgroundColor:bg,colorScheme:ColorScheme.fromSeed(seedColor:accent,brightness:Brightness.dark),useMaterial3:true,fontFamily:'Arial'),home:const Shell());
}

class Shell extends StatefulWidget { const Shell({super.key}); @override State<Shell> createState()=>_ShellState(); }
class _ShellState extends State<Shell> {
  final store=AnimeVaultStore(); final search=TextEditingController(); int index=0; String librarySection='watchlist';
  @override void initState(){super.initState(); store.init();}
  @override void dispose(){search.dispose();super.dispose();}
  void nav(int i){setState(()=>index=i); if(i==1 && store.discover.isEmpty) store.loadDiscover(); if(i==2) store.loadSchedule();}
  @override Widget build(BuildContext context){return AnimatedBuilder(animation:store,builder:(_,__)=>Scaffold(backgroundColor:bg,appBar:AppBar(backgroundColor:bg,elevation:0,title:titleRow(),actions:[IconButton(onPressed:()=>showSettings(context),icon:const Icon(Icons.settings_outlined))]),body:IndexedStack(index:index,children:[homePage(),discoverPage(),schedulePage(),libraryPage(),morePage()]),bottomNavigationBar:NavigationBar(backgroundColor:const Color(0xFF080C14),indicatorColor:accent.withOpacity(.15),selectedIndex:index,onDestinationSelected:nav,destinations:const[NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Home'),NavigationDestination(icon:Icon(Icons.search),label:'Search'),NavigationDestination(icon:Icon(Icons.calendar_month_outlined),label:'Schedule'),NavigationDestination(icon:Icon(Icons.video_library_outlined),label:'Library'),NavigationDestination(icon:Icon(Icons.more_horiz),label:'More')]),));}
  Widget titleRow()=>Row(children:[Container(width:36,height:36,decoration:BoxDecoration(gradient:const LinearGradient(colors:[accent,pink]),borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.play_arrow_rounded,color:Colors.white)),const SizedBox(width:10),const Text('AnimeVault',style:TextStyle(fontWeight:FontWeight.w900,fontSize:19)),const Spacer(),SizedBox(width:180,child:TextField(controller:search,onSubmitted:(v){store.search=v;setState(()=>index=1);store.loadDiscover();},decoration:InputDecoration(hintText:'Search anime',prefixIcon:const Icon(Icons.search,size:18),filled:true,fillColor:panel,border:OutlineInputBorder(borderSide:BorderSide(color:line),borderRadius:BorderRadius.all(Radius.circular(12))),contentPadding:const EdgeInsets.symmetric(vertical:0,horizontal:8))))]);
  Widget homePage(){final cont=store.library.values.where((e)=>e.status=='WATCHING').toList()..sort((a,b)=>b.updated.compareTo(a.updated)); return RefreshIndicator(onRefresh:store.loadHome,child:ListView(padding:const EdgeInsets.fromLTRB(12,8,12,30),children:[heroCard(),const SizedBox(height:16),sectionTitle('Continue Watching',action:cont.isEmpty?null:()=>setState(()=>librarySection='watchlist')),cont.isEmpty?emptyCard('Your in-progress anime will appear here.'):gridCards(cont.take(6).map(entryToMedia).toList()),const SizedBox(height:18),sectionTitle('Popular anime',action:()=>setState(()=>index=1)),store.popular.isEmpty?emptyCard(store.loading?'Loading popular anime…':'No popular anime available right now.'):gridCards(store.popular)]));}
  Map<String,dynamic> entryToMedia(LibraryEntry e)=>{'id':e.id,'title':{'romaji':e.title},'coverImage':{'extraLarge':e.poster},'episodes':e.total,'duration':e.duration,'status':e.airingStatus};
  Widget heroCard()=>Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(gradient:LinearGradient(colors:[const Color(0xFF171E3A),panel]),borderRadius:BorderRadius.circular(20),border:Border.all(color:Colors.white.withOpacity(.06))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Your anime, organized.',style:TextStyle(fontWeight:FontWeight.w900,fontSize:28)),const SizedBox(height:7),const Text('Track episodes, follow schedules, open legal viewing links and keep your library synced on this device.',style:TextStyle(color:muted,height:1.5)),const SizedBox(height:15),Wrap(spacing:8,runSpacing:8,children:[_btn('Browse anime',accent,()=>setState(()=>index=1)),_btn('Surprise me',panel2,()=>randomAnime()),_btn('Dashboard',panel2,()=>showDashboard(context))]) ]));
  Widget sectionTitle(String title,{VoidCallback? action})=>Row(children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:21)),const Spacer(),if(action!=null)TextButton(onPressed:action,child:const Text('Browse all'))]);
  Widget gridCards(List<Map<String,dynamic>> ms)=>GridView.builder(itemCount:ms.length,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,crossAxisSpacing:9,mainAxisSpacing:11,childAspectRatio:.62),itemBuilder:(_,i)=>MediaCard(m:ms[i],store:store,onOpen:()=>showDetails(context,ms[i])));
  Widget emptyCard(String t)=>Container(padding:const EdgeInsets.all(26),decoration:BoxDecoration(border:Border.all(color:line),borderRadius:BorderRadius.circular(16)),child:Center(child:Text(t,textAlign:TextAlign.center,style:const TextStyle(color:muted))));
  Widget _btn(String t,Color c,VoidCallback f)=>FilledButton(onPressed:f,style:FilledButton.styleFrom(backgroundColor:c==accent?accent:panel2,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(11))),child:Text(t));
  Future<void> randomAnime() async {try{final rows=await store.api.catalog(page:1,perPage:25,sort:'POPULARITY_DESC');if(rows.isNotEmpty)showDetails(context,rows[Random().nextInt(rows.length)]);}catch(_){}}
  Widget discoverPage() {
    return RefreshIndicator(
      onRefresh: store.loadDiscover,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              const Text('Discover anime', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 23)),
              const Spacer(),
              IconButton(onPressed: store.loadDiscover, icon: const Icon(Icons.refresh)),
              OutlinedButton.icon(
                onPressed: () => showFilterSheet(context),
                icon: const Icon(Icons.tune, size: 17),
                label: const Text('Filters'),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text('Popular first · adult titles are excluded here', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 10),
          if (store.discover.isNotEmpty) gridCards(store.discover),
          if (store.loading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!store.loading && store.discover.isNotEmpty)
            Center(
              child: TextButton(
                onPressed: () {
                  store.page++;
                  store.loadDiscover(reset: false);
                },
                child: const Text('Load more'),
              ),
            ),
          if (!store.loading && store.discover.isEmpty)
            Column(
              children: [
                emptyCard(store.lastApiError.isEmpty ? 'No anime found. Try Search or Filters.' : store.lastApiError),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: store.loadDiscover,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
        ],
      ),
    );
  }
  Widget schedulePage(){final grouped=<String,List<Map<String,dynamic>>>{};for(final r in store.scheduleRows){final d=DateTime.fromMillisecondsSinceEpoch((r['airingAt'] as num).toInt()*1000);final k=DateFormat('hh:mm a').format(d);(grouped[k]??=[]).add(r);}return ListView(padding:const EdgeInsets.all(12),children:[Row(children:[const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Schedule',style:TextStyle(fontWeight:FontWeight.w900,fontSize:23)),Text('Upcoming episodes in your local time',style:TextStyle(color:muted,fontSize:12))]),const Spacer(),IconButton(onPressed:store.loadSchedule,icon:const Icon(Icons.refresh))]),const SizedBox(height:10),dateStrip(),const SizedBox(height:10),if(store.loading)const Padding(padding:EdgeInsets.all(30),child:Center(child:CircularProgressIndicator())),...grouped.entries.map((e)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Text(e.key,style:const TextStyle(fontWeight:FontWeight.w800,color:muted))),...e.value.map(scheduleCard),const SizedBox(height:8)])),if(!store.loading && store.scheduleRows.isEmpty)emptyCard('No upcoming episodes listed for this day.')]);}
  Widget dateStrip(){return SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[IconButton(onPressed:(){store.scheduleDay=store.scheduleDay.subtract(const Duration(days:7));store.loadSchedule();},icon:const Icon(Icons.chevron_left)),...buildScheduleButtons(),IconButton(onPressed:(){store.scheduleDay=store.scheduleDay.add(const Duration(days:7));store.loadSchedule();},icon:const Icon(Icons.chevron_right))]));}
  List<Widget> buildScheduleButtons(){final monday=store.scheduleDay;return List.generate(7,(i){final d=monday.add(Duration(days:i));final active=d.year==store.scheduleDay.year&&d.month==store.scheduleDay.month&&d.day==store.scheduleDay.day;return Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:SizedBox(width:72,child:Column(mainAxisSize:MainAxisSize.min,children:[Text(DateFormat('EEE').format(d),style:const TextStyle(fontSize:11)),Text(DateFormat('d MMM').format(d),style:const TextStyle(fontSize:12,fontWeight:FontWeight.w800))])),selected:active,onSelected:(_){store.scheduleDay=DateTime(d.year,d.month,d.day);store.loadSchedule();},selectedColor:accent.withOpacity(.2)));});}
  Widget scheduleCard(Map<String,dynamic> row){final m=(row['media'] as Map).cast<String,dynamic>();final d=DateTime.fromMillisecondsSinceEpoch((row['airingAt'] as num).toInt()*1000);return Card(color:panel,borderOnForeground:false,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14),side:BorderSide(color:Colors.white.withOpacity(.05))),child:ListTile(onTap:()=>showDetails(context,m),contentPadding:const EdgeInsets.all(8),leading:Hero(tag:'poster_${m['id']}',child:ClipRRect(borderRadius:BorderRadius.circular(8),child:CachedNetworkImage(imageUrl:posterUrl(m),width:52,height:70,fit:BoxFit.cover,errorWidget:(_,__,___)=>Container(width:52,height:70,color:panel2,child:const Icon(Icons.image_not_supported_outlined))))),title:Text(safeTitle(m),maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Padding(padding:const EdgeInsets.only(top:5),child:Wrap(spacing:6,children:[Chip(label:Text('EP ${row['episode']}'),padding:EdgeInsets.zero,visualDensity:VisualDensity.compact),Text('${m['duration'] ?? '?'} min · ${DateFormat('hh:mm a').format(d)}',style:const TextStyle(color:muted))])),trailing:const Icon(Icons.chevron_right)));}
  Widget libraryPage(){final xs=store.libraryBy(librarySection);return ListView(padding:const EdgeInsets.all(12),children:[Row(children:[Text(librarySection[0].toUpperCase()+librarySection.substring(1),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:23)),const Spacer(),PopupMenuButton<String>(onSelected:(v)=>setState(()=>librarySection=v),itemBuilder:(_)=>const[PopupMenuItem(value:'watchlist',child:Text('Watchlist')),PopupMenuItem(value:'completed',child:Text('Completed')),PopupMenuItem(value:'favorites',child:Text('Favorites')),PopupMenuItem(value:'ongoing',child:Text('Ongoing'))])]),const SizedBox(height:10),xs.isEmpty?emptyCard('Nothing saved here yet.'):gridCards(xs.map(entryToMedia).toList())]);}
  Widget morePage(){return ListView(padding:const EdgeInsets.all(12),children:[const Text('More',style:TextStyle(fontWeight:FontWeight.w900,fontSize:23)),const SizedBox(height:12),_moreTile(Icons.insights_outlined,'Dashboard','Watch time, progress and data export',()=>showDashboard(context)),_moreTile(Icons.favorite_border,'Favorites','Your starred anime',(){setState(()=>librarySection='favorites');setState(()=>index=3);}),_moreTile(Icons.check_circle_outline,'Completed','Finished titles',(){setState(()=>librarySection='completed');setState(()=>index=3);}),_moreTile(Icons.timelapse,'Ongoing','Currently airing titles in your library',(){setState(()=>librarySection='ongoing');setState(()=>index=3);}),_moreTile(Icons.no_adult_content_outlined,'Mature area','Separate adult catalog and schedule',(){store.matureEnabled=true;store.persist();showMature(context);}),_moreTile(Icons.settings_outlined,'Settings','Streaming, providers, API enrichment and data',()=>showSettings(context))]);}
  Widget _moreTile(IconData icon,String title,String sub,VoidCallback f)=>Card(color:panel,child:ListTile(onTap:f,leading:CircleAvatar(backgroundColor:accent.withOpacity(.12),child:Icon(icon,color:accent)),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(sub,style:const TextStyle(color:muted)),trailing:const Icon(Icons.chevron_right)));
  Future<void> showFilterSheet(BuildContext c) async {showModalBottomSheet(context:c,backgroundColor:panel,isScrollControlled:true,builder:(_)=>StatefulBuilder(builder:(ctx,setSheet)=>Padding(padding:EdgeInsets.only(left:16,right:16,top:16,bottom:MediaQuery.of(ctx).viewInsets.bottom+16),child:Column(mainAxisSize:MainAxisSize.min,children:[const Align(alignment:Alignment.centerLeft,child:Text('Filters',style:TextStyle(fontWeight:FontWeight.w900,fontSize:20))),DropdownButtonFormField<String>(value:store.genre.isEmpty?null:store.genre,decoration:const InputDecoration(labelText:'Genre'),items:['Action','Adventure','Comedy','Drama','Fantasy','Horror','Mystery','Psychological','Romance','Sci-Fi','Sports','Supernatural','Thriller'].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>setSheet(()=>store.genre=v??'')),DropdownButtonFormField<String>(value:store.format.isEmpty?null:store.format,decoration:const InputDecoration(labelText:'Format'),items:const['TV','MOVIE','OVA','ONA','SPECIAL'].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>setSheet(()=>store.format=v??'')),DropdownButtonFormField<String>(value:store.status.isEmpty?null:store.status,decoration:const InputDecoration(labelText:'Airing status'),items:const['FINISHED','RELEASING','NOT_YET_RELEASED'].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>setSheet(()=>store.status=v??'')),DropdownButtonFormField<String>(value:store.sort,decoration:const InputDecoration(labelText:'Sort'),items:const['POPULARITY_DESC','TRENDING_DESC','SCORE_DESC','FAVOURITES_DESC','START_DATE_DESC','TITLE_ROMAJI'].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>setSheet(()=>store.sort=v??store.sort)),DropdownButtonFormField<int>(value:store.year,decoration:const InputDecoration(labelText:'Year'),items:[const DropdownMenuItem<int>(value:null,child:Text('Any year')),...List.generate(DateTime.now().year-1959,(i)=>DateTime.now().year-i).map((y)=>DropdownMenuItem<int>(value:y,child:Text('$y')))],onChanged:(v)=>setSheet(()=>store.year=v)),const SizedBox(height:8),FilledButton(onPressed:(){Navigator.pop(ctx);store.loadDiscover();},child:const Text('Apply filters'))]))));}
  void showDetails(BuildContext c,Map<String,dynamic> initial) async {await showDetailsSheet(c,store,initial);}
  void showDashboard(BuildContext c){showModalBottomSheet(context:c,isScrollControlled:true,backgroundColor:bg,builder:(_)=>DashboardSheet(store:store));}
  void showSettings(BuildContext c){showModalBottomSheet(context:c,isScrollControlled:true,backgroundColor:bg,builder:(_)=>SettingsSheet(store:store));}
  void showMature(BuildContext c){showModalBottomSheet(context:c,isScrollControlled:true,backgroundColor:bg,builder:(_)=>MatureSheet(store:store));}
}

Future<void> showDetailsSheet(BuildContext context, AnimeVaultStore store, Map<String,dynamic> initial) async {
  store.selected = initial;
  store.adultSection = matureMedia(initial);
  final m = await store.loadDetails(initial['id'] as int);
  if (!context.mounted) return;
  showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: bg, builder: (_) => DetailSheet(store: store, m: m ?? initial));
}

class MediaCard extends StatelessWidget { final Map<String,dynamic> m; final AnimeVaultStore store; final VoidCallback onOpen; const MediaCard({super.key,required this.m,required this.store,required this.onOpen}); @override Widget build(BuildContext context){final id=m['id'] as int;final saved=store.library[id];final total=effectiveTotal(m,saved);final watched=saved?.watched.length??0;final progress=total>0?((watched/total)*100).round():0;return Card(color:card,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:BorderSide(color:Colors.white.withOpacity(.06))),clipBehavior:Clip.antiAlias,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Stack(children:[Positioned.fill(child:Hero(tag:'poster_$id',child:GestureDetector(onTap:onOpen,child:CachedNetworkImage(imageUrl:posterUrl(m),fit:BoxFit.cover,errorWidget:(_,__,___)=>Container(color:panel2,child:const Icon(Icons.image_not_supported_outlined))))),),Positioned(left:8,top:8,child:_pill(formatLabel(s(m['format'])))),Positioned(right:8,top:8,child:_pill(m['averageScore']!=null?'★ ${(double.parse(s(m['averageScore']))/10).toStringAsFixed(1)}':'—',gold)),Positioned(right:8,bottom:8,child:IconButton.filledTonal(onPressed:()=>store.setFavorite(id),icon:Icon(store.favorites.contains(id)?Icons.star:Icons.star_border,color:store.favorites.contains(id)?gold:null))),]),),Padding(padding:const EdgeInsets.fromLTRB(9,8,9,8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(safeTitle(m),maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:4),Row(children:[Expanded(child:Text(total>0?'$watched/$total eps':'— eps',style:const TextStyle(color:muted,fontSize:11))),Text('$progress%',style:const TextStyle(color:muted,fontSize:11))]),const SizedBox(height:5),LinearProgressIndicator(value:total>0?watched/total:0,minHeight:4,backgroundColor:line,color:accent),const SizedBox(height:6),Row(children:[Expanded(child:OutlinedButton(onPressed:onOpen,child:const Text('View',style:TextStyle(fontSize:11)))),const SizedBox(width:6),Expanded(child:OutlinedButton(onPressed:()=>store.addToLibrary(m,saved==null?'WATCHING':(saved.status=='COMPLETED'?'WATCHING':'COMPLETED')),child:Text(saved==null?'Add':'Update',style:const TextStyle(fontSize:11)))),if(saved!=null) ...[const SizedBox(width:6),IconButton.filledTonal(tooltip:'Mark next episode',onPressed:()=>store.markNext(id),icon:const Icon(Icons.skip_next))]])]))]));}
  Widget _pill(String t,[Color? color])=>Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:4),decoration:BoxDecoration(color:Colors.black.withOpacity(.65),borderRadius:BorderRadius.circular(8)),child:Text(t,style:TextStyle(fontSize:9,fontWeight:FontWeight.w800,color:color??Colors.white)));
}

class DetailSheet extends StatefulWidget {
  final AnimeVaultStore store;
  final Map<String, dynamic> m;

  const DetailSheet({super.key, required this.store, required this.m});

  @override
  State<DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<DetailSheet> {
  int page = 0;
  final jump = TextEditingController();

  @override
  void dispose() {
    jump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final id = m['id'] as int;
    final e = widget.store.library[id];
    final total = effectiveTotal(m, e);
    final start = page * 100 + 1;
    final end = total > 0 ? min(total, start + 99) : 0;
    final watched = e?.watched.toSet() ?? <int>{};
    final airing = (m['nextAiringEpisode'] as Map?)?.cast<String, dynamic>();

    return DraggableScrollableSheet(
      initialChildSize: .94,
      maxChildSize: .98,
      minChildSize: .72,
      builder: (_, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => showPoster(context, posterUrl(m), safeTitle(m)),
                  child: Hero(
                    tag: 'poster_$id',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedNetworkImage(
                        imageUrl: posterUrl(m),
                        width: 120,
                        height: 180,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 120,
                          height: 180,
                          color: panel2,
                          child: const Icon(Icons.image_not_supported_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${formatLabel(s(m['format']))} · ${s(m['seasonYear']).isEmpty ? '—' : s(m['seasonYear'])} · ${s(m['status'])}',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                      Text(
                        safeTitle(m),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 25, height: 1.05),
                      ),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          ...((m['genres'] as List?) ?? const []).take(6).map(
                                (g) => Chip(
                                  label: Text(s(g)),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                          if (widget.store.favorites.contains(id)) const Chip(label: Text('★ Favourite')),
                        ],
                      ),
                      Text(
                        '${total > 0 ? '$total episodes' : 'Episode count not announced'} · ${m['duration'] ?? '?'} min · ${m['averageScore'] != null ? (double.tryParse(s(m['averageScore'])) ?? 0) / 10.0 : 0.0}/10',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        s(m['description']).isEmpty ? 'No description available.' : s(m['description']),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFA4AEC1), height: 1.45, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _statusBtn('WATCHING', 'Watching'),
                          _statusBtn('COMPLETED', 'Completed'),
                          _statusBtn('PLANNING', 'Plan'),
                          OutlinedButton(
                            onPressed: () {
                              widget.store.setFavorite(id);
                              setState(() {});
                            },
                            child: Text(widget.store.favorites.contains(id) ? '★ Favourite' : '☆ Favourite'),
                          ),
                        ],
                      ),
                      if (airing != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Next: Episode ${airing['episode']} · ${DateFormat('dd MMM, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(((airing['airingAt'] as num).toInt()) * 1000).toLocal())}',
                            style: const TextStyle(color: green, fontWeight: FontWeight.w700, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: () => watchEpisode(context, widget.store, m, widget.store.nextEpisode(id)),
                  child: const Text('Watch next'),
                ),
                OutlinedButton(
                  onPressed: () => widget.store.markNext(id),
                  child: const Text('Mark next'),
                ),
                OutlinedButton(
                  onPressed: () => _markThrough(context, total),
                  child: const Text('Mark through…'),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: jump,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Episode'),
                  ),
                ),
                OutlinedButton(
                  onPressed: () {
                    final n = int.tryParse(jump.text);
                    if (n != null && n > 0) {
                      setState(() => page = max(0, (n - 1) ~/ 100));
                    }
                  },
                  child: const Text('Go'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Episodes', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const Spacer(),
                Text(
                  '${watched.length}/${total > 0 ? total : '?'} watched',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
            if (total > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Wrap(
                  spacing: 5,
                  children: List.generate(
                    (total / 100).ceil(),
                    (i) => ChoiceChip(
                      label: Text('${i * 100 + 1}-${min(total, (i + 1) * 100)}'),
                      selected: page == i,
                      onSelected: (_) => setState(() => page = i),
                    ),
                  ),
                ),
              ),
            if (total == 0)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'AniList has not published a total episode count yet. The app will use next airing data for tracking.',
                  style: TextStyle(color: muted),
                ),
              ),
            if (total > 0)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: end - start + 1,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: 5,
                  mainAxisSpacing: 5,
                  childAspectRatio: 1.45,
                ),
                itemBuilder: (_, i) {
                  final ep = start + i;
                  final done = watched.contains(ep);
                  return Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: done ? accent : panel2,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => watchEpisode(context, widget.store, m, ep),
                          child: Text('${done ? '✓ ' : ''}$ep', style: const TextStyle(fontSize: 10)),
                        ),
                      ),
                      SizedBox(
                        width: 24,
                        child: IconButton(
                          onPressed: () => widget.store.toggleEpisode(id, ep),
                          icon: const Icon(Icons.check, size: 13),
                          padding: EdgeInsets.zero,
                          tooltip: 'Mark watched',
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusBtn(String value, String label) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: (widget.store.library[mId()]?.status == value) ? accent : panel2,
        ),
        onPressed: () {
          widget.store.addToLibrary(widget.m, value);
          setState(() {});
        },
        child: Text(label),
      );

  int mId() => widget.m['id'] as int;

  Future<void> _markThrough(BuildContext c, int total) async {
    final ctl = TextEditingController();
    final n = await showDialog<int>(
      context: c,
      builder: (_) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Mark watched through'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1–${total > 0 ? total : 'current'}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(ctl.text)), child: const Text('Mark')),
        ],
      ),
    );
    ctl.dispose();
    if (n != null && n > 0) widget.store.markThrough(mId(), n);
  }
}

Future<void> showPoster(BuildContext context,String url,String title){return showDialog(context:context,barrierColor:Colors.black.withOpacity(.85),builder:(_)=>Dialog(backgroundColor:Colors.transparent,child:Stack(children:[InteractiveViewer(child:ClipRRect(borderRadius:BorderRadius.circular(14),child:CachedNetworkImage(imageUrl:url,fit:BoxFit.contain))),Positioned(right:0,top:0,child:IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close)))])));}

Future<void> showDetails(BuildContext context, AnimeVaultStore store, Map<String, dynamic> initial) async {
  final m = await store.loadDetails(initial['id'] as int) ?? initial;
  if (!context.mounted) return;
  showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: bg, builder: (_) => DetailSheet(store: store, m: m));
}

Future<void> showSettings(BuildContext context, AnimeVaultStore store) async {
  await showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: bg, builder: (_) => SettingsSheet(store: store));
}

Future<void> watchEpisode(BuildContext context, AnimeVaultStore store, Map<String, dynamic> m, int ep) async {
  if (matureMedia(m) && !(store.matureStreamingEnabled && store.is18Confirmed)) {
    await showSettings(context, store);
    return;
  }
  if (!store.streamingEnabled) {
    await showSettings(context, store);
    return;
  }
  final exact = <Map<String, String>>[];
  final seen = <String>{};
  for (final x in ((m['streamingEpisodes'] as List?) ?? []).whereType<Map>()) {
    final label = s(x['title']);
    final match = RegExp(r'(?:episode|ep\.?|#)\s*([0-9]+)', caseSensitive:false).firstMatch(label);
    if (match == null || int.tryParse(match.group(1)!) != ep) continue;
    final url = s(x['url']);
    if (url.isEmpty || !seen.add(url)) continue;
    exact.add({'name': s(x['site']).isEmpty ? 'Streaming link' : s(x['site']), 'url': url, 'desc': 'Exact episode $ep link from AniList'});
  }
  final title = safeTitle(m);
  final names = ['Crunchyroll','YouTube','Muse India · YouTube','Ani-One · YouTube','Prime Video','Netflix','JustWatch India','Custom Provider'];
  final defaults = <String>[
    'https://www.crunchyroll.com/search?q={title}',
    'https://www.youtube.com/results?search_query={title}+episode+{episode}+official',
    'https://www.youtube.com/results?search_query=Muse+India+{title}+episode+{episode}',
    'https://www.youtube.com/results?search_query=Ani-One+{title}+episode+{episode}',
    'https://www.primevideo.com/search/ref=atv_nb_sr?phrase={title}+episode+{episode}',
    'https://www.netflix.com/search?q={title}',
    'https://www.justwatch.com/in/search?q={title}',
    '',
  ];
  final providers = <Map<String, String>>[];
  for (var i=0;i<8;i++) {
    var tpl = store.providerUrls[i].trim();
    if (tpl.isEmpty) tpl = defaults[i];
    if (tpl.isEmpty) continue;
    final url = tpl.replaceAll('{title}', Uri.encodeComponent(title)).replaceAll('{episode}', '$ep').replaceAll('{slug}', title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'));
    providers.add({'name': names[i], 'url': url, 'desc': i == 7 ? 'Saved custom provider' : 'Saved provider link'});
  }
  final all = [...exact, ...providers];
  final chosen = await showModalBottomSheet<Map<String,String>>(
    context: context, isScrollControlled: true, backgroundColor: panel,
    builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(14,16,14,10), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('WATCH EPISODE',style:TextStyle(color:muted,fontSize:10,fontWeight:FontWeight.w800)),Text('$title — Episode $ep',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:20))])),IconButton(onPressed:()=>Navigator.pop(_),icon:const Icon(Icons.close))]),
      const Text('Choose a viewing provider. AnimeVault does not host video; availability varies by country.',style:TextStyle(color:muted,fontSize:11)),
      const SizedBox(height:10),
      if(exact.isNotEmpty) ...[const Text('Exact episode links',style:TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:6)],
      Flexible(child: ListView(shrinkWrap:true, children: all.map((p)=>ListTile(leading:const Icon(Icons.play_circle_outline),title:Text(p['name']!,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(p['desc']!,style:const TextStyle(color:muted,fontSize:10)),trailing:const Icon(Icons.open_in_new,size:18),onTap:()=>Navigator.pop(context,p))).toList())),
      const SizedBox(height:4), Text('Your provider URLs are saved on this device and can be edited once in Settings.',style:const TextStyle(color:muted,fontSize:10))
    ]))));
  if (chosen == null || chosen['url']!.isEmpty) return;
  final uri = Uri.tryParse(chosen['url']!);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok || !context.mounted) return;
  final mark = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => AlertDialog(backgroundColor: panel, title: const Text('Finished the episode?'), content: Text('Mark $title episode $ep as watched?'), actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Not yet')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Yes, mark watched'))]));
  if (mark == true) {
    if (store.library[m['id'] as int] == null) store.addToLibrary(m,'WATCHING');
    store.markThrough(m['id'] as int, ep);
  }
}

class DashboardSheet extends StatelessWidget {
  final AnimeVaultStore store;

  const DashboardSheet({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final entries = store.library.values.toList()..sort((a, b) => b.watchMinutes.compareTo(a.watchMinutes));
    final top = entries.take(10).toList();
    final byProgress = entries.toList()..sort((a, b) => b.progress.compareTo(a.progress));

    return DraggableScrollableSheet(
      initialChildSize: .92,
      maxChildSize: .97,
      builder: (_, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AnimeVault Watch Report', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _stat('Watchlist', store.library.values.where((e) => e.status != 'COMPLETED').length.toString()),
                _stat('Completed', store.library.values.where((e) => e.status == 'COMPLETED').length.toString()),
                _stat('Episodes', store.watchedEpisodes().toString()),
                _stat('Watch time', '${store.watchHours().toStringAsFixed(1)}h'),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Watch time by anime', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            ...top.map(
              (e) => _bar(
                context,
                e.title,
                top.isEmpty ? 0 : e.watchMinutes / max(1, top.first.watchMinutes),
                '${(e.watchMinutes / 60).toStringAsFixed(1)}h',
                () => showDetails(context, store, store.cache[e.id] ?? storeToMedia(e)),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Episode progress', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            ...byProgress.take(10).map(
              (e) => _bar(
                context,
                e.title,
                e.progress / 100,
                '${e.progress.round()}%',
                () => showDetails(context, store, store.cache[e.id] ?? storeToMedia(e)),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Data & Export', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: store.exportCsv, icon: const Icon(Icons.table_chart_outlined), label: const Text('CSV / Excel')),
                OutlinedButton.icon(onPressed: store.exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF report')),
                OutlinedButton.icon(onPressed: store.exportJson, icon: const Icon(Icons.download_outlined), label: const Text('Backup')),
                OutlinedButton.icon(onPressed: store.importJson, icon: const Icon(Icons.upload_file_outlined), label: const Text('Restore')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Container(
        width: 145,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: muted, fontSize: 10)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          ],
        ),
      );

  Widget _bar(BuildContext c, String label, double value, String textValue, VoidCallback tap) => InkWell(
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(width: 110, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
              Expanded(
                child: Container(
                  height: 9,
                  decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(6)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: min(1, max(0, value)),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [accent, pink]),
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 48, child: Text(textValue, textAlign: TextAlign.right, style: const TextStyle(color: muted, fontSize: 10))),
            ],
          ),
        ),
      );
}

Map<String,dynamic> storeToMedia(LibraryEntry e)=>{'id':e.id,'title':{'romaji':e.title},'coverImage':{'extraLarge':e.poster},'episodes':e.total,'duration':e.duration,'status':e.airingStatus};

class SettingsSheet extends StatefulWidget { final AnimeVaultStore store; const SettingsSheet({super.key,required this.store}); @override State<SettingsSheet> createState()=>_SettingsSheetState(); }
class _SettingsSheetState extends State<SettingsSheet>{final providerCtrls=List.generate(8,(i)=>TextEditingController()); @override void initState(){super.initState(); for(var i=0;i<8;i++) providerCtrls[i].text=widget.store.providerUrls[i];} @override void dispose(){for(final c in providerCtrls)c.dispose();super.dispose();} @override Widget build(BuildContext context){return DraggableScrollableSheet(initialChildSize:.9,maxChildSize:.97,builder:(_,scroll)=>SingleChildScrollView(controller:scroll,padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Settings',style:TextStyle(fontWeight:FontWeight.w900,fontSize:25)),SwitchListTile(value:widget.store.matureEnabled,onChanged:(v){setState(()=>widget.store.matureEnabled=v);widget.store.persist();},title:const Text('Enable separate Mature area'),subtitle:const Text('Mature content stays isolated from the normal catalog.',style:TextStyle(color:muted))),SwitchListTile(value:widget.store.streamingEnabled,onChanged:(v){setState(()=>widget.store.streamingEnabled=v);widget.store.persist();},title:const Text('Enable external streaming'),subtitle:const Text('Shows provider links in the Watch Episode dialog.',style:TextStyle(color:muted))),SwitchListTile(value:widget.store.matureStreamingEnabled,onChanged:(v){setState(()=>widget.store.matureStreamingEnabled=v);widget.store.persist();},title:const Text('Enable 18+ provider links')),SwitchListTile(value:widget.store.is18Confirmed,onChanged:(v){setState(()=>widget.store.is18Confirmed=v);widget.store.persist();},title:const Text('I am 18+ and want to show the 18+ provider')),const Divider(height:28),const Text('External providers',style:TextStyle(fontWeight:FontWeight.w900,fontSize:18)),const Text('Add provider URL templates using {title}, {episode} and optionally {slug}.',style:TextStyle(color:muted,fontSize:11)),for(var i=0;i<8;i++)Padding(padding:const EdgeInsets.only(top:8),child:TextField(controller:providerCtrls[i],decoration:InputDecoration(labelText:'Provider ${i+1}',hintText:'https://example.com/watch/{title}?ep={episode}'))),const SizedBox(height:8),FilledButton.tonal(onPressed:(){for(var i=0;i<8;i++) widget.store.providerUrls[i]=providerCtrls[i].text.trim();widget.store.persist();ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Provider links saved on this device')));},child:const Text('Save provider links')),const SizedBox(height:6),OutlinedButton(onPressed:(){const d=['https://www.crunchyroll.com/search?q={title}','https://www.youtube.com/results?search_query={title}+episode+{episode}+official','https://www.youtube.com/results?search_query=Muse+India+{title}+episode+{episode}','https://www.youtube.com/results?search_query=Ani-One+{title}+episode+{episode}','https://www.primevideo.com/search/ref=atv_nb_sr?phrase={title}+episode+{episode}','https://www.netflix.com/search?q={title}','https://www.justwatch.com/in/search?q={title}',''];for(var i=0;i<8;i++){providerCtrls[i].text=d[i];widget.store.providerUrls[i]=d[i];}widget.store.persist();setState((){});},child:const Text('Restore default 8 provider slots')) ,const SizedBox(height:12),const Text('API Sources',style:TextStyle(fontWeight:FontWeight.w900,fontSize:18)),const Text('AniList · Jikan · Kitsu · AnimeChan · Waifu.im · NekosBest · AnimeFacts · Trace.moe',style:TextStyle(color:muted,fontSize:11)),if(widget.store.selected!=null)Padding(padding:const EdgeInsets.only(top:8),child:FilledButton.tonal(onPressed:()async{final out=await widget.store.enrich(widget.store.selected!);if(context.mounted)showDialog(context:context,builder:(_)=>AlertDialog(backgroundColor:panel,title:const Text('API enrichment'),content:SizedBox(width:420,child:ListView(shrinkWrap:true,children:out.map((x)=>Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Text('• $x',style:const TextStyle(fontSize:12)))).toList())),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close'))]));},child:const Text('Enrich current anime'))),const SizedBox(height:18),const Text('Data',style:TextStyle(fontWeight:FontWeight.w900,fontSize:18)),Wrap(spacing:8,runSpacing:8,children:[OutlinedButton(onPressed:widget.store.exportCsv,child:const Text('Export CSV')),OutlinedButton(onPressed:widget.store.exportJson,child:const Text('Export backup')),OutlinedButton(onPressed:widget.store.importJson,child:const Text('Import backup')),OutlinedButton(onPressed:()async{final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(backgroundColor:panel,title:const Text('Reset local data?'),content:const Text('This removes your AnimeVault library and favourites from this device.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Reset'))]));if(ok==true){widget.store.library.clear();widget.store.favorites.clear();await widget.store.persist();if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Local data reset')));}} ,child:const Text('Reset local data'))])])));}
}

class MatureSheet extends StatefulWidget { final AnimeVaultStore store; const MatureSheet({super.key,required this.store}); @override State<MatureSheet> createState()=>_MatureSheetState(); }
class _MatureSheetState extends State<MatureSheet>{int tab=0;List<Map<String,dynamic>> rows=[];bool loading=false;String error='';DateTime day=DateTime(DateTime.now().year,DateTime.now().month,DateTime.now().day);
 @override void initState(){super.initState();load();}
 Future<void> load()async{setState(() { loading = true; error = ''; });try{if(tab==0){rows=await widget.store.api.catalog(page:1,perPage:25,search:widget.store.search,sort:'POPULARITY_DESC',adult:true);}else if(tab==1){final sched=await widget.store.api.schedule(day,day.add(const Duration(days:1)),adult:true);rows=sched.map((r)=>(r['media'] as Map).cast<String,dynamic>()).toList();}else{final sec=tab==2?'watchlist':'completed';rows=widget.store.libraryBy(sec).where((e)=>e.mature).map(storeToMedia).toList();} }catch(e){rows=[];error=e.toString();}if(mounted)setState(()=>loading=false);}
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .94,
      maxChildSize: .99,
      builder: (_, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mature', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24)),
                      Text('Separate 18+ / adult area', style: TextStyle(color: muted, fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                _tab('Browse', 0),
                _tab('Schedule', 1),
                _tab('Watching', 2),
                _tab('Completed', 3),
              ],
            ),
            const SizedBox(height: 10),
            if (tab == 1)
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() => day = day.subtract(const Duration(days: 1)));
                      load();
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        DateFormat('EEEE, dd MMM yyyy').format(day),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => day = day.add(const Duration(days: 1)));
                      load();
                    },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rows.isEmpty)
              Column(
                children: [
                  emptyCard(error.isEmpty ? 'No mature titles found for this section.' : error),
                  const SizedBox(height: 8),
                  TextButton.icon(onPressed: load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                ],
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rows.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 9,
                  mainAxisSpacing: 9,
                  childAspectRatio: .62,
                ),
                itemBuilder: (_, i) => MediaCard(
                  m: rows[i],
                  store: widget.store,
                  onOpen: () => showDetails(context, widget.store, rows[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
 Widget _tab(String t,int i)=>ChoiceChip(label:Text(t),selected:tab==i,onSelected:(_){setState(()=>tab=i);load();});
 Widget emptyCard(String t)=>Container(width:double.infinity,padding:const EdgeInsets.all(24),decoration:BoxDecoration(border:Border.all(color:line),borderRadius:BorderRadius.circular(16)),child:Center(child:Text(t,textAlign:TextAlign.center,style:const TextStyle(color:muted))));
}

void main()=>runApp(const AnimeVaultApp());
