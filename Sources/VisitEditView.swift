import SwiftUI
import SwiftData
import PhotosUI

struct VisitEditView: View {
    enum Mode {
        case new(Shop)
        case edit(Visit)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var date = Date.now
    @State private var dateUnknown = false
    @State private var rating: Double?
    @State private var memo = ""
    @State private var showDeleteConfirm = false
    @State private var loaded = false

    // 写真
    @State private var keptPhotos: [Photo] = []            // 既存の写真（編集時）
    @State private var newPhotos: [ProcessedPhoto] = []    // 追加した写真（保存前）
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isProcessing = false
    @State private var viewerItem: ViewerItem?

    private var isNew: Bool {
        if case .new = mode { return true } else { return false }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("日付不明", isOn: $dateUnknown)
                    if !dateUnknown {
                        DatePicker("来店日", selection: $date, in: ...Date.now,
                                   displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ja_JP"))   // 日本語表示（I-22）
                    }
                }
                Section("評価") {
                    StarRatingInput(rating: $rating)
                }
                Section("メモ") {
                    TextField("食べたもの・感想など", text: $memo, axis: .vertical)
                        .lineLimit(3...10)
                }
                Section {
                    if !keptPhotos.isEmpty || !newPhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(keptPhotos) { photo in
                                    photoCell(thumbnail: photo.thumbnailData,
                                              onTap: { viewerItem = ViewerItem(data: photo.imageData) },
                                              onRemove: { keptPhotos.removeAll { $0.id == photo.id } })
                                }
                                ForEach(newPhotos) { photo in
                                    photoCell(thumbnail: photo.thumbnailData,
                                              onTap: { viewerItem = ViewerItem(data: photo.imageData) },
                                              onRemove: { newPhotos.removeAll { $0.id == photo.id } })
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                        Label("写真を追加", systemImage: "photo.badge.plus")
                    }
                    .disabled(isProcessing)
                    if isProcessing {
                        ProgressView("写真を処理中…")
                    }
                } header: {
                    Text("写真（\(keptPhotos.count + newPhotos.count)枚）")
                } footer: {
                    Text("写真は縮小して保存します。×で外した写真は、保存した時点で削除されます。")
                }
                if !isNew {
                    Section {
                        Button("この来店記録を削除", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "来店記録を追加" : "来店記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(isProcessing)
                }
            }
            .confirmationDialog("この来店記録を削除しますか？",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("削除する", role: .destructive) { deleteVisit() }
            } message: {
                Text("この来店記録の写真も削除されます。元に戻せません。")
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
            .sheet(item: $viewerItem) { item in
                PhotoViewer(data: item.data)
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    // サムネイル＋×ボタン
    private func photoCell(thumbnail: Data,
                           onTap: @escaping () -> Void,
                           onRemove: @escaping () -> Void) -> some View {
        ThumbnailImage(data: thumbnail, size: 72)
            .onTapGesture(perform: onTap)
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .padding(2)
            }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if case .edit(let visit) = mode {
            date = visit.isDateUnknown ? .now : visit.date
            dateUnknown = visit.isDateUnknown
            rating = visit.ratingValue
            memo = visit.memo
            keptPhotos = visit.sortedPhotos
        }
    }

    // 選んだ写真を縮小して一時保持
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isProcessing = true
        defer {
            isProcessing = false
            pickerItems = []
        }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let processed = ImageTools.process(data) else { continue }
            // 新規の来店記録で最初の写真なら、撮影日を来店日にする（D-23）
            if isNew, keptPhotos.isEmpty, newPhotos.isEmpty, let taken = processed.meta.takenAt {
                date = min(taken, .now)
                dateUnknown = false
            }
            newPhotos.append(processed)
            await Task.yield()
        }
    }

    private func appendNewPhotos(to visit: Visit, startingAt start: Int) {
        for (offset, photo) in newPhotos.enumerated() {
            visit.photos.append(Photo(imageData: photo.imageData,
                                      thumbnailData: photo.thumbnailData,
                                      takenAt: photo.meta.takenAt,
                                      latitude: photo.meta.latitude,
                                      longitude: photo.meta.longitude,
                                      sortOrder: start + offset))
        }
    }

    private func save() {
        switch mode {
        case .new(let shop):
            let visit = Visit(date: date, rating: rating, memo: memo, isDateUnknown: dateUnknown)
            shop.visits.append(visit)
            appendNewPhotos(to: visit, startingAt: 0)
            shop.wantToGo = false
            shop.updatedAt = .now
        case .edit(let visit):
            visit.date = date
            visit.isDateUnknown = dateUnknown
            visit.ratingValue = rating
            visit.rating = nil
            visit.memo = memo
            visit.updatedAt = .now
            visit.shop?.updatedAt = .now
            // ×で外した既存写真を削除
            let keptIDs = Set(keptPhotos.map(\.id))
            let removed = visit.photos.filter { !keptIDs.contains($0.id) }
            for photo in removed {
                context.delete(photo)
            }
            // 並び順を振り直して、新しい写真を末尾に追加
            for (index, photo) in keptPhotos.enumerated() {
                photo.sortOrder = index
            }
            appendNewPhotos(to: visit, startingAt: keptPhotos.count)
        }
        try? context.save()
        dismiss()
    }

    private func deleteVisit() {
        guard case .edit(let visit) = mode else { return }
        visit.shop?.updatedAt = .now
        context.delete(visit)
        try? context.save()
        dismiss()
    }
}
