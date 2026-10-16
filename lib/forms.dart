part of 'main.dart';

class SheetLayout extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SheetLayout({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: '閉じる',
                      icon: const Icon(Icons.close, size: 21),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class InfoNote extends StatelessWidget {
  final String text;
  const InfoNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEEF5EF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 18, color: green),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: green, fontSize: 11, height: 1.7),
          ),
        ),
      ],
    ),
  );
}

class ErrorNote extends StatelessWidget {
  final String text;
  const ErrorNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEFEA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFAE433A), fontSize: 12),
      ),
    ),
  );
}

Widget label(String text) => Padding(
  padding: const EdgeInsets.only(top: 18, bottom: 8),
  child: Text(
    text,
    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
  ),
);

Future<DateTime?> pickDate(BuildContext context, {DateTime? initial}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final selected = initial != null && !initial.isBefore(today) ? initial : today;
  return showDatePicker(
    context: context,
    initialDate: selected,
    firstDate: today,
    lastDate: DateTime(now.year + 10, 12, 31),
  );
}

class AuthSheet extends StatefulWidget {
  final MoneyStore store;
  const AuthSheet({super.key, required this.store});

  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool register = true;
  bool busy = false;
  bool hidden = true;
  String? error;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.auth(
        register,
        name.text,
        email.text.trim(),
        password.text,
      );
      if (mounted) {
        toast(
          context,
          register
              ? 'アカウントを作成しました。共有IDで相手を追加できます。'
              : 'ログインしました。',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = message(e);
        });
      }
    }
  }

  Future<void> reset() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.resetPassword(email.text);
      if (mounted) {
        toast(context, '再設定メールを送信しました。');
      }
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetLayout(
    title: register ? 'お金シェア帳をはじめる' : 'おかえりなさい',
    children: [
      const Row(
        children: [
          BrandMark(size: 42),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              '大切なお金の約束を、\nお互いに見える記録に。',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ),
        ],
      ),
      const SizedBox(height: 22),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('新規登録')),
          ButtonSegment(value: false, label: Text('ログイン')),
        ],
        selected: {register},
        onSelectionChanged: busy
            ? null
            : (s) => setState(() {
                  register = s.first;
                  error = null;
                }),
      ),
      if (register) label('アカウント名'),
      if (register)
        TextField(
          controller: name,
          maxLength: 40,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: '例：山田 はるか',
            counterText: '',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
      label('メールアドレス'),
      TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          hintText: 'you@example.com',
          prefixIcon: Icon(Icons.mail_outline),
        ),
      ),
      label('パスワード'),
      TextField(
        controller: password,
        obscureText: hidden,
        autofillHints: [
          register ? AutofillHints.newPassword : AutofillHints.password,
        ],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          if (!busy) submit();
        },
        decoration: InputDecoration(
          hintText: '8文字以上',
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            onPressed: () => setState(() => hidden = !hidden),
            icon: Icon(
              hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            ),
          ),
        ),
      ),
      if (!register)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy ? null : reset,
            child: const Text(
              'パスワードを忘れた方',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
      const SizedBox(height: 20),
      if (register)
        const InfoNote(
          'アカウント名・アイコン・共有ID・支払い日・標準期限は、ログイン済みの利用者が確認できる公開プロフィールです。取引は当事者のみ確認できます。',
        ),
      const SizedBox(height: 20),
      if (error != null) ErrorNote(error!),
      FilledButton(
        onPressed: busy ? null : submit,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(register ? 'アカウントを作成' : 'ログイン'),
      ),
      const SizedBox(height: 14),
      const Text(
        '実際の送金は行いません。支払い方法は相手と直接やり取りしてください。',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted, fontSize: 10),
      ),
    ],
  );
}

Future<void> showContact(BuildContext context, MoneyStore store) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => ContactForm(store: store),
    );

class ContactForm extends StatefulWidget {
  final MoneyStore store;
  const ContactForm({super.key, required this.store});

