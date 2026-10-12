import Foundation

// 日付の日本語表示（I-22）
enum JPDate {
    private static let dayFormatter: DateFormatter = makeFormatter("yyyy年M月d日")
    private static let dayTimeFormatter: DateFormatter = makeFormatter("yyyy年M月d日 H:mm")
    private static let monthFormatter: DateFormatter = makeFormatter("yyyy年MM月")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }

    // 2026年1月30日
    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    // 2026年1月30日 12:34
    static func dayTime(_ date: Date) -> String {
        dayTimeFormatter.string(from: date)
    }

    // 2026年01月（月ごとの見出し用：I-23）
    static func month(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }
}
