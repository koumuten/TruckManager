# テストのデバッグとリファクタリングの記録

`app_test.dart` のユニットテストを成功させるために実施したデバッグ作業とコードのリファクタリングの過程をまとめます。

## 課題1: 密結合によるテストの失敗

- **エラー内容:** 最初のテスト実行時、具体的な処理（Gmail API呼び出しなど）をモックできず、テストが失敗しました。
- **原因:** `AppService`クラスが、`GmailServiceImpl`などの具象クラスを直接インスタンス化しており、テスト時に振る舞いを差し替える（モックする）ことが困難でした（密結合）。
- **解決策:**
  1. `GmailService`のような抽象インターフェースを定義しました。
  2. `AppService`のコンストラクタを修正し、具象クラスのインスタンスではなく、抽象インターフェースを受け取るように変更しました（依存性の注入 / DI）。
  3. これにより、テスト時にはインターフェースを満たすモックオブジェクトを注入できるようになりました。

## 課題2: モック生成の対象クラスの誤り

- **エラー内容:** `Error: 'MockGmailServiceImpl' isn't a type.`
- **原因:** DIの導入後、テストコードが古い具象クラス（`GmailServiceImpl`）のモックを生成しようとしていました。`@GenerateMocks`のアノテーションでは新しいインターフェース（`GmailService`）を指定していたため、型が一致せずエラーが発生しました。
- **解決策:**
  1. `test/app_test.dart`内の`@GenerateMocks`アノテーションの対象を、具象クラスから`GmailService`インターフェースに変更しました。
  2. テストコード内で使用するモックの型も`MockGmailServiceImpl`から`MockGmailService`に修正しました。
  3. `build_runner`を再実行し、正しいモックファイルを生成しました。

## 課題3: コンストラクタのパラメータ名の不一致

- **エラー内容:** `Error: No named parameter with the name 'totalAmount'.`
- **原因:** テストコードで`InvoiceCapsule`をインスタンス化する際に、誤ったパラメータ名 `totalAmount` を使用していました。`InvoiceCapsule`のコンストラクタで定義されている正しいパラメータ名は `price` でした。
- **解決策:** `test/app_test.dart`内の`InvoiceCapsule`のインスタンス化部分を、正しいパラメータ名 `price` を使用するように修正しました。

## 課題4: 無効な作業ディレクトリパス

- **エラー内容:** `PathNotFoundException: Setting current working directory failed, path = 'truck_manager'`
- **原因:** テストの`setUp`関数内で`Directory.current = 'truck_manager';`を実行していました。しかし、テストの実行コマンドはすでに`truck_manager`ディレクトリに移動してから`dart test`を呼び出しているため、存在しないサブディレクトリへ移動しようとしてエラーになっていました。
- **解決策:** `test/app_test.dart`から不要な`Directory.current = 'truck_manager';`の行を削除しました。

## 課題5: 環境変数の不足

- **エラー内容:** `Exception: Environment variable NOT FOUND: TMP_DIR`
- **原因:** `AppService`が一時ファイルの保存場所として環境変数 `TMP_DIR` を参照していますが、テスト実行環境ではこの変数が設定されていませんでした。
- **解決策（試行）:** `setUp`関数内で`Platform.environment['TMP_DIR'] = ...`のように環境変数をプログラム的に設定しようと試みました。

## 課題6（現在の課題）: 変更不可能な環境変数マップ

- **エラー内容:** `Unsupported operation: Cannot modify unmodifiable map`
- **原因:** Dartの`Platform.environment`は変更不可能な（unmodifiable）Mapです。そのため、`setUp`関数内で直接キーを追加しようとしても、このエラーが発生して失敗します。
- **今後の対策案:**
    - **案A:** `AppService`が`TMP_DIR`のパスを環境変数から直接読み込むのではなく、コンストラクタ経由で受け取るようにリファクタリングする。これにより、テスト時には任意のテスト用パスを注入できます。
    - **案B:** `AssetLoader.readAsset`のような静的メソッドの呼び出しをモックする高度なテスト手法（`mockito` の `spy` や `any` などと組み合わせた工夫）を検討する。



app_test.dart で使われているモックがどのように動作するかを説明します。

@GenerateMocks([...]): このアノテーションは、build_runner というツールに、指定されたクラス（FirebaseServiceやLineNotifyServiceなど）の「影武者」となるモッククラスを app_test.mocks.dart ファイルに自動生成するように指示します。
when(...).thenAnswer(...): これはテストの「台本」のようなものです。when の中でモックオブジェクトの特定のメソッドが呼び出されたときに、thenAnswer で指定した動作をさせるように設定します。
具体的な例:

// app_test.dart のサンプルコード
final pdfText = '発行日: 2023/01/15\nお支払い総合計: 10,000円';

// 「mockPdfService の extractTextFromPdf メソッドがどんな引数で呼ばれても、
//   pdfText という文字列を返す」という台本を設定
when(mockPdfService.extractTextFromPdf(any)).thenAnswer((_) async => pdfText);


このように設定することで、PdfService の実際の処理（PDFファイルを読み込んで解析する処理）を実行することなく、テストコードに都合の良い値を返すことができます。これにより、テストを高速かつ安定して実行できます。

テストが終了しない（ハングする）最も一般的な原因は、完了しない非同期処理を待っていることです。

特に、HTTPリクエストやファイル読み込みなどのI/O（入出力）処理は、外部環境に依存するため、テストが不安定になる原因となります。

あなたのコードでは、以下の2つが原因である可能性が高いです。

LineNotifyService のHTTPリクエスト: truck_manager/lib/services/line.dart を見ると、LineNotifyService は実際に https://notify-api.line.me/api/notify へHTTPリクエストを送信しています。テスト中にこのメソッドが呼ばれると、実際のネットワーク通信が発生してしまい、レスポンスが返ってくるまでテストが停止します。テスト環境のネットワーク設定によっては、レスポンスが永遠に返ってこず、テストがハングします。

AssetLoader の環境変数/ファイルアクセス: truck_manager/lib/services/asset_loader.dart は、環境変数やファイルを読み込む処理を持っています。特に Platform.environment[...] を使って環境変数を読み込む部分は、テスト実行時にその環境変数が設定されていない場合、例外（Exception）を投げるか、予期せぬ動作をする可能性があります。

テスト対象のコード（App.processNewMessage）が呼び出す全てのサービスのメソッドを、モックを使って正しく「偽の動作」に置き換える必要があります。

app_test.dart のテストコードで、LineNotifyService の sendNotification メソッドが呼ばれている箇所があるはずです。その呼び出しに対して、以下のように when を使ってダミーの動作を定義してください。

app_test.dart に追加するコードの例:

// test('...', () async { ... の中

// ... 他のモック設定 ...

// LineNotifyService の sendNotification が呼ばれたら、
// 何もせずに正常終了したことにする
when(mockLineNotifyService.sendNotification(any, any))
    .thenAnswer((_) async => Future.value()); // Future<void> を返すメソッドなので Future.value() を使う

// ... テスト対象のメソッド呼び出し ...
// await app.processNewMessage(mockMessage);

// ... アサーション ...

// });


同様に、FirebaseService や GmailService など、@GenerateMocks に指定した他のサービスのメソッド呼び出しがテスト中に発生している場合は、それらすべてに対して when(...).thenAnswer(...) を設定する必要があります。

まとめ: テストが終了しないのは、モック化されていない LineNotifyService が実際のHTTP通信を行ってしまい、その完了を待ち続けている可能性が非常に高いです。テストコードを見直し、外部と通信する可能性のあるすべてのメソッド呼び出しをモックに置き換えてみてください。