  @override
  State<ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<ContactForm> {
  final code = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.mutate('contact', {'code': code.text.trim()});
      if (mounted) {
        toast(context, 'メンバーを追加しました。');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SheetLayout(
    title: 'メンバーを追加',
    children: [
      const InfoNote(
        '相手にもアカウントを作成してもらい、マイページの共有IDを教えてもらってください。追加すると相手の支払い日の目安を確認できます。',
      ),
      label('相手の共有ID'),
      TextField(
        controller: code,
        decoration: const InputDecoration(
          hintText: 'OS-3F9A01C7BE',
          prefixIcon: Icon(Icons.person_search_outlined),
        ),
        onSubmitted: (_) {
          if (!busy) submit();
        },
      ),
      const SizedBox(height: 22),
      if (error != null) ErrorNote(error!),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(busy ? '追加中…' : 'メンバーを追加'),
      ),
      const SizedBox(height: 24),
      const Text(
        'あなたの共有ID',
        style: TextStyle(color: muted, fontSize: 11),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: SelectableText(
              widget.store.shareId,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.store.shareId));
              toast(context, 'コピーしました。');
            },
            icon: const Icon(Icons.copy_outlined, size: 19),
          ),
        ],
      ),
    ],
  );
}

class TransactionForm extends StatefulWidget {
  final MoneyStore store;
  final bool split;
  const TransactionForm({
    super.key,
    required this.store,
    this.split = false,
  });

  @override
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  final amount = TextEditingController();
  final memo = TextEditingController();
  bool borrowing = true;
  bool busy = false;
  String? peer;
  String? error;
  String method = '';
  String mode = 'equal';
  DateTime? due;
  final Set<String> members = {};

  @override
  void initState() {
    super.initState();
    if (widget.store.contacts.isNotEmpty) {
      peer = widget.store.contacts.first['id'] as String;
    }
    amount.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    amount.removeListener(changed);
    amount.dispose();
    memo.dispose();
    super.dispose();
  }

  Json get borrower =>
      widget.store.person(borrowing ? widget.store.id : peer ?? '');

  DateTime get effectiveDue {
    final schedule = borrower['schedule'] as Map? ?? defaultSchedule;
    final kind = borrower['defaultKind'] as String? ?? 'salary';
    return due ?? nextDue(schedule[kind] as int? ?? 25, DateTime.now());
  }

