# Pomodoro MVP (Flutter / iOS-first)

Flutterで作る、**iOS優先**の最小ポモドーロタイマーです。  
バックエンド/ログインなし、ローカル保存のみで動作します。

## 1. 最小のファイル構成

```txt
pomodoro/
├─ lib/
│  └─ main.dart
├─ pubspec.yaml
└─ README.md
```

> 実運用では `flutter create` で `ios/` などのプラットフォームファイルを生成してください。

## 2. 状態設計

### 管理する状態
- `sessionType`: `work` / `breakTime`
- `isRunning`: タイマー稼働中か
- `endAt`: 終了予定時刻 (`DateTime`)
- `pausedRemaining`: 一時停止時の残り秒数

### 時間計算の方針（重要）
- 1秒ずつカウントダウン値を減らすのではなく、`endAt - now` で残り時間を算出。
- `Timer.periodic` は**表示更新トリガー**としてのみ利用。

### 永続化（SharedPreferences）
- `sessionType`
- `isRunning`
- `endAt`（epoch ms）
- `pausedRemaining`

アプリ再起動時に復元し、`endAt`を超過していればセッション完了扱いにして次フェーズへ切り替えます。

## 3. 実装コード

- エントリ/ロジック/UIを `lib/main.dart` 1ファイルに集約（MVP優先）。
- ローカル通知は `flutter_local_notifications` を利用。

### 依存パッケージ
- `flutter_local_notifications`
- `shared_preferences`

## 4. GitHubに載せやすい使い方

### セットアップ
```bash
flutter pub get
flutter run -d ios
```

### iOS通知の注意点
`ios/Runner/Info.plist` に通知権限説明文を追加してください（必要に応じて）。

例:
```xml
<key>NSUserNotificationsUsageDescription</key>
<string>ポモドーロタイマー終了を通知するために使用します。</string>
```

### MVPでできること
- 25分作業 / 5分休憩
- Start / Pause / Reset
- 現在フェーズ表示（作業中 / 休憩中）
- 残り時間の大きな mm:ss 表示
- セッション終了のローカル通知
- 再起動後の状態復元（可能な範囲）

---

必要なら次のステップとして、
- 自動で次セッションを開始
- 1日あたりの完了セッション数記録
- iOS向けの見た目最適化（Cupertino化）
を追加できます。
