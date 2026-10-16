import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

part 'screens.dart';
part 'forms.dart';

typedef Json = Map<String, dynamic>;

const ink = Color(0xFF182E2A);
const green = Color(0xFF176B50);
const muted = Color(0xFF788680);
const canvas = Color(0xFFF4F7F5);
const line = Color(0xFFE5ECE7);
const amber = Color(0xFFAC7635);
const scheduleLabels = {
  'salary': '給料日',
  'bank': '銀行口座の引き落とし日',
  'closing': 'クレカの締日',
  'credit': 'クレカ利用可能額の更新日',
};
const defaultSchedule = {
  'bank': 27,
  'closing': 15,
  'credit': 1,
  'salary': 25,
};
const avatars = [
  Icons.person_outline,
  Icons.spa_outlined,
  Icons.pets_outlined,
  Icons.coffee_outlined,
  Icons.nightlight_outlined,
  Icons.favorite_outline,
];
const statusLabels = {
  'pending': '承認待ち',
  'active': '返済予定',
  'repayment_pending': '受取確認待ち',
  'repaid': '返済済み',
  'rejected': '辞退',
  'cancelled': '取消済み',
};
const setupMessage =
    'Firebase の設定が未完了です。README の手順に従って flutterfire configure を実行してください。';
const operationDenied =
    'この操作はできません。画面を更新して状態を確認してください。';

DateTime nextDue(int day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  for (var i = 0; i < 14; i++) {
    final first = DateTime(now.year, now.month + i);
    final last = DateTime(first.year, first.month + 1, 0).day;
    final result = DateTime(
      first.year,
      first.month,
      day.clamp(1, last),
    ).add(const Duration(days: 1));
    if (!result.isBefore(today)) return result;
  }
  return today;
}

String iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String shortDate(String s) {
  final d = DateTime.tryParse(s);
  return d == null ? '未設定' : '${d.month}/${d.day}';
}

String fullDate(String s) {
  final d = DateTime.tryParse(s);
  return d == null ? '未設定' : '${d.year}年${d.month}月${d.day}日';
}

String yen(num ticks, {bool decimal = false}) {
  final value = ticks.round();
  final whole = (value ~/ 10).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '¥$whole${decimal || value % 10 != 0 ? '.${value % 10}' : ''}';
}

int parseTicks(String s) {
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s.trim())) return 0;
  final parts = s.trim().split('.');
  final whole = int.tryParse(parts[0]);
  if (whole == null || whole > 100000000 || s.length > 30) return 0;
  final decimals = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
  return whole * 10 +
      int.parse(decimals[0]) +
      (int.parse(decimals[1]) >= 5 ? 1 : 0);
}

int splitTicks(int total, int count) =>
    count <= 0 ? 0 : (total * 2 + count) ~/ (2 * count);

int splitDecimalTicks(String value, int count) {
  final s = value.trim();
  if (count <= 0 || parseTicks(s) <= 0) return 0;
  final parts = s.split('.');
  final decimals = parts.length == 2 ? parts[1] : '';
  final numerator = BigInt.parse(parts[0] + decimals) * BigInt.from(10);
  final denominator = BigInt.from(10).pow(decimals.length) * BigInt.from(count);
  return ((numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two))
      .toInt();
}

String message(Object e) {
  if (e is FirebaseException) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return 'メールアドレスまたはパスワードが違います。';
      case 'email-already-in-use':
        return 'このメールアドレスはすでに登録されています。';
      case 'weak-password':
        return 'パスワードは8〜128文字で入力してください。';
      case 'too-many-requests':
        return '試行回数が多すぎます。しばらくしてからお試しください。';
      case 'network-request-failed':
      case 'unavailable':
        return 'サーバーに接続できません。通信状態を確認してください。';
      case 'permission-denied':
        return operationDenied;
      default:
        return '処理できませんでした。時間をおいて再度お試しください。';
    }
  }
  if (e is Exception) {
    return e.toString().replaceFirst('Exception: ', '');
  }
  return '処理できませんでした。時間をおいて再度お試しください。';
}

class MoneyStore extends ChangeNotifier {
  Json me = {};
  List<Json> contacts = [];
  List<Json> transactions = [];
  String? error;
  DateTime? synced;
  bool ready = false;
  bool refreshing = false;

  StreamSubscription<User?>? _authSubscription;
  final List<StreamSubscription<dynamic>> _dataSubscriptions = [];
  final Set<String> _contactUids = {};
  final Map<String, Json> _peerCache = {};
  final Map<String, Future<Json?>> _peerLoads = {};
  final Map<String, Future<void>> _contactWrites = {};
  Future<void>? _profileFuture;
  String? _profileFutureUid;
  String? _pendingName;
  String? _uid;
  bool _started = false;
  bool _disposed = false;
  int _epoch = 0;
  int _cacheRevision = 0;

  MoneyStore();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  bool get loggedIn => me.isNotEmpty;
  String get id => me['id'] as String? ?? '';
  String get shareId => me['shareId'] as String? ?? '';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _failed(Object e, int epoch) {
    if (_disposed || epoch != _epoch) return;
    error = message(e);
    _notify();
  }

