import Foundation
import SwiftData

// タグの重複防止（D-17）
enum TagRules {
    // 比較用の正規化：前後の空白、全角/半角、大文字/小文字の違いを無視
    static func normalized(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let halfwidth = trimmed.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? trimmed
        return halfwidth.lowercased()
    }

    // 同じ名前のタグがあればそれを返し、なければ新規作成して候補の末尾に追加（D-19）
    @MainActor
    static func findOrCreate(name: String, in context: ModelContext, existing: [Tag]) -> Tag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = normalized(trimmed)
        if let found = existing.first(where: { normalized($0.name) == key }) {
            return found
        }
        let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        let tag = Tag(name: trimmed, isPreset: true, sortOrder: nextOrder)
        context.insert(tag)
        try? context.save()
        return tag
    }
}
