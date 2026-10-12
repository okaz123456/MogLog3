import Foundation

// CSVエクスポート（F-18、形式はD-28）
enum CSVExporter {
    static let headers: [String] = [
        "店名", "住所", "状態", "タグ", "店メモ", "電話", "URL", "緯度", "経度",
        "登録方法", "登録日", "来店日", "評価", "来店メモ", "写真枚数"
    ]

    // 1行＝来店記録1件。来店記録のない店は来店欄を空欄で1行
    static func makeCSV(shops: [Shop]) -> String {
        var lines: [String] = [row(headers)]
        let liveShops: [Shop] = shops
            .filter { !$0.isDeleted && $0.modelContext != nil }
            .sorted { $0.createdAt < $1.createdAt }
        for shop in liveShops {
            let shopFields: [String] = shopColumns(shop)
            let visits: [Visit] = shop.visits
                .filter { !$0.isDeleted && $0.modelContext != nil }
                .sorted(by: Visit.newerFirst)
                .reversed()
            if visits.isEmpty {
                let emptyVisit: [String] = ["", "", "", ""]
                lines.append(row(shopFields + emptyVisit))
            } else {
                for visit in visits {
                    let visitFields: [String] = visitColumns(visit)
                    lines.append(row(shopFields + visitFields))
                }
            }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func shopColumns(_ shop: Shop) -> [String] {
        let status: String = shop.isVisited ? "行った" : "行きたい"
        let tags: String = shop.sortedTags.map(\.name).joined(separator: "・")
        let latitude: String = shop.latitude.map { String(format: "%.6f", $0) } ?? ""
        let longitude: String = shop.longitude.map { String(format: "%.6f", $0) } ?? ""
        let source: String
        switch shop.source {
        case .keyword: source = "キーワード検索"
        case .photo: source = "写真"
        case .manual: source = "手入力"
        case .mogureco: source = "もぐレコから移行"
        }
        return [shop.name, shop.address, status, tags, shop.memo,
                shop.phone ?? "", shop.url ?? "", latitude, longitude,
                source, dateText(shop.createdAt)]
    }

    private static func visitColumns(_ visit: Visit) -> [String] {
        let date: String = visit.isDateUnknown ? "日付不明" : dateText(visit.date)
        let rating: String = visit.ratingValue.map { String(format: "%.1f", $0) } ?? ""
        let photoCount: String = String(visit.photos.count)
        return [date, rating, visit.memo, photoCount]
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    private static func row(_ fields: [String]) -> String {
        var escapedFields: [String] = []
        for field in fields {
            escapedFields.append(escape(field))
        }
        return escapedFields.joined(separator: ",")
    }

    // カンマ・ダブルクォート・改行を含む項目は "" で囲む
    private static func escape(_ field: String) -> String {
        let needsQuote: Bool = field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        let escaped: String = field.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuote ? "\"\(escaped)\"" : escaped
    }
}
