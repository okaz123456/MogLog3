import Foundation
import SwiftData

// 登録方法
enum ShopSource: String, Codable, CaseIterable {
    case keyword    // キーワード検索
    case photo      // 写真から
    case manual     // 手入力
    case mogureco   // もぐレコから移行（D-35）
}

// 店舗
@Model
final class Shop {
    var id: UUID = UUID()
    var name: String = ""
    var address: String = ""
    var latitude: Double?
    var longitude: Double?
    var phone: String?
    var url: String?
    var wantToGo: Bool = false
    var memo: String = ""
    var sourceRaw: String = ShopSource.manual.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // 店舗を消すと来店記録も消える
    @Relationship(deleteRule: .cascade, inverse: \Visit.shop)
    var visits: [Visit] = []

    // 店舗を消してもタグは残る
    @Relationship(deleteRule: .nullify, inverse: \Tag.shops)
    var tags: [Tag] = []

    init(name: String,
         address: String = "",
         latitude: Double? = nil,
         longitude: Double? = nil,
         source: ShopSource = .manual,
         wantToGo: Bool = false) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.sourceRaw = source.rawValue
        self.wantToGo = wantToGo
    }

    // ---- 以下は保存しない算出値 ----
    var source: ShopSource { ShopSource(rawValue: sourceRaw) ?? .manual }

    var isVisited: Bool { !visits.isEmpty }

    var averageRating: Double? {
        let ratings: [Double] = visits.compactMap(\.ratingValue)
        guard !ratings.isEmpty else { return nil }
        return ratings.reduce(0, +) / Double(ratings.count)
    }

    // 来店記録を新しい順に（日付不明は末尾）
    var visitsNewestFirst: [Visit] { visits.sorted(by: Visit.newerFirst) }

    // 評価が付いている来店記録のうち、最も新しいものの評価
    var latestRating: Double? {
        visitsNewestFirst.first(where: { $0.ratingValue != nil })?.ratingValue
    }

    // 日付不明の記録は除外（D-29）
    var lastVisitDate: Date? {
        visits.filter { !$0.isDateUnknown }.map(\.date).max()
    }

    var sortedTags: [Tag] { tags.sorted { $0.sortOrder < $1.sortOrder } }
}

// 来店記録
@Model
final class Visit {
    var id: UUID = UUID()
    var shop: Shop?
    var date: Date = Date.now
    var rating: Int?               // 旧：整数の評価（ratingValueへ移行後は使わない）
    var ratingValue: Double?       // 評価：0.5〜5.0（0.5刻み）、未評価はnil（D-30）
    var isDateUnknown: Bool = false  // 日付不明（D-29）
    var memo: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // 来店記録を消すと写真も消える
    @Relationship(deleteRule: .cascade, inverse: \Photo.visit)
    var photos: [Photo] = []

    init(date: Date = .now, rating: Double? = nil, memo: String = "", isDateUnknown: Bool = false) {
        self.date = date
        self.ratingValue = rating
        self.memo = memo
        self.isDateUnknown = isDateUnknown
    }

    var sortedPhotos: [Photo] { photos.sorted { $0.sortOrder < $1.sortOrder } }

    var dateText: String {
        isDateUnknown ? "日付不明" : JPDate.day(date)
    }

    // 新しい順の並べ替え用：日付ありが先、日付不明は登録の新しい順で末尾
    static func newerFirst(_ a: Visit, _ b: Visit) -> Bool {
        if a.isDateUnknown != b.isDateUnknown {
            return !a.isDateUnknown
        }
        if a.isDateUnknown {
            return a.createdAt > b.createdAt
        }
        return a.date > b.date
    }
}

// 写真
@Model
final class Photo {
    var id: UUID = UUID()
    var visit: Visit?
    @Attribute(.externalStorage) var imageData: Data = Data()   // 縮小版（DB本体の外に保存）
    var thumbnailData: Data = Data()                            // 一覧用サムネイル
    var takenAt: Date?
    var latitude: Double?
    var longitude: Double?
    var sortOrder: Int = 0

    init(imageData: Data,
         thumbnailData: Data,
         takenAt: Date? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil,
         sortOrder: Int = 0) {
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.takenAt = takenAt
        self.latitude = latitude
        self.longitude = longitude
        self.sortOrder = sortOrder
    }
}

// タグ
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var isPreset: Bool = true   // falseにすると候補から外れる
    var sortOrder: Int = 0
    var shops: [Shop] = []

    init(name: String, isPreset: Bool = true, sortOrder: Int = 0) {
        self.name = name
        self.isPreset = isPreset
        self.sortOrder = sortOrder
    }
}
