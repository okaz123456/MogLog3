import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.sortOrder) private var tags: [Tag]
    @Query private var shops: [Shop]
    @Query private var visits: [Visit]
    @Query private var photos: [Photo]

    @State private var exportURL: URL?
    @State private var exportMessage = ""
    @State private var restorer = BackupRestorer()
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        createCSV()
                    } label: {
                        Label("CSVファイルを作成", systemImage: "doc.text")
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("共有・保存（\(exportURL.lastPathComponent)）",
                                  systemImage: "square.and.arrow.up")
                        }
                    }
                    if !exportMessage.isEmpty {
                        Text(exportMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("データの書き出し")
                } footer: {
                    Text("店舗と来店記録を1つのCSVにまとめます（写真は含みません）。「共有・保存」から「ファイル」アプリに保存したり、メールで送ったりできます。Excelで開けます。")
                }

                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("バックアップから復元", systemImage: "arrow.down.doc")
                    }
                    .disabled(restorer.isRunning)

                    if let summary = restorer.summary {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.title)
                                .font(.callout.bold())
                            Text("店舗 \(summary.shopCount)件（新規 \(summary.newShopCount)件・登録済み \(summary.shopCount - summary.newShopCount)件）")
                            Text("来店記録 \(summary.visitCount)件・写真 \(summary.photoCount)枚")
                            Text(newTagText(summary))
                        }
                        .font(.caption)
                        HStack(spacing: 12) {
                            Button("取り込む") {
                                Task { await restorer.restore(context: context) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(restorer.isRunning || summary.newShopCount == 0)
                            Button("やめる") {
                                restorer.cancel()
                            }
                            .buttonStyle(.bordered)
                            .disabled(restorer.isRunning)
                        }
                    }
                    if restorer.isRunning {
                        ProgressView(restorer.progress)
                    }
                    if !restorer.message.isEmpty {
                        Text(restorer.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("バックアップから復元")
                } footer: {
                    Text("MoguLogバックアップ形式のフォルダ（backup.jsonとphotosフォルダが入ったもの）を選びます。登録済みの店舗は取り込まれないため、重複しません。")
                }

                CoordinateFillSection()

                Section("タグ候補（\(tags.count)件）") {
                    Text(tags.map(\.name).joined(separator: "、"))
                        .font(.callout)
                }

                Section("データ件数") {
                    LabeledContent("店舗", value: "\(shops.count)")
                    LabeledContent("来店記録", value: "\(visits.count)")
                    LabeledContent("写真", value: "\(photos.count)")
                    LabeledContent("写真の合計サイズ", value: photoSizeText)
                }

                Section("アプリ情報") {
                    LabeledContent("バージョン", value: appVersionText)
                }
            }
            .navigationTitle("設定")
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.folder],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        restorer.load(folder: url, context: context)
                    }
                case .failure(let error):
                    restorer.message = "フォルダを開けませんでした：\(error.localizedDescription)"
                }
            }
        }
    }

    private func newTagText(_ summary: BackupRestorer.Summary) -> String {
        if summary.newTagNames.isEmpty {
            return "新しく追加されるタグ：なし"
        }
        let names: String = summary.newTagNames.joined(separator: "、")
        return "新しく追加されるタグ：\(names)"
    }

    // 写真の合計サイズと1枚あたりの平均
    // ビルド時のバージョン番号（project.yml の MARKETING_VERSION / CURRENT_PROJECT_VERSION）
    private var appVersionText: String {
        let info: [String: Any] = Bundle.main.infoDictionary ?? [:]
        let version: String = info["CFBundleShortVersionString"] as? String ?? "-"
        let build: String = info["CFBundleVersion"] as? String ?? "-"
        return "\(version)（ビルド\(build)）"
    }

    private var photoSizeText: String {
        var total: Int = 0
        for photo in photos {
            total += photo.imageData.count
            total += photo.thumbnailData.count
        }
        let average: Int = photos.isEmpty ? 0 : total / photos.count
        let formatter = ByteCountFormatter()
        let totalText: String = formatter.string(fromByteCount: Int64(total))
        let averageText: String = formatter.string(fromByteCount: Int64(average))
        return "\(totalText)（1枚平均 \(averageText)）"
    }

    // CSVを一時フォルダに作成し、共有・保存できるようにする
    private func createCSV() {
        let csv: String = CSVExporter.makeCSV(shops: shops)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let fileName: String = "MoguLog_\(formatter.string(from: .now)).csv"
        let url: URL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        // BOM付きUTF-8（Excelで文字化けしないように：D-28）
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv.utf8))

        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
            exportMessage = "作成しました（店舗\(shops.count)件・来店記録\(visits.count)件）"
        } catch {
            exportURL = nil
            exportMessage = "作成できませんでした：\(error.localizedDescription)"
        }
    }
}
