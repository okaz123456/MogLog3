import SwiftUI

// 星評価（入力用）：星の左半分で0.5、右半分で1.0。選択中の値をもう一度タップすると未評価
struct StarRatingInput: View {
    @Binding var rating: Double?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { index in
                star(index)
            }
            Spacer()
            Text(rating.map { String(format: "%.1f / 5", $0) } ?? "未評価")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func star(_ index: Int) -> some View {
        let value: Double = rating ?? 0
        let full: Double = Double(index)
        let half: Double = full - 0.5
        let isLit: Bool = value >= half
        return Image(systemName: StarRatingLabel.symbol(for: index, value: value))
            .font(.title2)
            .foregroundStyle(isLit ? Color.orange : Color.secondary)
            .frame(width: 36, height: 36)
            .overlay {
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { select(half) }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { select(full) }
                }
            }
    }

    private func select(_ value: Double) {
        rating = (rating == value) ? nil : value
    }
}

// 星評価（表示用）
struct StarRatingLabel: View {
    let rating: Double?

    static func symbol(for index: Int, value: Double) -> String {
        let full: Double = Double(index)
        if value >= full { return "star.fill" }
        if value >= full - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }

    var body: some View {
        if let rating {
            HStack(spacing: 4) {
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { index in
                        Image(systemName: Self.symbol(for: index, value: rating))
                    }
                }
                .foregroundStyle(.orange)
                Text(String(format: "%.1f", rating))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        } else {
            Text("未評価")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