  void _received() {
    if (_disposed) return;
    synced = DateTime.now();
    error = null;
    _notify();
  }

  Future<void> init() async {
    if (_started || _disposed) return;
    _started = true;
    if (Firebase.apps.isEmpty) {
      me = {};
      contacts = [];
      transactions = [];
      ready = true;
      _notify();
      return;
    }
    _authSubscription = _auth.authStateChanges().listen(
      (user) {
        if (_disposed) return;
        ready = true;
        final epoch = ++_epoch;
        unawaited(_onAuthChanged(user, epoch));
      },
      onError: (Object e) {
        ready = true;
        _failed(e, _epoch);
      },
    );
  }

  Future<void> _stopDataListeners() async {
    final subscriptions =
        List<StreamSubscription<dynamic>>.from(_dataSubscriptions);
    _dataSubscriptions.clear();
    await Future.wait(subscriptions.map((s) => s.cancel()));
  }

  Future<void> _onAuthChanged(User? user, int epoch) async {
    await _stopDataListeners();
    if (_disposed || epoch != _epoch) return;
    _uid = user?.uid;
    me = {};
    contacts = [];
    transactions = [];
    error = null;
    synced = null;
    _contactUids.clear();
    _peerCache.clear();
    _peerLoads.clear();
    _contactWrites.clear();
    _cacheRevision++;
    _notify();
    if (user == null) return;

    try {
      await _ensureProfile(user);
      if (_disposed || epoch != _epoch) return;

      _dataSubscriptions.add(
        _db.collection('profiles').doc(user.uid).snapshots().listen(
          (snapshot) {
            if (_disposed || epoch != _epoch) return;
            final data = snapshot.data();
            if (data == null) {
              error = 'プロフィールを取得できませんでした。再度ログインしてください。';
              _notify();
              return;
            }
            me = _profileMap(user.uid, data);
            _received();
          },
          onError: (Object e) => _failed(e, epoch),
        ),
      );

      _dataSubscriptions.add(
        _db
            .collection('users')
            .doc(user.uid)
            .collection('contacts')
            .snapshots()
            .listen(
          (snapshot) {
            if (_disposed || epoch != _epoch) return;
            _contactUids
              ..clear()
              ..addAll(snapshot.docs.map((d) => d.id));
            unawaited(_syncPeers(epoch));
            _received();
          },
          onError: (Object e) => _failed(e, epoch),
        ),
      );

      _dataSubscriptions.add(
        _db
            .collection('transactions')
            .where('participants', arrayContains: user.uid)
            .snapshots()
            .listen(
          (snapshot) {
            if (_disposed || epoch != _epoch) return;
            transactions = snapshot.docs.map((doc) {
              final data = doc.data();
              final timestamp = data['createdAt'];
              final created = timestamp is Timestamp
                  ? timestamp.toDate()
                  : DateTime.now();
              return <String, dynamic>{
                'id': doc.id,
                'lender': data['lender'] as String? ?? '',
                'borrower': data['borrower'] as String? ?? '',
                'creator': data['creator'] as String? ?? '',
                'amount': (data['amount'] as num?)?.toInt() ?? 0,
                'memo': data['memo'] as String? ?? '',
                'due': data['due'] as String? ?? '',
                'method': data['method'] as String? ?? '',
                'created': created.toIso8601String(),
                'status': data['status'] as String? ?? 'pending',
                'approvals':
                    (data['approvals'] as List? ?? []).whereType<String>().toList(),
                'split_id': data['splitId'] as String? ?? '',
              };
            }).toList();
            transactions.sort((a, b) {
              final byDate =
                  (b['created'] as String).compareTo(a['created'] as String);
              return byDate != 0
                  ? byDate
                  : (b['id'] as String).compareTo(a['id'] as String);
            });
            for (final peer in _peerUids()) {
              if (!_contactUids.contains(peer)) {
                unawaited(_autoAddContact(peer, epoch));
              }
            }
            unawaited(_syncPeers(epoch));
            _received();
          },
          onError: (Object e) => _failed(e, epoch),
        ),
      );
    } catch (e) {
      _failed(e, epoch);
    }
  }

  Json _profileMap(String uid, Json data) {
    final source = data['schedule'];
    final schedule = <String, int>{};
    for (final key in defaultSchedule.keys) {
      final value = source is Map ? source[key] : null;
      schedule[key] = value is int && value >= 1 && value <= 31
          ? value
          : defaultSchedule[key]!;
    }
    final kind = data['defaultKind'];
    final avatar = data['avatar'];
    return {
      'id': uid,
      'name': data['name'] as String? ?? 'ユーザー',
      'avatar': avatar is int && avatar >= 0 && avatar <= 5 ? avatar : 0,
      'shareId': data['shareId'] as String? ?? '',
      'schedule': schedule,
      'defaultKind': kind is String && scheduleLabels.containsKey(kind)
          ? kind
          : 'salary',
    };
  }

