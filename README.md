# お金シェア帳

貸し借り・割り勘を、当事者双方の承認で記録するFlutterアプリです。

WebはGitHub Pagesで静的配信し、認証はFirebase Authenticationのメール／パスワード、共有データはCloud Firestoreを使用します。FirebaseはSparkプランのまま運用します。自作サーバー、Cloud Functions、Cloud Storage、Blazeプランは使用しません。

## セットアップ

1. Firebaseコンソールでプロジェクトを作成します。Sparkプランを維持し、Blazeへ変更しません。
2. Authenticationの「ログイン方法」で「メール／パスワード」を有効にします。
3. Firestore Databaseを本番モード、リージョン`asia-northeast1`で作成します。
4. `firestore.rules`をFirestoreの「ルール」に貼り付けて公開します。Firebase CLIを使用する場合は、対象プロジェクトを選択したうえで実行します。

   ```bash
   firebase deploy --only firestore:rules
   ```

5. FlutterFire CLIでWebとAndroidを設定し、`lib/firebase_options.dart`を実際の設定値で上書きします。

   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure --platforms=web,android
   ```

6. Authenticationの「設定 → 承認済みドメイン」に`ユーザー名.github.io`を追加します。ローカル確認用の`localhost`も登録します。
7. 古い`pubspec.lock`があれば削除してから依存関係を取得します。

   ```bash
   flutter pub get
   ```

8. ローカルでWeb版を確認します。

   ```bash
   flutter run -d chrome
   ```

9. GitHubに公開リポジトリを作成してソースをpushし、Settings → Pages → Sourceを「GitHub Actions」にします。`main`へのpushで指定のワークフローがテスト・ビルド・公開を実行します。生成された`lib/firebase_options.dart`もリポジトリに含めます。
10. Androidは任意です。Firebaseにパッケージ名`com.okaneshearcho.sharedmoney`のAndroidアプリを登録し、`flutterfire configure`を実行したうえでビルドします。

    ```bash
    flutter build apk
    ```

`YOUR_`から始まる設定値が残っている場合、アプリはFirebase未設定画面を表示します。日本語フォント`assets/fonts/NotoSansJP.ttf`と既存のWeb・Androidプロジェクト構成は必要です。

## 利用方法

- 各利用者がアカウントを登録し、共有IDを相手へ伝えます。
- 「メンバー」で相手の共有IDを入力します。メールアドレスでの相手検索はありません。
- 「貸し借りを記録」で自分の立場、相手、金額、メモ、期限、支払い方法を指定します。
- 相手が承認すると残高と返済予定に反映されます。
- 借りた人が返済を報告し、貸した人が受取確認すると完了します。
- 割り勘は立替者本人が作成します。請求先を1〜15人選び、自分を含めるか除くかを指定します。
- パスワード再設定はログイン画面でメールアドレスを入力し、「パスワードを忘れた方」を押します。

## 運用上の注意

- Firestoreの無料枠には、書き込み2万回／日、読み取り5万回／日などの制限があります。Sparkでは超過分に自動課金されませんが、該当操作が制限されます。日次枠は日次でリセットされ、「その月ずっと停止」するという意味ではありません。
- リアルタイムリスナーの初回取得・再接続・更新、プロフィール取得、ルール内の参照も読み取り消費に影響します。
- `firebase_options.dart`のAPIキーなどは公開前提の識別子で、秘密鍵ではありません。サービスアカウント鍵や署名用秘密鍵は公開しません。
- Authenticationの承認済みドメインを設定し、データへのアクセス権限は`firestore.rules`で制御します。承認済みドメインだけでFirestoreの権限が保護されるわけではありません。
- 公開プロフィールはログイン済みならUIDを指定して取得できます。プロフィールと共有IDの一覧取得は禁止です。
- 取引の読み取り・更新は当事者に限定します。成立済み取引の金額・期限・メモは変更できません。
- 端末に独自の取引データ保存処理はありません。認証状態とFirestore SDK標準のキャッシュはSDKが管理します。
- 実際の送金は行いません。支払い方法は当事者間で直接確認してください。

## 既知の制約

- サーバー側の権限・型・状態遷移の検証は、指定されたFirestoreルールで行います。ルールは期限の実在日や今日以降であることを検証せず、それらは端末側で確認します。
- メールアドレス確認による認証は行いません。メール／パスワード認証とパスワード再設定メールを使用します。
- 割り勘の請求先は15人までです。
- 記録は0.1円単位です。実際の支払いの端数は当事者間で調整します。
- 旧SQLiteのデータは引き継ぎません。
- 共有IDは`OS-`と大文字16進10桁です。旧形式の8桁IDは使用できません。
- 相手プロフィールは初回取得後にキャッシュします。再取得は共有状態表示のタップまたは更新操作で行います。
- プロフィール取得失敗時はエラー表示します。取引の相手を自分のメンバーへ自動追加する処理の失敗だけは表示を継続します。
- 旧グループ、期限変更提案、銀行口座登録・表示・銀行アプリへのリンクはありません。
- Androidの既存Gradle構成は`minSdk`以外を維持しており、提示された元ファイルではreleaseもdebug署名です。ストア公開用の署名設定は含みません。

## テスト

```bash
flutter test
```

計算・残高・未ログイン画面のwidget testではFirebaseを初期化しません。Firebase未初期化の`MoneyStore.init()`は未ログイン状態で終了します。

本復元環境にはFlutter／Dart SDKがないため、`flutter test`、Web／Androidビルド、Firebaseエミュレータによる実行検証は行っていません。

## 削除するファイル

- `server.py`
- `server_test.py`
- `android/app/build.gradle.kts.bak`

## 前提と判断

- 元ソースと修正回答を照合し、画面・機能は修正回答のまま、混入した`Copy`、コードブロックの崩れ、改行・インデント、失われた型引数、文字化けを復元しました。
- Firebase依存関係の基準バージョンは修正回答を維持し、プロンプトの指定に合わせてfirebase_core ^3.6.0、firebase_auth ^5.3.1、cloud_firestore ^5.4.3としました。
- GitHub Actionsの内容は指定どおり固定し、リポジトリ名配下への公開を前提としました。
- Androidの元ファイルにあるコメント・import・署名設定は「minSdk以外を変更しない」という指定を優先してそのまま出力しました。
- 公開プロフィールの説明は、指定ルールに合わせて「ログイン済み利用者が取得可能」としました。
- Firebaseの実設定値は利用者のプロジェクトから生成する必要があるため、指定どおりfirebase_options.dartだけにプレースホルダを使用しました。
- 取引更新はFirestoreトランザクション内で最新状態を取得し、許可されたstatusとapprovalsだけを更新します。
- メンバー追加は自分のcontactsだけを書き込み、受信取引の相手は各利用者の端末から自分のcontactsへ自動追加します。
- 相手プロフィールの読み取りは指定の1回取得とキャッシュを優先し、自分のプロフィール・contacts・取引をリアルタイム購読します。
- Sparkの日次無料枠超過は月末までの停止ではないため、修正回答の説明を維持しました。
- SDK標準の認証永続化とキャッシュは維持し、独自の端末保存・ポーリング・有料サービスは導入しません。
