part of 'main.dart';

class TxTile extends StatelessWidget {
  final MoneyStore store;
  final Json tx;
  const TxTile({super.key, required this.store, required this.tx});

  @override
  Widget build(BuildContext context) {
    final lending = tx['lender'] == store.id;
    final peer = store.person(tx[lending ? 'borrower' : 'lender'] as String);
    final overdue = tx['status'] == 'active' &&
        (tx['due'] as String).compareTo(iso(DateTime.now())) < 0;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Avatar(person: peer),
      title: Row(
        children: [
          Expanded(
            child: Text(
              peer['name'] as String? ?? 'メンバー',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          Text(
            yen(
              tx['amount'] as num,
              decimal: (tx['split_id'] as String).isNotEmpty,
            ),
            style: TextStyle(
              color: lending ? green : ink,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${tx['memo'] == '' ? '目的のメモなし' : tx['memo']}\n${shortDate(tx['due'] as String)}までに${lending ? '受け取り' : '返済'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ),
            const SizedBox(width: 6),
            StatusChip(
              overdue ? '期限超過' : statusLabels[tx['status']] ?? '',
              warning: overdue || store.needsAction(tx),
            ),
          ],
        ),
      ),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        builder: (_) => TxDetails(store: store, txId: tx['id'] as String),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final bool warning;
  const StatusChip(this.label, {super.key, this.warning = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFBF1E3) : const Color(0xFFF0F5F1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: warning ? amber : green,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class TransactionsPage extends StatefulWidget {
  final MoneyStore store;
  final Future<void> Function({bool split}) create;
  final Future<void> Function() auth;
  const TransactionsPage({
    super.key,
    required this.store,
    required this.create,
    required this.auth,
  });

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  int filter = 0;
  String search = '';

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final txs = store.transactions.where((t) {
      final active = ['active', 'repayment_pending'].contains(t['status']);
      final match = switch (filter) {
        1 => active && t['lender'] == store.id,
        2 => active && t['borrower'] == store.id,
        3 => t['status'] == 'pending' || store.needsAction(t),
        4 => ['repaid', 'cancelled', 'rejected'].contains(t['status']),
        _ => true,
      };
      return match &&
          '${t['memo']} ${store.name(t['lender'] as String)} ${store.name(t['borrower'] as String)}'
              .toLowerCase()
              .contains(search.toLowerCase());
    }).toList();

    final records = <Widget>[];
    for (var i = 0; i < txs.length; i++) {
      records.add(TxTile(store: store, tx: txs[i]));
      if (i < txs.length - 1) {
        records.add(
          const Divider(height: 1, indent: 18, endIndent: 18),
        );
      }
    }

    return PageScroll(
      children: [
        SectionTitle(
          'やりとりの記録',
          subtitle: '貸し借り・割り勘をまとめて確認',
          trailing: FilledButton.icon(
            onPressed: () => widget.create(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('記録', style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          onChanged: (s) => setState(() => search = s),
          decoration: const InputDecoration(
            hintText: '相手の名前・目的で検索',
            prefixIcon: Icon(Icons.search, size: 22),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in [
              'すべて',
              '貸している',
              '借りている',
              '確認待ち',
              '履歴',
            ].asMap().entries)
              ChoiceChip(
                label: Text(e.value, style: const TextStyle(fontSize: 12)),
                selected: filter == e.key,
                onSelected: (_) => setState(() => filter = e.key),
                showCheckmark: false,
                selectedColor: const Color(0xFFE4F0E8),
                side: const BorderSide(color: line),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Panel(
          padding: const EdgeInsets.all(6),
          child: txs.isEmpty
              ? EmptyView(
                  title: '表示する取引がありません',
                  description: store.loggedIn
                      ? '新しい貸し借りを記録して、相手に依頼しましょう。'
                      : 'ログインすると、共有された取引を確認できます。',
                  action: store.loggedIn
                      ? null
                      : TextButton(
                          onPressed: widget.auth,
                          child: const Text('ログイン / 新規登録'),
                        ),
                )
              : Column(children: records),
        ),
      ],
    );
  }
}

class CalendarPage extends StatefulWidget {
  final MoneyStore store;
  const CalendarPage({super.key, required this.store});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final active = store.transactions
        .where((t) => ['active', 'repayment_pending'].contains(t['status']))
        .toList();
    final events = active.where((t) => t['due'] == iso(selected)).toList();
    final offset = month.weekday % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;

    return PageScroll(
      children: [
        const SectionTitle('返済カレンダー', subtitle: 'お金の流れを、日付で見える化'),
        const SizedBox(height: 24),
        Panel(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${month.year}年 ${month.month}月',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1),
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      selected = DateTime.now();
                      month = DateTime(selected.year, selected.month);
                    }),
                    child: const Text('今日'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final d in ['日', '月', '火', '水', '木', '金', '土'])
                    Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontSize: 12,
                            color: d == '日' ? amber : muted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: ((offset + days + 6) ~/ 7) * 7,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: constraints.maxWidth < 450 ? 55 : 72,
                  ),
                  itemBuilder: (context, index) {
                    final day = index - offset + 1;
                    if (day < 1 || day > days) return const SizedBox.shrink();
                    final date = DateTime(month.year, month.month, day);
                    final key = iso(date);
                    final chosen = iso(selected) == key;
                    final today = iso(DateTime.now()) == key;
                    final receiving = active.any(
                      (t) => t['due'] == key && t['lender'] == store.id,
                    );
                    final paying = active.any(
                      (t) => t['due'] == key && t['borrower'] == store.id,
                    );
                    return InkWell(
                      onTap: () => setState(() => selected = date),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: chosen
                              ? green
                              : today
                                  ? const Color(0xFFEDF4EE)
                                  : null,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$day',
                              style: TextStyle(
                                color: chosen ? Colors.white : ink,
                                fontSize: 14,
                                fontWeight: chosen || today
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (receiving)
                                  _dot(
                                    chosen ? const Color(0xFFB5E9CD) : green,
                                  ),
                                if (receiving && paying)
                                  const SizedBox(width: 4),
                                if (paying) _dot(const Color(0xFFD8A96B)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Legend(color: green, text: '受け取り'),
                  SizedBox(width: 24),
                  Legend(color: amber, text: '返済'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SectionTitle(
          '${selected.month}月${selected.day}日の予定',
          subtitle: '${events.length}件のやりとり',
        ),
        const SizedBox(height: 14),
        Panel(
          padding: const EdgeInsets.all(6),
          child: events.isEmpty
              ? const EmptyView(
                  title: 'この日の返済予定はありません',
                  description: '日付をタップすると、受け取り・返済を確認できます。',
                  icon: Icons.event_note_outlined,
                )
              : Column(
                  children:
                      events.map((t) => TxTile(store: store, tx: t)).toList(),
                ),
        ),
        const SizedBox(height: 24),
        if (store.loggedIn)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'あなたの毎月の支払い日',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                for (final e in scheduleLabels.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.value,
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                        Text(
                          '毎月${store.me['schedule'][e.key]}日',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dot(Color color) => Container(
    width: 5,
    height: 5,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class Legend extends StatelessWidget {
  final Color color;
  final String text;
  const Legend({super.key, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Text(text, style: const TextStyle(color: muted, fontSize: 11)),
    ],
  );
}

class MembersPage extends StatelessWidget {
  final MoneyStore store;
  final Future<void> Function() auth;
  const MembersPage({
    super.key,
    required this.store,
    required this.auth,
  });

  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      SectionTitle(
        'メンバー',
        subtitle: '支払いの都合を共有して、スムーズに',
        trailing: IconButton.filled(
          onPressed: () async {
            if (!store.loggedIn) {
              await auth();
              if (!store.loggedIn) return;
            }
            if (context.mounted) await showContact(context, store);
          },
          icon: const Icon(Icons.person_add_alt_1, size: 21),
        ),
      ),
      const SizedBox(height: 24),
      if (store.loggedIn)
        Panel(
          child: Row(
            children: [
              const Icon(Icons.badge_outlined, color: green),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'あなたの共有ID',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      store.shareId,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: store.shareId));
                  toast(context, '共有IDをコピーしました。');
                },
                tooltip: '共有IDをコピー',
                icon: const Icon(Icons.copy_outlined, size: 20),
              ),
            ],
          ),
        ),
      if (store.loggedIn) const SizedBox(height: 24),
      const SectionTitle('メンバー', subtitle: '共有IDで追加できます'),
      const SizedBox(height: 14),
      Panel(
        padding: const EdgeInsets.all(6),
        child: store.contacts.isEmpty
            ? const EmptyView(
                title: 'メンバーを追加しましょう',
                description: '相手もアカウントを作成し、共有IDを伝えてもらってください。',
                icon: Icons.people_outline,
              )
            : Column(
                children: [
                  for (final p in store.contacts)
                    ListTile(
                      contentPadding: const EdgeInsets.all(14),
                      leading: Avatar(person: p),
                      title: Text(
                        p['name'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '標準期限：${scheduleLabels[p['defaultKind']]}の翌日',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: muted,
                      ),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Row(
                            children: [
                              Avatar(person: p),
                              const SizedBox(width: 12),
                              Expanded(child: Text(p['name'] as String)),
                            ],
                          ),
                          content: SizedBox(
                            width: 380,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '登録済みの支払い日',
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                                const SizedBox(height: 16),
                                for (final e in scheduleLabels.entries)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            e.value,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '毎月${p['schedule'][e.key]}日',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                Text(
                                  '次の標準返済期限：${fullDate(iso(nextDue(p['schedule'][p['defaultKind']] as int, DateTime.now())))}',
                                  style: const TextStyle(
                                    color: green,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  '登録日は相手が設定した情報です。残高や取引履歴は他のメンバーには共有しません。',
                                  style: TextStyle(color: muted, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('閉じる'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
}

class ProfilePage extends StatelessWidget {
  final MoneyStore store;
  final Future<void> Function() auth;
  final void Function(int) select;
  const ProfilePage({
    super.key,
    required this.store,
    required this.auth,
    required this.select,
  });

  @override
  Widget build(BuildContext context) {
    if (!store.loggedIn) {
      return PageScroll(
        children: [
          const SectionTitle('マイページ', subtitle: '支払いの都合を、ひとつに'),
          const SizedBox(height: 24),
          Panel(
            child: EmptyView(
              title: 'アカウントを登録しましょう',
              description: 'あなたの支払い日・標準期限を設定できます。',
              icon: Icons.person_outline,
              action: FilledButton(
                onPressed: auth,
                child: const Text('ログイン / 新規登録'),
              ),
            ),
          ),
        ],
      );
    }
    final me = store.me;
    return PageScroll(
      children: [
        SectionTitle(
          'マイページ',
          subtitle: 'あなたの支払いの都合を共有',
          trailing: OutlinedButton.icon(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.white,
              builder: (_) => ProfileForm(store: store),
            ),
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('編集', style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(height: 24),
        Panel(
          child: Row(
            children: [
              Avatar(person: me, size: 62),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      me['name'] as String,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 21,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      store.shareId,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: store.shareId));
                  toast(context, '共有IDをコピーしました。');
                },
                icon: const Icon(Icons.copy_outlined, size: 21),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Panel(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '貸している合計',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      child: Text(
                        yen(store.balance(true)),
                        style: const TextStyle(
                          color: green,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Panel(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '借りている合計',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      child: Text(
                        yen(store.balance(false)),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => select(2),
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: const Text('返済・受取カレンダーを見る'),
        ),
        const SizedBox(height: 24),
        const SectionTitle(
          '支払い日と標準返済期限',
          subtitle: '相手が返済日を指定する際に使われます',
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            children: [
              for (final e in scheduleLabels.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        e.key == 'salary'
                            ? Icons.account_balance_wallet_outlined
                            : e.key == 'bank'
                                ? Icons.account_balance_outlined
                                : Icons.credit_card_outlined,
                        size: 20,
                        color: muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          e.value,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        '毎月${me['schedule'][e.key]}日',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF5EF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '未指定時の返済期限',
                      style: TextStyle(color: green, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${scheduleLabels[me['defaultKind']]}の翌日',
                      style: const TextStyle(
                        color: green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '次回：${fullDate(iso(nextDue(me['schedule'][me['defaultKind']] as int, DateTime.now())))}',
                      style: const TextStyle(color: green, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '月末に存在しない日付は、その月の最終日として計算します。銀行休業日の調整は行いません。',
                style: TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () async {
            final confirmed = await confirm(
              context,
              'ログアウトしますか？',
              '共有データはサーバーに残ります。',
            );
            if (confirmed) {
              try {
                await store.logout();
              } catch (e) {
                if (context.mounted) toast(context, message(e));
              }
            }
          },
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('ログアウト'),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );

Future<bool> confirm(
  BuildContext context,
  String title,
  String body,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 18)),
        content: Text(body, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('確認して実行'),
          ),
        ],
      ),
    ) ??
    false;

class TxDetails extends StatefulWidget {
  final MoneyStore store;
  final String txId;
  const TxDetails({super.key, required this.store, required this.txId});

  @override
  State<TxDetails> createState() => _TxDetailsState();
}

class _TxDetailsState extends State<TxDetails> {
  bool busy = false;
  String? error;

  Future<void> act(String action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.mutate('tx_action', {
        'id': widget.txId,
        'action': action,
      });
      if (mounted) toast(context, '共有された記録を更新しました。');
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final tx = store.transactions.firstWhere(
        (t) => t['id'] == widget.txId,
        orElse: () => {},
      );
      if (tx.isEmpty) {
        return const SizedBox(
          height: 200,
          child: Center(child: Text('取引が見つかりません。')),
        );
      }
      final lender = tx['lender'] as String;
      final borrower = tx['borrower'] as String;
      final state = tx['status'] as String;
      final approvals = tx['approvals'] as List? ?? [];
      final children = <Widget>[
        Center(
          child: StatusChip(
            statusLabels[state] ?? '',
            warning: store.needsAction(tx),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            yen(tx['amount'] as num, decimal: tx['split_id'] != ''),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Avatar(person: store.person(lender)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                store.name(lender),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.arrow_forward, color: muted),
            ),
            Avatar(person: store.person(borrower)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                store.name(borrower),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            '貸した人 → 借りた人',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ),
        const SizedBox(height: 24),
        detailRow('目的のメモ', tx['memo'] == '' ? '未入力' : tx['memo'] as String),
        detailRow('記録日', fullDate(tx['created'] as String)),
        detailRow('返済期限', fullDate(tx['due'] as String)),
        detailRow(
          '希望する支払い方法',
          tx['method'] == '' ? '指定なし' : tx['method'] as String,
        ),
        if (tx['split_id'] != '') detailRow('記録の種類', '割り勘（小数第1位まで）'),
        const SizedBox(height: 14),
        if (error != null) ErrorNote(error!),
        if (busy)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          ),
      ];

      if (state == 'pending') {
        children.addAll([
          InfoNote(
            approvals.contains(store.id)
                ? 'あなたの確認は完了しました。相手の承認を待っています。承認前の金額は残高に含まれません。'
                : '内容を確認して承認してください。貸した人と借りた人の両方が承認すると成立します。',
          ),
          const SizedBox(height: 16),
        ]);
        if (!approvals.contains(store.id)) {
          children.add(
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => act('reject'),
                    child: const Text('辞退する'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : () => act('approve'),
                    child: const Text('承認する'),
                  ),
                ),
              ],
            ),
          );
        } else if (tx['creator'] == store.id) {
          children.add(
            OutlinedButton(
              onPressed: busy ? null : () => act('cancel'),
              child: const Text('リクエストを取り消す'),
            ),
          );
        }
      }

      if (state == 'active' && store.id == borrower) {
        children.addAll([
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final confirmed = await confirm(
                      context,
                      '返済を報告しますか？',
                      '実際に支払いが完了していることを確認してください。相手が受取確認をすると返済完了になります。',
                    );
                    if (confirmed && mounted) await act('repay');
                  },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('返済したことを報告'),
          ),
          const SizedBox(height: 8),
          const Text(
            'このボタンで送金は行われません。',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 10),
          ),
        ]);
      }

      if (state == 'repayment_pending') {
        children.addAll([
          InfoNote(
            store.id == lender
                ? '相手から返済報告が届きました。実際に受け取ったことを確認してください。'
                : '返済報告済みです。相手の受取確認を待っています。',
          ),
          const SizedBox(height: 14),
        ]);
        if (store.id == lender) {
          children.add(
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => act('reject_repayment'),
                    child: const Text(
                      'まだ受け取っていない',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : () => act('confirm_repayment'),
                    child: const Text('受取確認'),
                  ),
                ),
              ],
            ),
          );
        }
      }

      if (state == 'repaid') {
        children.add(
          const InfoNote('双方の確認が完了した取引です。貸し借りの合計には含まれません。'),
        );
      }

      return SheetLayout(title: 'やりとりの詳細', children: children);
    },
  );
}

Widget detailRow(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 10),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 130,
        child: Text(
          label,
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    ],
  ),
);