  Future<void> _ensureProfile(User user) async {
    final running = _profileFuture;
    if (running != null) {
      if (_profileFutureUid == user.uid) {
        return running;
      }
      try {
        await running;
      } catch (_) {
        // 別セッションの失敗は、このセッションの作成を妨げません。
      }
    }
    final future = _createProfile(user);
    _profileFuture = future;
    _profileFutureUid = user.uid;
    try {
      await future;
    } finally {
      if (identical(_profileFuture, future)) {
        _profileFuture = null;
        _profileFutureUid = null;
      }
    }
  }

  String _randomHex(int bytes) {
    final random = Random.secure();
    return List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join().toUpperCase();
  }

  Future<void> _createProfile(User user) async {
    final ref = _db.collection('profiles').doc(user.uid);
    final existing = await ref.get();
    if (existing.exists) {
      _pendingName = null;
      return;
    }
    final rawName = _pendingName ?? user.displayName ?? 'ユーザー';
    final name = rawName.trim().isEmpty
        ? 'ユーザー'
        : String.fromCharCodes(rawName.trim().runes.take(40));
    Object? lastError;

    for (var attempt = 0; attempt < 5; attempt++) {
      if (_disposed || _auth.currentUser?.uid != user.uid) {
        throw Exception(operationDenied);
      }
      final generatedShareId = 'OS-${_randomHex(5)}';
      final batch = _db.batch();
      batch.set(_db.collection('shareIds').doc(generatedShareId), {
        'uid': user.uid,
      });
      batch.set(ref, {
        'name': name,
        'avatar': 0,
        'shareId': generatedShareId,
        'schedule': Map<String, int>.from(defaultSchedule),
        'defaultKind': 'salary',
      });
      try {
        await batch.commit();
        _pendingName = null;
        return;
      } catch (e) {
        lastError = e;
        try {
          if ((await ref.get()).exists) {
            _pendingName = null;
            return;
          }
        } catch (_) {
          // 次の試行では新しい共有IDを使います。
        }
      }
    }
    throw lastError ??
        Exception('プロフィールを作成できませんでした。再度お試しください。');
  }

  Set<String> _peerUids() {
    final result = Set<String>.from(_contactUids);
    for (final tx in transactions) {
      final lender = tx['lender'] as String? ?? '';
      final borrower = tx['borrower'] as String? ?? '';
      if (lender.isNotEmpty) result.add(lender);
      if (borrower.isNotEmpty) result.add(borrower);
    }
    result.remove(_uid);
    result.remove('');
    return result;
  }

  Future<Json?> _fetchPeer(String uid, int epoch) {
    final cached = _peerCache[uid];
    if (cached != null) return Future.value(cached);
    final existing = _peerLoads[uid];
    if (existing != null) return existing;

    final revision = _cacheRevision;
    late final Future<Json?> future;
    future = () async {
      try {
        final doc = await _db.collection('profiles').doc(uid).get();
        final data = doc.data();
        if (data == null) return null;
        final profile = _profileMap(uid, data);
        if (!_disposed && epoch == _epoch && revision == _cacheRevision) {
          _peerCache[uid] = profile;
        }
        return profile;
      } finally {
        if (identical(_peerLoads[uid], future)) {
          _peerLoads.remove(uid);
        }
      }
    }();
    _peerLoads[uid] = future;
    return future;
  }

  Future<void> _syncPeers(int epoch) async {
    if (_disposed || epoch != _epoch || _uid == null) return;
    final revision = _cacheRevision;
    final peers = _peerUids();
    try {
      await Future.wait(peers.map((uid) => _fetchPeer(uid, epoch)));
      if (_disposed || epoch != _epoch || revision != _cacheRevision) return;
      contacts = _peerUids()
          .map((uid) => _peerCache[uid])
          .whereType<Json>()
          .toList();
      contacts.sort((a, b) {
        final byName = (a['name'] as String).compareTo(b['name'] as String);
        return byName != 0
            ? byName
            : (a['id'] as String).compareTo(b['id'] as String);
      });
      _received();
    } catch (e) {
      _failed(e, epoch);
    }
  }

  Future<void> _ensureContact(String peer) async {
    final owner = _auth.currentUser?.uid;
    if (owner == null) throw Exception(operationDenied);
    if (peer == owner) throw Exception('自分自身は追加できません。');
    if (peer.isEmpty || peer.contains('/')) {
      throw Exception('アカウントが見つかりません。相手の共有IDを確認してください。');
    }
    if (_uid == owner && _contactUids.contains(peer)) return;

    final key = '$owner/$peer';
    final running = _contactWrites[key];
    if (running != null) return running;

    late final Future<void> future;
    future = () async {
      try {
        final ref =
            _db.collection('users').doc(owner).collection('contacts').doc(peer);
        if ((await ref.get()).exists) return;
        try {
          await ref.set({'addedAt': FieldValue.serverTimestamp()});
        } catch (e) {
          if (!(await ref.get()).exists) rethrow;
        }
      } finally {
        if (identical(_contactWrites[key], future)) {
          _contactWrites.remove(key);
        }
      }
    }();
    _contactWrites[key] = future;
    return future;
  }