  Future<void> submit() async {
    final ticks = parseTicks(amount.text);
    if (ticks <= 0 || ticks > 1000000000) {
      setState(() {
        error = '金額は0より大きく、1億円以下にしてください。';
      });
      return;
    }
    if (widget.split && (members.isEmpty || members.length > 15)) {
      setState(() => error = '請求する相手を1〜15人選択してください。');
      return;
    }
    if (!widget.split && peer == null) {
      setState(() => error = '相手を選択してください。');
      return;
    }
    if (widget.split) {
      final count = members.length + (mode == 'equal' ? 1 : 0);
      if (splitDecimalTicks(amount.text, count) <= 0) {
        setState(() => error = '1人あたり0.1円以上にしてください。');
        return;
      }
    }

    final description = widget.split
        ? '${members.length}人に割り勘リクエストを送ります。承認された分だけ取引が成立します。'
        : '${widget.store.name(peer!)}さんへリクエストを送ります。相手の承認後に取引が成立します。';
    if (!await confirm(context, '内容を確認して送信', description)) return;
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });

    final data = <String, dynamic>{
      'amount': amount.text,
      'memo': memo.text,
      'due': due == null ? '' : iso(due!),
      'method': method,
    };
    if (widget.split) {
      data['members'] = members.toList();
      data['mode'] = mode;
    } else {
      data['lender'] = borrowing ? peer : widget.store.id;
      data['borrower'] = borrowing ? widget.store.id : peer;
    }

    try {
      await widget.store.mutate(
        widget.split ? 'split' : 'transaction',
        data,
      );
      if (mounted) {
        toast(context, 'リクエストを送信しました。');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final count = members.length + (mode == 'equal' ? 1 : 0);
    final perPerson = splitDecimalTicks(amount.text, count);
    final children = <Widget>[
      Row(
        children: [
          const Icon(Icons.today_outlined, color: muted, size: 17),
          const SizedBox(width: 8),
          Text(
            '記録日：${fullDate(iso(DateTime.now()))}（自動）',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    ];

    if (!widget.split) {
      children.addAll([
        label('あなたの立場'),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('借りる'),
              icon: Icon(Icons.south_west, size: 16),
            ),
            ButtonSegment(
              value: false,
              label: Text('貸す'),
              icon: Icon(Icons.north_east, size: 16),
            ),
          ],
          selected: {borrowing},
          onSelectionChanged: (s) => setState(() {
            borrowing = s.first;
            due = null;
          }),
        ),
        label(borrowing ? '貸してくれた人' : '借りた人'),
        DropdownButtonFormField<String>(
          initialValue: peer,
          isExpanded: true,
          items: store.contacts.map((p) {
            return DropdownMenuItem(
              value: p['id'] as String,
              child: Text(p['name'] as String),
            );
          }).toList(),
          onChanged: (s) => setState(() {
            peer = s;
            due = null;
          }),
        ),
      ]);
    } else {
      children.add(label('請求する相手（1〜15人）'));
      for (final p in store.contacts) {
        children.add(
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            secondary: Avatar(person: p, size: 30),
            title: Text(
              p['name'] as String,
              style: const TextStyle(fontSize: 13),
            ),
            value: members.contains(p['id']),
            onChanged: (value) {
              if (value == true &&
                  !members.contains(p['id']) &&
                  members.length >= 15) {
                setState(() => error = '請求する相手は15人までです。');
                return;
              }
              setState(() {
                error = null;
                if (value == true) {
                  members.add(p['id'] as String);
                } else {
                  members.remove(p['id']);
                }
              });
            },
          ),
        );
      }
      children.addAll([
        label('割り勘モード'),
        DropdownButtonFormField<String>(
          initialValue: mode,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: 'equal',
              child: Text('立替者を含めて均等に割る'),
            ),
            DropdownMenuItem(
              value: 'others',
              child: Text('立替者以外で均等に割る'),
            ),
          ],
          onChanged: (v) => setState(() => mode = v!),
        ),
      ]);
    }

    children.addAll([
      label(widget.split ? '立て替えた合計金額' : '金額'),
      TextField(
        controller: amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: const InputDecoration(
          hintText: '0',
          prefixText: '¥  ',
          suffixText: '円',
        ),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
    ]);

    if (widget.split && members.isNotEmpty) {
      children.addAll([
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEDF5EF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1人あたり  ${yen(perPerson, decimal: true)}',
                style: const TextStyle(
                  color: green,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$count人で計算・${members.length}人へ個別に請求',
                style: const TextStyle(color: green, fontSize: 11),
              ),
              const SizedBox(height: 5),
              Text(
                '小数第2位を四捨五入。丸めによる合計差額：${(perPerson * count - parseTicks(amount.text)) / 10}円\n記録は0.1円単位です。送金時は当事者間で端数を調整してください。',
                style: const TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ]);
    }

    children.addAll([
      label('目的・メモ（任意）'),
      TextField(
        controller: memo,
        maxLength: 500,
        minLines: 2,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: '例：ランチ代、旅行の宿泊費',
          counterText: '',
        ),
      ),
      label('返済期限'),
      OutlinedButton.icon(
        onPressed: () async {
          final selected = await pickDate(
            context,
            initial: due ?? (widget.split ? null : effectiveDue),
          );
          if (selected != null && mounted) {
            setState(() => due = selected);
          }
        },
        icon: const Icon(Icons.calendar_today_outlined, size: 17),
        label: Text(
          due != null
              ? fullDate(iso(due!))
              : widget.split
                  ? '各メンバーの登録済み期限を使う'
                  : '${fullDate(iso(effectiveDue))}（自動）',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ]);

    if (due != null) {
      children.add(
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => due = null),
            child: const Text(
              '登録済みの期限に戻す',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),
      );
    } else {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            widget.split
                ? '借りる人それぞれの標準期限が自動設定されます。'
                : '${store.name(borrower['id'] as String? ?? '')}さんの${scheduleLabels[borrower['defaultKind'] ?? 'salary']}の翌日',
            style: const TextStyle(color: muted, fontSize: 10),
          ),
        ),
      );
    }

    children.addAll([
      label('希望する支払い方法（任意）'),
      DropdownButtonFormField<String>(
        initialValue: method,
        items: ['', '現金', 'PayPay', '振り込み', 'その他'].map((m) {
          return DropdownMenuItem(
            value: m,
            child: Text(m == '' ? '指定しない' : m),
          );
        }).toList(),
        onChanged: (v) => setState(() => method = v!),
      ),
      const SizedBox(height: 24),
      if (error != null) ErrorNote(error!),
      FilledButton.icon(
        onPressed: busy || (!widget.split && peer == null) ? null : submit,
        icon: const Icon(Icons.send_outlined, size: 18),
        label: Text(busy ? '送信中…' : '内容を確認してリクエスト'),
      ),
      const SizedBox(height: 14),
      const Text(
        'この操作で送金は行いません。相手の承認後に共有記録が成立します。',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted, fontSize: 10),
      ),
    ]);

    return SheetLayout(
      title: widget.split ? 'みんなで割り勘' : '貸し借りを記録',
      children: children,
    );
  }
}

