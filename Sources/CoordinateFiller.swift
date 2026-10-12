import SwiftUI
import SwiftData
import MapKit
import UIKit

// 住所から座標を補完（F-22、D-31）
@MainActor
@Observable
final class CoordinateFiller {
    var isRunning = false
    var progress = ""
    var message = ""
    var failedNames: [String] = []
    private var shouldStop = false

    private struct Found {
        let latitude: Double
        let longitude: Double
        let byName: Bool
    }

    func stop() {
        shouldStop = true
    }

    func run(context: ModelContext) async {
        let all: [Shop] = (try? context.fetch(FetchDescriptor<Shop>())) ?? []
        let targets: [Shop] = all.filter { $0.latitude == nil || $0.longitude == nil }
        guard !targets.isEmpty else {
            message = "座標のない店舗はありません"
            return
        }
        isRunning = true
        shouldStop = false
        failedNames = []
        message = ""
        UIApplication.shared.isIdleTimerDisabled = true   // 処理中は自動消灯しない
        defer {
            isRunning = false
            progress = ""
            UIApplication.shared.isIdleTimerDisabled = false
        }

        var byAddress = 0
        var byName = 0
        var notFound = 0
        for (index, shop) in targets.enumerated() {
            if shouldStop { break }
            progress = "\(index + 1) / \(targets.count)：\(shop.name)"
            if let found = await locate(shop) {
                shop.latitude = found.latitude
                shop.longitude = found.longitude
                if found.byName { byName += 1 } else { byAddress += 1 }
                try? context.save()
            } else {
                notFound += 1
                failedNames.append(shop.name)
            }
        }
        let head: String = shouldStop ? "停止しました。" : "完了しました。"
        message = "\(head)住所で取得 \(byAddress)件、店名で取得 \(byName)件、見つからず \(notFound)件"
    }

    // ①住所全体 →②建物名より前 →③店名＋住所
    private func locate(_ shop: Shop) async -> Found? {
        let address: String = shop.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.split(whereSeparator: { $0 == " " || $0 == "　" })
        let firstPart: String = parts.first.map { String($0) } ?? ""

        if !address.isEmpty {
            if let c = await searchAddress(address) {
                return Found(latitude: c.latitude, longitude: c.longitude, byName: false)
            }
            if !firstPart.isEmpty && firstPart != address {
                if let c = await searchAddress(firstPart) {
                    return Found(latitude: c.latitude, longitude: c.longitude, byName: false)
                }
            }
        }
        if let c = await searchShop(name: shop.name, area: firstPart) {
            return Found(latitude: c.latitude, longitude: c.longitude, byName: true)
        }
        return nil
    }

    private func searchAddress(_ query: String) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        guard let items = await perform(request) else { return nil }
        return items.first.map { $0.location.coordinate }.flatMap(validated)
    }

    // 店名が一致する候補だけを採用
    private func searchShop(name: String, area: String) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = area.isEmpty ? name : "\(name) \(area)"
        request.resultTypes = .pointOfInterest
        guard let items = await perform(request) else { return nil }
        let key: String = TagRules.normalized(name)
        let match = items.first { item in
            let candidate: String = TagRules.normalized(item.name ?? "")
            return !candidate.isEmpty && (candidate.contains(key) || key.contains(candidate))
        }
        return match.map { $0.location.coordinate }.flatMap(validated)
    }

    // 日本の範囲外は採用しない
    private func validated(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D? {
        let inJapan: Bool = (20.0...46.0).contains(c.latitude) && (122.0...154.0).contains(c.longitude)
        return inJapan ? c : nil
    }

    // 間隔を空けて検索。利用制限にかかったら60秒待って1回だけ再試行
    private func perform(_ request: MKLocalSearch.Request) async -> [MKMapItem]? {
        for attempt in 0..<2 {
            try? await Task.sleep(for: .milliseconds(1200))
            do {
                let response = try await MKLocalSearch(request: request).start()
                return response.mapItems
            } catch let error as MKError where error.code == .loadingThrottled && attempt == 0 {
                progress += "（利用制限のため60秒待機中）"
                try? await Task.sleep(for: .seconds(60))
            } catch {
                return nil
            }
        }
        return nil
    }
}

// 設定画面の「座標の補完」セクション
struct CoordinateFillSection: View {
    @Environment(\.modelContext) private var context
    @Query private var shops: [Shop]
    @State private var filler = CoordinateFiller()

    private var missingCount: Int {
        shops.filter { $0.latitude == nil || $0.longitude == nil }.count
    }

    var body: some View {
        Section {
            LabeledContent("座標のない店舗", value: "\(missingCount)件")
            if filler.isRunning {
                ProgressView(filler.progress)
                Button("停止", role: .destructive) {
                    filler.stop()
                }
            } else {
                Button {
                    Task { await filler.run(context: context) }
                } label: {
                    Label("住所から座標を補完", systemImage: "mappin.and.ellipse")
                }
                .disabled(missingCount == 0)
            }
            if !filler.message.isEmpty {
                Text(filler.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !filler.failedNames.isEmpty {
                DisclosureGroup("見つからなかった店舗（\(filler.failedNames.count)件）") {
                    ForEach(Array(filler.failedNames.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.caption)
                    }
                }
            }
        } header: {
            Text("座標の補完")
        } footer: {
            Text("住所からAppleマップで座標を検索します。1件ずつ間隔を空けて処理するため、300件で10〜20分程度かかります（目安）。処理中は画面を開いたままにしてください。途中で停止しても、次回は残りの店舗から再開します。")
        }
    }
}