  Future<void> _autoAddContact(String peer, int epoch) async {
    if (_disposed || epoch != _epoch) return;
    try {
      await _ensureContact(peer);
    } catch (_) {
      // 受信取引の相手の自動追加だけは失敗しても取引表示を継続します。
    }
  }

  Future<void> refresh() async {
    if (_disposed || refreshing || _uid == null || Firebase.apps.isEmpty) {
      return;
    }
    refreshing = true;
    final epoch = _epoch;
    _cacheRevision++;
    _peerCache.clear();
    _peerLoads.clear();
    try {
      await _syncPeers(epoch);
    } finally {
      if (!_disposed && epoch == _epoch) {
        refreshing = false;
        _notify();
      }
    }
  }

  void _requireFirebase() {
    if (Firebase.apps.isEmpty) throw Exception(setupMessage);
  }

  String _validatedEmail(String value) {
    final email = value.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw Exception('メールアドレスを正しく入力してください。');
    }
    return email;
  }

  String _validatedName(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      throw Exception('アカウント名を入力してください。');
    }
    final name = value.trim();
    if (name.runes.length > 40) {
      throw Exception('アカウント名は40文字以内で入力してください。');
    }
    return name;
  }

  Future<void> _waitForMe(String uid) async {
    if (loggedIn && id == uid) return;
    final completer = Completer<void>();
    void changed() {
      if (completer.isCompleted) return;
      if (_disposed) {
        completer.completeError(Exception(operationDenied));
      } else if (loggedIn && id == uid) {
        completer.complete();
      } else if (_uid == uid && error != null) {
        completer.completeError(Exception(error));
      }
    }
    addListener(changed);
    changed();
    try {
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception(
          'プロフィールの取得がタイムアウトしました。再度ログインしてください。',
        ),
      );
    } finally {
      if (!_disposed) removeListener(changed);
    }
  }

  Future<void> auth(
    bool register,
    String name,
    String email,
    String password,
  ) async {
    final address = _validatedEmail(email);
    if (password.length < 8 || password.length > 128) {
      throw Exception('パスワードは8〜128文字で入力してください。');
    }
    final accountName = register ? _validatedName(name) : '';
    _requireFirebase();
    if (!_started) await init();

    UserCredential credential;
    if (register) {
      _pendingName = accountName;
      try {
        credential = await _auth.createUserWithEmailAndPassword(
          email: address,
          password: password,
        );
      } catch (_) {
        _pendingName = null;
        rethrow;
      }
      await credential.user!.updateDisplayName(accountName);
    } else {
      _pendingName = null;
      credential = await _auth.signInWithEmailAndPassword(
        email: address,
        password: password,
      );
    }
    final user = credential.user;
    if (user == null) throw Exception(operationDenied);
    await _waitForMe(user.uid);
  }

  Future<void> resetPassword(String email) async {
    if (email.trim().isEmpty) {
      throw Exception('メールアドレスを入力してください。');
    }
    final address = _validatedEmail(email);
    _requireFirebase();
    await _auth.sendPasswordResetEmail(email: address);
  }

  Future<void> logout() async {
    _requireFirebase();
    await _auth.signOut();
  }

  int _validatedAmount(dynamic value) {
    final ticks = value is String ? parseTicks(value) : 0;
    if (ticks <= 0 || ticks > 1000000000) {
      throw Exception('金額は0より大きく、1億円以下にしてください。');
    }
    return ticks;
  }

  String _validatedMemo(dynamic value) {
    final memo = value is String ? value.trim() : '';
    if (memo.runes.length > 500) {
      throw Exception('目的のメモは500文字以内で入力してください。');
    }
    return memo;
  }

  String _validatedMethod(dynamic value) {
    final method = value is String ? value : '';
    if (!['', '現金', 'PayPay', '振り込み', 'その他'].contains(method)) {
      throw Exception('支払い方法が無効です。');
    }
    return method;
  }

  Future<String> _deadline(String borrower, dynamic value) async {
    final specified = value is String ? value.trim() : '';
    if (specified.isNotEmpty) {
      final date = DateTime.tryParse(specified);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(specified) ||
          date == null ||
          iso(date) != specified) {
        throw Exception('有効な日付を指定してください。');
      }
      if (specified.compareTo(iso(DateTime.now())) < 0) {
        throw Exception('返済期限は今日以降を指定してください。');
      }
      return specified;
    }
    Json? profile;
    if (borrower == id && me.isNotEmpty) {
      profile = me;
    } else {
      profile = await _fetchPeer(borrower, _epoch);
    }
    if (profile == null) throw Exception('アカウントが見つかりません。');
    final schedule = profile['schedule'] as Map;
    final day = schedule[profile['defaultKind']] as int;
    return iso(nextDue(day, DateTime.now()));
  }

  Json _newTransaction({
    required String lender,
    required String borrower,
    required String creator,
    required int amount,
    required String memo,
    required String due,
    required String method,
    required String splitId,
  }) => {
    'lender': lender,
    'borrower': borrower,
    'creator': creator,
    'participants': [lender, borrower],
    'amount': amount,
    'memo': memo,
    'due': due,
    'method': method,
    'createdAt': FieldValue.serverTimestamp(),
    'status': 'pending',
    'approvals': [creator],
    'splitId': splitId,
  };

  Future<void> _updateTransaction(String transactionId, String action) async {
    if (transactionId.isEmpty || transactionId.contains('/')) {
      throw Exception(operationDenied);
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception(operationDenied);
    final ref = _db.collection('transactions').doc(transactionId);

    await _db.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) throw Exception(operationDenied);
      final participants =
          (data['participants'] as List? ?? []).whereType<String>().toList();
      if (!participants.contains(uid)) throw Exception(operationDenied);
      final approvals =
          (data['approvals'] as List? ?? []).whereType<String>().toList();
      final status = data['status'];
      final creator = data['creator'];
      final lender = data['lender'];
      final borrower = data['borrower'];
      final update = <String, dynamic>{};

      switch (action) {
        case 'approve':
          if (status != 'pending' || approvals.contains(uid)) {
            throw Exception(operationDenied);
          }
          update['status'] = 'active';
          update['approvals'] = List<String>.from(approvals)..add(uid);
          break;
        case 'reject':
          if (status != 'pending' || creator == uid) {
            throw Exception(operationDenied);
          }
          update['status'] = 'rejected';
          break;
        case 'cancel':
          if (status != 'pending' || creator != uid) {
            throw Exception(operationDenied);
          }
          update['status'] = 'cancelled';
          break;
        case 'repay':
          if (status != 'active' || borrower != uid) {
            throw Exception(operationDenied);
          }
          update['status'] = 'repayment_pending';
          break;
        case 'confirm_repayment':
          if (status != 'repayment_pending' || lender != uid) {
            throw Exception(operationDenied);
          }
          update['status'] = 'repaid';
          break;
        case 'reject_repayment':
          if (status != 'repayment_pending' || lender != uid) {
            throw Exception(operationDenied);
          }
          update['status'] = 'active';
          break;
        default:
          throw Exception(operationDenied);
      }
      transaction.update(ref, update);
    });
  }

  Future<void> mutate(String path, Json data) async {
    _requireFirebase();
    final uid = _auth.currentUser?.uid;
    if (uid == null || !loggedIn || uid != id) {
      throw Exception(operationDenied);
    }

    switch (path) {
      case 'contact':
        final code = (data['code'] as String? ?? '').trim().toUpperCase();
        const notFound = 'アカウントが見つかりません。相手の共有IDを確認してください。';
        if (!RegExp(r'^OS-[0-9A-F]{10}$').hasMatch(code)) {
          throw Exception(notFound);
        }
        final mapping = await _db.collection('shareIds').doc(code).get();
        final peer = mapping.data()?['uid'];
        if (peer is! String || peer.isEmpty || peer.contains('/')) {
          throw Exception(notFound);
        }
        if (peer == uid) throw Exception('自分自身は追加できません。');
        await _ensureContact(peer);
        break;

      case 'profile':
        final name = _validatedName(data['name']);
        final avatar = data['avatar'];
        final schedule = data['schedule'];
        final kind = data['defaultKind'];
        if (avatar is! int || avatar < 0 || avatar > 5) {
          throw Exception('アイコンが無効です。');
        }
        if (schedule is! Map ||
            schedule.length != 4 ||
            !defaultSchedule.keys.every(schedule.containsKey) ||
            !defaultSchedule.keys.every((key) {
              final value = schedule[key];
              return value is int && value >= 1 && value <= 31;
            })) {
          throw Exception('各日付は1〜31日の範囲で指定してください。');
        }
        if (kind is! String || !scheduleLabels.containsKey(kind)) {
          throw Exception('標準期限を選択してください。');
        }
        await _db.collection('profiles').doc(uid).update({
          'name': name,
          'avatar': avatar,
          'schedule': {
            for (final key in defaultSchedule.keys) key: schedule[key],
          },
          'defaultKind': kind,
        });
        break;

      case 'transaction':
        final lender = data['lender'];
        final borrower = data['borrower'];
        if (lender is! String ||
            borrower is! String ||
            lender.isEmpty ||
            borrower.isEmpty ||
            lender.contains('/') ||
            borrower.contains('/') ||
            lender == borrower ||
            (uid != lender && uid != borrower)) {
          throw Exception('貸す人と借りる人は別のアカウントを指定してください。');
        }
        final amount = _validatedAmount(data['amount']);
        final memo = _validatedMemo(data['memo']);
        final method = _validatedMethod(data['method']);
        final due = await _deadline(borrower, data['due']);
        final peer = uid == lender ? borrower : lender;
        await _ensureContact(peer);
        await _db.collection('transactions').add(
          _newTransaction(
            lender: lender,
            borrower: borrower,
            creator: uid,
            amount: amount,
            memo: memo,
            due: due,
            method: method,
            splitId: '',
          ),
        );
        break;

      case 'split':
        _validatedAmount(data['amount']);
        final rawMembers = data['members'];
        if (rawMembers is! List ||
            rawMembers.any((p) => p is! String)) {
          throw Exception('請求する相手を1〜15人選択してください。');
        }
        final members = rawMembers.cast<String>().toSet().toList();
        if (members.isEmpty ||
            members.length > 15 ||
            members.contains(uid) ||
            members.any((p) => p.isEmpty || p.contains('/'))) {
          throw Exception('請求する相手を1〜15人選択してください。');
        }
        final mode = data['mode'];
        if (mode != 'equal' && mode != 'others') {
          throw Exception('割り勘モードが無効です。');
        }
        final count = members.length + (mode == 'equal' ? 1 : 0);
        final share = splitDecimalTicks(data['amount'] as String, count);
        if (share <= 0) {
          throw Exception('1人あたり0.1円以上にしてください。');
        }
        if (share > 1000000000) {
          throw Exception('金額は0より大きく、1億円以下にしてください。');
        }
        final memo = _validatedMemo(data['memo']);
        final method = _validatedMethod(data['method']);
        final deadlines = <String, String>{};
        for (final peer in members) {
          deadlines[peer] = await _deadline(peer, data['due']);
        }
        for (final peer in members) {
          await _ensureContact(peer);
        }
        final splitId = _randomHex(10);
        final batch = _db.batch();
        for (final peer in members) {
          batch.set(
            _db.collection('transactions').doc(),
            _newTransaction(
              lender: uid,
              borrower: peer,
              creator: uid,
              amount: share,
              memo: memo,
              due: deadlines[peer]!,
              method: method,
              splitId: splitId,
            ),
          );
        }
        await batch.commit();
        break;

      case 'tx_action':
        await _updateTransaction(
          data['id'] as String? ?? '',
          data['action'] as String? ?? '',
        );
        break;

      default:
        throw Exception(operationDenied);
    }
  }

  Json person(String uid) => uid == id
      ? me
      : contacts.firstWhere(
          (p) => p['id'] == uid,
          orElse: () => {'id': uid, 'name': 'メンバー', 'avatar': 0},
        );

  String name(String uid) => person(uid)['name'] as String? ?? 'メンバー';

  int balance(bool lending) => transactions
      .where(
        (t) =>
            ['active', 'repayment_pending'].contains(t['status']) &&
            t[lending ? 'lender' : 'borrower'] == id,
      )
      .fold(0, (a, t) => a + (t['amount'] as num).toInt());

  bool needsAction(Json t) =>
      (t['status'] == 'pending' &&
          !(t['approvals'] as List? ?? []).contains(id)) ||
      (t['status'] == 'repayment_pending' && t['lender'] == id);

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _cacheRevision++;
    final authSubscription = _authSubscription;
    if (authSubscription != null) {
      unawaited(authSubscription.cancel());
    }
    for (final subscription in _dataSubscriptions) {
      unawaited(subscription.cancel());
    }
    _dataSubscriptions.clear();
    super.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = DefaultFirebaseOptions.currentPlatform;
  if (options.apiKey.startsWith('YOUR_')) {
    runApp(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(setupMessage, textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  try {
    await Firebase.initializeApp(options: options);
    runApp(const MyApp());
  } catch (e) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(message(e), textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  final MoneyStore? store;
  const MyApp({super.key, this.store});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'お金シェア帳',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ja'),
    supportedLocales: const [Locale('ja')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      fontFamily: 'NotoSansJP',
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
        primary: green,
        surface: Colors.white,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: ink, fontSize: 14, height: 1.5),
        bodyLarge: TextStyle(color: ink, height: 1.5),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF6F8F6),
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    ),
    home: AppShell(store: store),
  );
}

