import Foundation
import SwiftData

// タグ候補の初期登録（初回起動時のみ）
enum TagSeeder {
    static let presetNames = [
        "ラーメン", "うどん", "そば", "和食", "寿司", "焼肉", "洋食",
        "イタリアン", "中華", "カレー", "カフェ", "スイーツ", "パン",
        "居酒屋", "ランチ", "ディナー", "肉", "魚", "鶏"
    ]
    private static let seededKey = "didSeedPresetTags_v1"

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<Tag>())) ?? 0
        if existing == 0 {
            for (index, name) in presetNames.enumerated() {
                context.insert(Tag(name: name, isPreset: true, sortOrder: index))
            }
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: seededKey)
    }
}