class ProfileForm extends StatefulWidget {
  final MoneyStore store;
  const ProfileForm({super.key, required this.store});

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  late final TextEditingController name;
  late Map<String, int> schedule;
  late String kind;
  late int avatar;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final me = widget.store.me;
    name = TextEditingController(text: me['name'] as String);
    schedule = (me['schedule'] as Map).map(
      (k, v) => MapEntry(k as String, v as int),
    );
    kind = me['defaultKind'] as String;
    avatar = me['avatar'] as int;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.mutate('profile', {
        'name': name.text,
        'avatar': avatar,
        'schedule': schedule,
        'defaultKind': kind,
      });
      if (mounted) {
        toast(context, 'プロフィールを更新して共有しました。');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SheetLayout(
    title: 'マイページを編集',
    children: [
      label('アカウント名'),
      TextField(
        controller: name,
        maxLength: 40,
        decoration: const InputDecoration(counterText: ''),
      ),
      label('アイコン'),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var i = 0; i < avatars.length; i++)
            InkWell(
              onTap: () => setState(() => avatar = i),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: avatar == i ? green : Colors.transparent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Avatar(person: {'avatar': i}, size: 44),
              ),
            ),
        ],
      ),
      label('毎月の支払い日'),
      for (final e in scheduleLabels.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(e.value, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<int>(
                  initialValue: schedule[e.key],
                  isExpanded: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: [
                    for (var day = 1; day <= 31; day++)
                      DropdownMenuItem(
                        value: day,
                        child: Text(
                          '$day日',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => schedule[e.key] = v!),
                ),
              ),
            ],
          ),
        ),
      label('未指定時の標準返済期限'),
      DropdownButtonFormField<String>(
        initialValue: kind,
        isExpanded: true,
        items: scheduleLabels.entries.map((e) {
          return DropdownMenuItem(
            value: e.key,
            child: Text(
              '${e.value}の翌日',
              style: const TextStyle(fontSize: 12),
            ),
          );
        }).toList(),
        onChanged: (v) => setState(() => kind = v!),
      ),
      const SizedBox(height: 12),
      InfoNote(
        '次の標準期限：${fullDate(iso(nextDue(schedule[kind]!, DateTime.now())))}\n月に存在しない日付は月末として計算します。変更は新しいリクエストに適用され、成立済みの取引期限は変更されません。',
      ),
      const SizedBox(height: 24),
      if (error != null) ErrorNote(error!),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(busy ? '保存中…' : '設定を保存して共有'),
      ),
    ],
  );
}