class AppShell extends StatefulWidget {
  final MoneyStore? store;
  const AppShell({super.key, this.store});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final MoneyStore store;
  int page = 0;
  final navTitles = ['ホーム', '取引一覧', 'カレンダー', 'メンバー', 'マイページ'];
  final navIcons = [
    Icons.grid_view_rounded,
    Icons.swap_horiz_rounded,
    Icons.calendar_month_outlined,
    Icons.people_outline_rounded,
    Icons.person_outline_rounded,
  ];

  @override
  void initState() {
    super.initState();
    store = widget.store ?? MoneyStore();
    unawaited(store.init());
  }

  @override
  void dispose() {
    if (widget.store == null) store.dispose();
    super.dispose();
  }

  Future<void> auth() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (_) => AuthSheet(store: store),
  );

  Future<void> create({bool split = false}) async {
    if (!store.loggedIn) {
      await auth();
      if (!store.loggedIn) return;
    }
    if (!mounted) return;
    if (store.contacts.isEmpty) {
      await showContact(context, store);
      if (store.contacts.isEmpty) return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => TransactionForm(store: store, split: split),
    );
  }

  void select(int value) {
    setState(() => page = value);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final wide = MediaQuery.sizeOf(context).width >= 960;
      final bodies = [
        HomePage(store: store, create: create, auth: auth, select: select),
        TransactionsPage(store: store, create: create, auth: auth),
        CalendarPage(store: store),
        MembersPage(store: store, auth: auth),
        ProfilePage(store: store, auth: auth, select: select),
      ];
      final headerChildren = <Widget>[];
      if (!wide) {
        headerChildren.addAll([
          const BrandMark(size: 32),
          const SizedBox(width: 10),
          const Text(
            'お金シェア帳',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
        ]);
      } else {
        headerChildren.add(
          Text(
            navTitles[page],
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        );
      }
      headerChildren.addAll([
        const Spacer(),
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: store.loggedIn ? store.refresh : auth,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: store.error != null
                  ? const Color(0xFFFFF2E5)
                  : const Color(0xFFF0F6F2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  store.loggedIn
                      ? Icons.cloud_done_outlined
                      : Icons.lock_outline,
                  size: 15,
                  color: green,
                ),
                const SizedBox(width: 6),
                Text(
                  store.error != null
                      ? '接続を確認'
                      : store.loggedIn
                          ? '共有中'
                          : 'ログイン',
                  style: const TextStyle(
                    color: green,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ]);
      if (wide) {
        headerChildren.addAll([
          const SizedBox(width: 20),
          Avatar(person: store.me, size: 34),
        ]);
      }

      final content = Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 36 : 20,
              vertical: 18,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: Row(children: headerChildren),
          ),
          if (store.error != null)
            Material(
              color: const Color(0xFFFFF2E5),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.wifi_off, color: amber),
                title: Text(
                  store.error!,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: TextButton(
                  onPressed: store.refresh,
                  child: const Text('再接続'),
                ),
              ),
            ),
          Expanded(
            child: !store.ready
                ? const Center(child: CircularProgressIndicator())
                : bodies[page],
          ),
        ],
      );

      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                Container(
                  width: 224,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 30, 20, 32),
                        child: Row(
                          children: [
                            BrandMark(size: 36),
                            SizedBox(width: 10),
                            Text(
                              'お金シェア帳',
                              style: TextStyle(
                                color: ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 28, bottom: 14),
                        child: Text(
                          'PERSONAL MONEY',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 2,
                            color: muted,
                          ),
                        ),
                      ),
                      for (var i = 0; i < navTitles.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          child: Material(
                            color: page == i
                                ? const Color(0xFFEAF4EE)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: Icon(
                                navIcons[i],
                                color: page == i ? green : muted,
                                size: 22,
                              ),
                              title: Text(
                                navTitles[i],
                                style: TextStyle(
                                  color: page == i ? green : muted,
                                  fontWeight: page == i
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              onTap: () => select(i),
                            ),
                          ),
                        ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: canvas,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                color: green,
                                size: 22,
                              ),
                              SizedBox(height: 8),
                              Text(
                                '双方の確認で、安心。',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '承認されたやりとりだけを\n残高に反映します。',
                                style: TextStyle(color: muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(26, 0, 20, 24),
                        child: Text(
                          'OKANE SHARE  /  v1.0',
                          style: TextStyle(
                            color: muted,
                            letterSpacing: 1,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: content),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                backgroundColor: Colors.white,
                indicatorColor: const Color(0xFFE6F2EB),
                height: 70,
                selectedIndex: page,
                onDestinationSelected: select,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  for (var i = 0; i < navTitles.length; i++)
                    NavigationDestination(
                      icon: Icon(navIcons[i]),
                      label: i == 1 ? '取引' : navTitles[i],
                    ),
                ],
              ),
      );
    },
  );
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: green,
      borderRadius: BorderRadius.circular(size * .28),
    ),
    child: Icon(Icons.swap_horiz_rounded, color: Colors.white, size: size * .7),
  );
}

