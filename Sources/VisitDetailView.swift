import SwiftUI
import SwiftData

// 来店記録の詳細（閲覧専用。変更は「編集」から）
struct VisitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let visit: Visit

    @State private var showEdit = false
    @State private var viewerItem: ViewerItem?

    // 削除済みかどうか（削除直後の画面更新でのクラッシュ防止）
    private var isGone: Bool { visit.isDeleted || visit.modelContext == nil }

    private var livePhotos: [Photo] {
        visit.sortedPhotos.filter { !$0.isDeleted && $0.modelContext != nil }
    }

    var body: some View {
        if isGone {
            ContentUnavailableView("この来店記録は削除されました", systemImage: "trash")
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                LabeledContent("来店日", value: visit.dateText)
                HStack {
                    Text("評価")
                    Spacer()
                    StarRatingLabel(rating: visit.ratingValue)
                }
                if let shopName = visit.shop?.name {
                    LabeledContent("お店", value: shopName)
                }
            }
            Section("メモ") {
                if visit.memo.isEmpty {
                    Text("（なし）")
                        .foregroundStyle(.secondary)
                } else {
                    Text(visit.memo)
                }
            }
            Section("写真（\(livePhotos.count)枚）") {
                if livePhotos.isEmpty {
                    Text("（なし）")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(Array(livePhotos.enumerated()), id: \.element.id) { item in
                            ThumbnailImage(data: item.element.thumbnailData, size: 96)
                                .onTapGesture {
                                    let images: [Data] = livePhotos.map(\.imageData)
                                    viewerItem = ViewerItem(images: images, index: item.offset)
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("来店記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編集") { showEdit = true }
            }
        }
        // 編集画面で削除された場合は、閉じたあとに店舗詳細へ戻る
        .sheet(isPresented: $showEdit, onDismiss: {
            if isGone { dismiss() }
        }) {
            VisitEditView(mode: .edit(visit))
        }
        // 全画面で拡大表示（左右スワイプで次の写真：I-21）
        .fullScreenCover(item: $viewerItem) { item in
            PhotoPagerView(images: item.images, startIndex: item.index)
        }
    }
}
