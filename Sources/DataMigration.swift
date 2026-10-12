import Foundation
import SwiftData

// データ移行（起動時に1回だけ実行）
enum DataMigration {
    private static let ratingKey = "didMigrateRatingValue_v1"

    // 整数の評価（rating）→ 小数の評価（ratingValue）へ移す（D-30）
    @MainActor
    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: ratingKey) else { return }
        let visits: [Visit] = (try? context.fetch(FetchDescriptor<Visit>())) ?? []
        for visit in visits {
            if visit.ratingValue == nil, let old = visit.rating {
                visit.ratingValue = Double(old)
            }
            visit.rating = nil   // 旧項目は今後使わない
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: ratingKey)
    }
}
