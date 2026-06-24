import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';

/// Thrown when an Appe API call returns `status: false` or a transport error.
class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when the backend rejects the API token (Frappe `AuthenticationError`
/// / HTTP 401 / 403). The backend rotates `api_secret` on every `login_user`
/// call, so an older token can become stale — callers should prompt re-login
/// rather than surface the raw server traceback.
class AuthException implements Exception {
  AuthException([this.message = 'Your session has expired. Please sign in again.']);
  final String message;
  @override
  String toString() => message;
}

/// Client for the Appe Frappe backend (`appe.appe_api.*`).
///
/// Endpoint names and the request/response shapes mirror the real backend
/// (see `appe/appe_api.py` in this repo). Frappe whitelisted methods are called
/// as `POST {site}/api/method/{dotted.path}` and the payload is returned under
/// the top-level `message` key.
class AppeApi {
  AppeApi._(this._site, this._token);

  final String _site;
  String? _token; // "token api_key:api_secret" — refreshed by silent re-auth

  static const _secure = FlutterSecureStorage();

  /// Builds a client from saved site + token.
  static Future<AppeApi> create() async {
    final prefs = await SharedPreferences.getInstance();
    final site = prefs.getString(AppeApi._kSite) ??
        prefs.getString(AppConfig.prefSiteUrl) ??
        AppConfig.defaultSiteUrl;
    final token = prefs.getString(AppeApi._kToken);
    return AppeApi._(site, token);
  }

  static const _kSite = 'appe_site_url';
  static const _kToken = 'appe_token';
  static const _kUser = 'appe_user';
  static const _kLoginUsr = 'appe_login_usr';
  static const _kSecurePwd = 'appe_login_pwd';

  bool get isAuthenticated => _token != null;
  String get site => _site;

  Map<String, String> get _headers {
    final h = {'Accept': 'application/json'};
    final t = _token;
    if (t != null) h['Authorization'] = t;
    return h;
  }

  Uri _method(String dotted) =>
      Uri.parse('$_site/api/method/$dotted');

  /// Runs a request and, if the token is stale (rotated by another login),
  /// silently re-authenticates once with the saved credentials and retries —
  /// so the user is not bounced to the login screen.
  Future<Map<String, dynamic>> _send(
      Future<http.Response> Function() request) async {
    try {
      return _unwrap(await request());
    } on AuthException {
      if (await _reauth()) {
        return _unwrap(await request()); // retry with refreshed _token
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _post(
          String dotted, Map<String, dynamic> body) =>
      _send(() => http.post(_method(dotted),
          headers: _headers, body: _encode(body)));

  Future<Map<String, dynamic>> _get(String dotted) =>
      _send(() => http.get(_method(dotted), headers: _headers));

  /// Re-authenticate with stored credentials and refresh the token in place.
  Future<bool> _reauth() async {
    final prefs = await SharedPreferences.getInstance();
    final usr = prefs.getString(_kLoginUsr);
    final pwd = await _secure.read(key: _kSecurePwd);
    if (usr == null || pwd == null) return false;
    try {
      _token = await _rawLogin(_site, usr, pwd);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Calls `login_user`, persists + returns the fresh token. Shared by
  /// interactive login and silent re-auth.
  static Future<String> _rawLogin(
      String site, String usr, String pwd) async {
    final client = AppeApi._(site, null);
    final msg = await client._unwrapDirect(await http.post(
      client._method('appe.appe_api.login_user'),
      headers: const {'Accept': 'application/json'},
      body: {'usr': usr, 'pwd': pwd},
    ));
    final data = msg['data'] as Map<String, dynamic>?;
    final token = data?['token'] as String?;
    if (token == null) {
      throw ApiException(msg['message']?.toString() ?? 'Login failed.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSite, site);
    await prefs.setString(_kToken, token);
    await prefs.setString(_kUser, data?['user']?.toString() ?? usr);
    return token;
  }

  // login_user never returns 401, so no recursion risk here.
  Future<Map<String, dynamic>> _unwrapDirect(http.Response res) =>
      Future.value(_unwrap(res));

  // Frappe accepts form-encoded bodies; nested values go as JSON strings.
  Map<String, String> _encode(Map<String, dynamic> body) => body.map(
        (k, v) => MapEntry(
          k,
          v is String ? v : jsonEncode(v),
        ),
      );

  Map<String, dynamic> _unwrap(http.Response res) {
    // Token rejected / not permitted → surface as a clean auth error.
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw AuthException();
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      throw ApiException('Unexpected server response (${res.statusCode}).');
    }
    // Frappe exception envelope: {"exc_type": "...", "exception": "..."}.
    if (decoded is Map && decoded['exc_type'] != null) {
      final type = decoded['exc_type'].toString();
      if (type.contains('Authentication')) throw AuthException();
      if (type.contains('Permission')) {
        throw ApiException('You do not have permission to view this.');
      }
      throw ApiException(type);
    }
    if (res.statusCode >= 500) {
      throw ApiException('Server error (${res.statusCode}).');
    }
    final msg = decoded is Map && decoded.containsKey('message')
        ? decoded['message']
        : decoded;
    if (msg is Map && msg['status'] == false) {
      throw ApiException(msg['message']?.toString() ?? 'Request failed.');
    }
    return msg is Map<String, dynamic> ? msg : {'data': msg};
  }

  /// Generic `frappe.client.get_list` wrapper (token-authed).
  Future<List<dynamic>> getList(
    String doctype, {
    Map<String, dynamic>? filters,
    List<String>? fields,
    String orderBy = 'creation desc',
    int limit = 50,
  }) async {
    final body = <String, dynamic>{
      'doctype': doctype,
      'fields': fields ?? const ['name'],
      'order_by': orderBy,
      'limit_page_length': limit,
    };
    if (filters != null && filters.isNotEmpty) body['filters'] = filters;
    final m = await _post('frappe.client.get_list', body);
    return (m['data'] as List?) ?? const [];
  }

  /// Notification Log entries for the logged-in user.
  /// [read]: -1 = all, 0 = unread, 1 = read.
  Future<List<dynamic>> notifications({int read = -1}) {
    return getList(
      'Notification Log',
      filters: read >= 0 ? {'read': read} : null,
      fields: const [
        'name',
        'subject',
        'email_content',
        'type',
        'read',
        'document_type',
        'document_name',
        'from_user',
        'creation',
      ],
      orderBy: 'creation desc',
      limit: 50,
    );
  }

  // --- Auth ---------------------------------------------------------------

  /// `appe.appe_api.login_user(usr, pwd)` → persists token + credentials so the
  /// session can be silently restored after the backend rotates the secret.
  static Future<AppeApi> login(
      String site, String usr, String pwd) async {
    final token = await _rawLogin(site, usr, pwd);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLoginUsr, usr);
    await _secure.write(key: _kSecurePwd, value: pwd);
    return AppeApi._(site, token);
  }

  /// True if credentials are stored (so we can auto-login on launch).
  static Future<bool> hasSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLoginUsr) != null &&
        await _secure.read(key: _kSecurePwd) != null;
  }

  /// Saved site URL / login id, for prefilling the login form.
  static Future<String?> savedSite() async =>
      (await SharedPreferences.getInstance()).getString(_kSite);
  static Future<String?> savedLoginUsr() async =>
      (await SharedPreferences.getInstance()).getString(_kLoginUsr);

  /// Attempts a silent login from stored credentials. Returns a ready client,
  /// or null if no credentials / login failed.
  static Future<AppeApi?> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final site = prefs.getString(_kSite) ?? AppConfig.defaultSiteUrl;
    final usr = prefs.getString(_kLoginUsr);
    final pwd = await _secure.read(key: _kSecurePwd);
    if (usr == null || pwd == null) return null;
    try {
      final token = await _rawLogin(site, usr, pwd);
      return AppeApi._(site, token);
    } catch (_) {
      return null;
    }
  }

  Future<void> sendOtp() => _get('appe.appe_api.sendOTP');

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
    await prefs.remove(_kLoginUsr);
    await _secure.delete(key: _kSecurePwd);
  }

  // --- Generic doc helpers ------------------------------------------------

  /// `frappe.client.get` — fetch a full document.
  Future<Map<String, dynamic>> getDoc(String doctype, String name) async {
    final m = await _post('frappe.client.get', {
      'doctype': doctype,
      'name': name,
    });
    final data = m['data'] ?? m;
    return data is Map<String, dynamic>
        ? data
        : (data is Map ? data.cast<String, dynamic>() : <String, dynamic>{});
  }

  /// Single value of a Number Card (`Number Card View` dashboard items).
  /// Fetches the card doc, then `get_result(doc, filters=[])` → a number.
  Future<double?> numberCardValue(String name) async {
    final doc = await getDoc('Number Card', name);
    final m = await _post(
      'frappe.desk.doctype.number_card.number_card.get_result',
      {'doc': doc, 'filters': const []},
    );
    final v = m['data'] ?? m['message'];
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  /// Dashboard Chart series (`Chart View` items) →
  /// `{ "labels": [...], "datasets": [{ "name", "values": [...] }] }`.
  Future<Map<String, dynamic>> dashboardChart(String name) async {
    final res = await http.get(
      _method(
              'frappe.desk.doctype.dashboard_chart.dashboard_chart.get')
          .replace(queryParameters: {'chart_name': name}),
      headers: _headers,
    );
    final m = _unwrap(res);
    final data = m['data'] ?? m;
    return data is Map<String, dynamic>
        ? data
        : (data is Map ? data.cast<String, dynamic>() : <String, dynamic>{});
  }

  /// Chart render type (Bar / Line / Pie / Donut / Percentage).
  Future<String> chartType(String name) async {
    try {
      final m = await _post('frappe.client.get_value', {
        'doctype': 'Dashboard Chart',
        'filters': {'name': name},
        'fieldname': 'type',
      });
      final d = m['data'] ?? m;
      final t = (d is Map ? d['type'] : null)?.toString();
      return (t == null || t.isEmpty) ? 'Bar' : t;
    } catch (_) {
      return 'Bar';
    }
  }

  /// `frappe.client.set_value` — update a single field on a document.
  Future<void> setValue(
          String doctype, String name, String field, dynamic value) =>
      _post('frappe.client.set_value', {
        'doctype': doctype,
        'name': name,
        'fieldname': field,
        'value': value,
      });

  Future<void> markNotificationRead(String name) =>
      setValue('Notification Log', name, 'read', 1);

  /// Change the signed-in user's password via Frappe's standard
  /// `update_password` (validates [oldPassword] before applying [newPassword]).
  Future<void> changePassword(String oldPassword, String newPassword) =>
      _post('frappe.core.doctype.user.user.update_password', {
        'old_password': oldPassword,
        'new_password': newPassword,
        'logout_all_sessions': 0,
      });

  // --- Dashboard / modules ------------------------------------------------

  Future<dynamic> dashboardSections() async =>
      (await _get('appe.appe_api.get_dashboard_sections'))['data'] ??
      (await _get('appe.appe_api.get_dashboard_sections'));

  Future<dynamic> moduleData() async =>
      (await _get('appe.appe_api.get_module_data'));

  Future<dynamic> tasksRequestsAttendance() async =>
      (await _get('appe.appe_api.gettasks_and_request_and_attendancedata'));

  Future<dynamic> leaveBalance() async =>
      (await _get('appe.appe_api.leave_balance'));

  Future<dynamic> userDetails() async =>
      (await _get('appe.appe_api.user_details'));

  Future<dynamic> employeeDetails() async =>
      (await _get('appe.appe_api.employee_details'));

  Future<dynamic> checkinStatus() async =>
      (await _get('appe.appe_api.employee_checkin_status'));

  Future<dynamic> employeeCheckin(Map<String, dynamic> payload) async =>
      _post('appe.appe_api.employee_checkin', payload);

  Future<dynamic> appePosts({int start = 0, int pageLength = 10}) async =>
      _post('appe.appe_api.get_appe_posts',
          {'limit_start': start, 'limit_page_length': pageLength});

  /// `appe.appe_api.storelocation` — accepts a batched `locations` array.
  Future<void> storeLocations(List<Map<String, dynamic>> locations) =>
      _post('appe.appe_api.storelocation', {'locations': locations});

  // --- AI "Appe Buddy" (appe.ai.api.*) -----------------------------------
  // Envelope is {status, data}; methods return the inner `data`.

  Future<List<dynamic>> aiListConversations() async {
    final m = await _get('appe.ai.api.list_conversations');
    return (m['data'] as List?) ?? const [];
  }

  Future<Map<String, dynamic>> aiGetConversation(String name) async {
    final m = await _post('appe.ai.api.get_conversation', {'name': name});
    return (m['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Sends a chat message; backend creates the conversation if [conversation]
  /// is null. Returns the inner `data` from `send_message`.
  Future<Map<String, dynamic>> aiSendMessage(String message,
      {String? conversation}) async {
    final body = <String, dynamic>{'message': message};
    if (conversation != null) body['conversation'] = conversation;
    final m = await _post('appe.ai.api.send_message', body);
    return (m['data'] as Map<String, dynamic>?) ?? {};
  }
}
