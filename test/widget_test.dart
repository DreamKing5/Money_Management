import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart';

void main() {
  test('給料日の翌日・年跨ぎ・存在しない日の月末処理', () {
    expect(iso(nextDue(25, DateTime(2026, 3, 2))), '2026-03-26');
    expect(iso(nextDue(25, DateTime(2026, 3, 26))), '2026-03-26');
    expect(iso(nextDue(25, DateTime(2026, 3, 27))), '2026-04-26');
    expect(iso(nextDue(31, DateTime(2026, 2, 15))), '2026-03-01');
    expect(iso(nextDue(31, DateTime(2026, 12, 15))), '2027-01-01');
  });

  test('金額と割り勘は0.1円単位で小数第2位を四捨五入', () {
    expect(parseTicks('1000'), 10000);
    expect(parseTicks('10.25'), 103);
    expect(parseTicks('10.24'), 102);
    expect(parseTicks('1..2'), 0);
    expect(splitTicks(10000, 3), 3333);
    expect(splitTicks(10001, 2), 5001);
    expect(splitDecimalTicks('10.25', 2), 51);
    expect(splitDecimalTicks('1000', 3), 3333);
    expect(parseTicks('99999999999999999999999999'), 0);
    expect(yen(3333, decimal: true), '¥333.3');
    expect(yen(10000, decimal: true), '¥1,000.0');
  });

  test('残高には承認済みと受取確認待ちだけを含む', () {
    final store = MoneyStore();
    store.me = {'id': 'A'};
    store.transactions = [
      {'lender': 'A', 'borrower': 'B', 'status': 'pending', 'amount': 10000},
      {'lender': 'A', 'borrower': 'B', 'status': 'active', 'amount': 20000},
      {
        'lender': 'B',
        'borrower': 'A',
        'status': 'repayment_pending',
        'amount': 30000,
      },
      {'lender': 'A', 'borrower': 'B', 'status': 'repaid', 'amount': 40000},
    ];
    expect(store.balance(true), 20000);
    expect(store.balance(false), 30000);
    store.dispose();
  });

  testWidgets('モバイル初期画面とナビゲーションにオーバーフローなし', (tester) async {
    final store = MoneyStore();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();

    expect(store.ready, isTrue);
    expect(store.loggedIn, isFalse);
    expect(find.text('貸しているお金'), findsOneWidget);
    expect(find.text('借りているお金'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('カレンダー').last);
    await tester.pumpAndSettle();
    expect(find.text('返済カレンダー'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('マイページ').last);
    await tester.pumpAndSettle();
    expect(find.text('アカウントを登録しましょう'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('デスクトップ表示にオーバーフローなし', (tester) async {
    final store = MoneyStore();
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();

    expect(store.ready, isTrue);
    expect(store.loggedIn, isFalse);
    expect(find.text('PERSONAL MONEY'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