class Avatar extends StatelessWidget {
  final Json person;
  final double size;
  const Avatar({super.key, required this.person, this.size = 42});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: [
        const Color(0xFFE9F0E8),
        const Color(0xFFE9EEE2),
        const Color(0xFFF1EAE0),
        const Color(0xFFE3EDEF),
        const Color(0xFFEAE5F0),
        const Color(0xFFF1E4E4),
      ][(person['avatar'] as int? ?? 0) % 6],
      borderRadius: BorderRadius.circular(size * .35),
    ),
    child: Icon(
      avatars[(person['avatar'] as int? ?? 0) % 6],
      color: green,
      size: size * .53,
    ),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(18),
    ),
    child: child,
  );
}

class PageScroll extends StatelessWidget {
  final List<Widget> children;
  const PageScroll({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: SingleChildScrollView(
      padding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width >= 960 ? 32 : 20,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: .3,
              ),
            ),
            if (subtitle != null) const SizedBox(height: 5),
            if (subtitle != null)
              Text(subtitle!, style: const TextStyle(color: muted, fontSize: 12)),
          ],
        ),
      ),
      if (trailing != null) trailing!,
    ],
  );
}

class EmptyView extends StatelessWidget {
  final String title, description;
  final IconData icon;
  final Widget? action;
  const EmptyView({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.receipt_long_outlined,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: const BoxDecoration(
              color: canvas,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 29, color: green),
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          if (action != null) const SizedBox(height: 16),
          if (action != null) action!,
        ],
      ),
    ),
  );
}

