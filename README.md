# MoguLog

個人用の飲食店記録アプリ（iOS 26以降）。データは端末内にのみ保存する。

## 構成

| パス | 内容 |
|---|---|
| `Sources/` | アプリのソースコード（SwiftUI・SwiftData） |
| `project.yml` | XcodeGen の設定。Xcode プロジェクトはビルド時に自動生成する |
| `.github/workflows/build-ipa.yml` | GitHub Actions で署名なしの IPA を作成する設定 |

## IPA の作り方

1. GitHub の「Actions」タブ →「Build IPA」→「Run workflow」
2. 完了後、実行結果のページの「Artifacts」から `MoguLog-ipa` をダウンロード
3. ZIP を展開した `MoguLog.ipa` を、AltStore で自分の iPhone にインストールする（署名は AltStore が行う）

## 注意

- このリポジトリには個人の記録データは含まれない（記録は端末内のみ）。
- 署名なしの IPA は、そのままではインストールできない。AltStore などで署名して使う。
