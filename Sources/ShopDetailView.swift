import SwiftUI
import SwiftData
import MapKit

struct ShopDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let shop: Shop

    @State private var showEdit = false
    @State private var showAddVisit = false
    @State private var selectedVisit: Visit?
    @State private var viewerItem: ViewerItem?

    // 削除済みかどうか（削除直後の画面更新でのクラッシュ防止）
    private var isGone: Bool { shop.isDeleted || shop.modelContext == nil }

    var body: some View {
        if isGone {
            ContentUnavailableView("このお店は削除されました", systemImage: "trash")
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(shop.name)
                        .font(.title3.bold())
                    // 店名の下に平均評価の星（I-25）
                    StarRatingLabel(rating: shop.averageRating)
                    if !shop.address.isEmpty {
                        Text(shop.address)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if !shop.tags.isEmpty {
                        Text(shop.sortedTags.map(\.name).joined(separator: "・"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if let lat = shop.latitude, let lon = shop.longitude {
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,
                                                                    latitudinalMeters: 500,
                                                                    longitudinalMeters: 500))) {
                        Marker(shop.name, coordinate: coordinate)
                    }
                    .frame(height: 180)
                    .allowsHitTesting(false)
                    .listRowInsets(EdgeInsets())
                }

                if let phone = shop.phone, !phone.isEmpty,
                   let telURL = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                    Link(destination: telURL) {
                        Label(phone, systemImage: "phone")
                    }
                }
                if let urlString = shop.url, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("Webサイト", systemImage: "safari")
                    }
                }
            }

            Section("評価") {
                LabeledContent("平均",
                               value: shop.averageRating.map { String(format: "★%.1f", $0) } ?? "未評価")
                HStack {
                    Text("直近")
                    Spacer()
                    StarRatingLabel(rating: shop.latestRating)
                }
                LabeledContent("来店回数", value: "\(shop.visits.count)回")
            }

            if !shop.memo.isEmpty {
                Section("店メモ") {
                    Text(shop.memo)
                }
            }

            Section("来店記録") {
                Button {
                    showAddVisit = true
                } label: {
                    Label("来店記録を追加", systemImage: "plus.circle")
                }
                ForEach(sortedVisits) { visit in
                    VisitRowView(visit: visit,
                                 onOpen: { selectedVisit = visit },
                                 onPhotoTap: { images, index in
                                     viewerItem = ViewerItem(images: images, index: index)
                                 })
                }
            }
        }
        .navigationTitle("お店の詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編集") { showEdit = true }
            }
        }
        .navigationDestination(item: $selectedVisit) { visit in
            VisitDetailView(visit: visit)
        }
        // 編集画面で削除された場合は、閉じたあとに一覧へ戻る
        .sheet(isPresented: $showEdit, onDismiss: {
            if isGone { dismiss() }
        }) {
            NavigationStack {
                ShopEditView(mode: .edit(shop))
            }
        }
        .sheet(isPresented: $showAddVisit) {
            VisitEditView(mode: .new(shop))
        }
        // 写真をタップしたら全画面で拡大表示（I-20）
        .fullScreenCover(item: $viewerItem) { item in
            PhotoPagerView(images: item.images, startIndex: item.index)
        }
    }

    // 新しい順（日付不明は末尾：D-29）
    private var sortedVisits: [Visit] {
        shop.visits
            .filter { !$0.isDeleted && $0.modelContext != nil }
            .sorted(by: Visit.newerFirst)
    }
}

// 来店記録の行：上段（日付・星・メモ）をタップすると詳細へ、写真をタップすると拡大表示
struct VisitRowView: View {
    let visit: Visit
    var onOpen: () -> Void = {}
    var onPhotoTap: ([Data], Int) -> Void = { _, _ in }

    // 削除直後の写真を参照しないように除外
    private var livePhotos: [Photo] {
        visit.sortedPhotos.filter { !$0.isDeleted && $0.modelContext != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(visit.dateText)
                            .foregroundStyle(visit.isDateUnknown ? Color.secondary : Color.primary)
                        Spacer()
                        StarRatingLabel(rating: visit.ratingValue)
                    }
                    if !visit.memo.isEmpty {
                        Text(visit.memo)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }

            if !livePhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(livePhotos.enumerated()), id: \.element.id) { item in
                            ThumbnailImage(data: item.element.thumbnailData, size: 64)
                                .onTapGesture {
                                    let images: [Data] = livePhotos.map(\.imageData)
                                    onPhotoTap(images, item.offset)
                                }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