class HomePage extends StatelessWidget {
  final MoneyStore store;
  final Future<void> Function({bool split}) create;
  final Future<void> Function() auth;
  final void Function(int) select;
  const HomePage({
    super.key,
    required this.store,
    required this.create,
    required this.auth,
    required this.select,
  });

  @override
  Widget build(BuildContext context) {
    final requests = store.transactions.where(store.needsAction).toList();
    final upcoming = store.transactions
        .where((t) => ['active', 'repayment_pending'].contains(t['status']))
        .toList()
      ..sort((a, b) => (a['due'] as String).compareTo(b['due'] as String));
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: PageScroll(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.loggedIn
                          ? '${store.me['name']}さんのシェア帳'
                          : 'お金のやりとりを、もっとクリアに。',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '貸したお金も、借りたお金も。大切な約束をひとつに。',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width > 650)
                Text(
                  '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 26),
          LayoutBuilder(
            builder: (context, constraints) {
              final lending = BalanceCard(store: store, lending: true);
              final borrowing = BalanceCard(store: store, lending: false);
              return constraints.maxWidth >= 560
                  ? Row(
                      children: [
                        Expanded(child: lending),
                        const SizedBox(width: 18),
                        Expanded(child: borrowing),
                      ],
                    )
                  : Column(
                      children: [
                        lending,
                        const SizedBox(height: 14),
                        borrowing,
                      ],
                    );
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ActionTile(
                  icon: Icons.add_rounded,
                  title: '貸し借りを記録',
                  subtitle: '相手へリクエスト',
                  onTap: () => create(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ActionTile(
                  icon: Icons.pie_chart_outline_rounded,
                  title: 'みんなで割り勘',
                  subtitle: '人数で自動計算',
                  onTap: () => create(split: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          if (!store.loggedIn)
            Panel(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.cloud_sync_outlined, color: green, size: 27),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'つながると、記録が共有されます',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'アカウントを作成して、メンバーを招待しましょう。',
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: auth,
                    child: const Text('はじめる', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          if (!store.loggedIn) const SizedBox(height: 26),
          SectionTitle(
            '確認待ちのリクエスト',
            subtitle: 'お互いの承認で、やりとりが成立します',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF3ED),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${requests.length}件',
                style: const TextStyle(
                  color: green,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Panel(
            padding: const EdgeInsets.all(6),
            child: requests.isEmpty
                ? const EmptyView(
                    title: '確認待ちのリクエストはありません',
                    description: '新しい依頼や返済報告が届くと、ここに表示されます。',
                    icon: Icons.task_alt_rounded,
                  )
                : Column(
                    children: requests
                        .take(3)
                        .map((t) => TxTile(store: store, tx: t))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 28),
          SectionTitle(
            'これからの返済予定',
            subtitle: '期限が近い順に表示',
            trailing: TextButton(
              onPressed: () => select(2),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('カレンダー', style: TextStyle(fontSize: 12)),
                  Icon(Icons.chevron_right, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            padding: const EdgeInsets.all(6),
            child: upcoming.isEmpty
                ? const EmptyView(
                    title: '今は返済予定がありません',
                    description: '承認された取引の返済日を、ここで確認できます。',
                    icon: Icons.event_available_outlined,
                  )
                : Column(
                    children: upcoming
                        .take(4)
                        .map((t) => TxTile(store: store, tx: t))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 24),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 13, color: muted),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  '取引データはサーバーで共有・保存されます',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class BalanceCard extends StatelessWidget {
  final MoneyStore store;
  final bool lending;
  const BalanceCard({super.key, required this.store, required this.lending});

  @override
  Widget build(BuildContext context) {
    final color = lending ? Colors.white : ink;
    final count = store.transactions
        .where(
          (t) =>
              ['active', 'repayment_pending'].contains(t['status']) &&
              t[lending ? 'lender' : 'borrower'] == store.id,
        )
        .length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: lending
            ? const LinearGradient(
                colors: [Color(0xFF205F4C), Color(0xFF123E34)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: lending ? null : Colors.white,
        border: lending ? null : Border.all(color: line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: lending
                      ? Colors.white.withValues(alpha: .12)
                      : const Color(0xFFF6EFE4),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  lending ? Icons.south_west_rounded : Icons.north_east_rounded,
                  size: 18,
                  color: lending ? const Color(0xFFADDEC6) : amber,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                lending ? '貸しているお金' : '借りているお金',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 22,
                color: lending ? Colors.white.withValues(alpha: .4) : muted,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            store.loggedIn ? yen(store.balance(lending)) : '¥ —',
            style: TextStyle(
              color: color,
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 19),
          Row(
            children: [
              Text(
                lending ? '受け取り予定' : '返済予定',
                style: TextStyle(
                  color: lending ? const Color(0xFFB7D5C8) : muted,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                '$count件のやりとり',
                style: TextStyle(
                  color: lending ? const Color(0xFFB7D5C8) : muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ActionTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 19),
        decoration: BoxDecoration(
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, size: 27, color: green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            if (MediaQuery.sizeOf(context).width > 500)
              const Icon(Icons.chevron_right, size: 18, color: muted),
          ],
        ),
      ),
    ),
  );
}
