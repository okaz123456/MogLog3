import Foundation
import Observation
import SwiftData

// バックアップからの復元（F-19、もぐレコ移行F-21を含む）
@MainActor
@Observable
final class BackupRestorer {
    struct Summary {
        let title: String
        let shopCount: Int
        let newShopCount: Int
        let visitCount: Int
        let photoCount: Int
        let newTagNames: [String]
    }

    var summary: Summary?
    var progress = ""
    var message = ""
    var isRunning = false

    private var backup: BackupFile?
    private var folderURL: URL?

    // フォルダを読み込み、取り込み内容の概要を作る（まだ保存はしない）
    func load(folder: URL, context: ModelContext) {
        message = ""
        summary = nil
        backup = nil
        let accessing = folder.startAccessingSecurityScopedResource()
        defer {
            if accessing { folder.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: folder.appendingPathComponent("backup.json"))
            let file = try JSONDecoder().decode(BackupFile.self, from: data)
            guard file.format == "MoguLogBackup", file.formatVersion == 1 else {
                message = "MoguLogのバックアップ形式ではありません"
                return
            }
            let existingShops: [Shop] = (try? context.fetch(FetchDescriptor<Shop>())) ?? []
            let existingIDs: Set<UUID> = Set(existingShops.map(\.id))
            let existingTags: [Tag] = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
            let existingKeys: Set<String> = Set(existingTags.map { TagRules.normalized($0.name) })

            var newTags: [String] = []
            for tag in file.tags where !existingKeys.contains(TagRules.normalized(tag.name)) {
                newTags.append(tag.name)
            }
            var visitCount = 0
            var photoCount = 0
            for shop in file.shops {
                visitCount += shop.visits.count
                for visit in shop.visits {
                    photoCount += visit.photos.count
                }
            }
            let newShopCount: Int = file.shops.filter { !existingIDs.contains($0.id) }.count

            summary = Summary(title: file.origin?.title ?? "MoguLogバックアップ",
                              shopCount: file.shops.count,
                              newShopCount: newShopCount,
                              visitCount: visitCount,
                              photoCount: photoCount,
                              newTagNames: newTags)
            backup = file
            folderURL = folder
        } catch {
            message = "読み込めませんでした：\(error.localizedDescription)"
        }
    }

    func cancel() {
        summary = nil
        backup = nil
        folderURL = nil
    }

    // 取り込み（登録済みの店舗はスキップ）
    func restore(context: ModelContext) async {
        guard let backup, let folderURL else { return }
        isRunning = true
        message = ""
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { folderURL.stopAccessingSecurityScopedResource() }
            isRunning = false
            progress = ""
        }

        // タグ：既存は名前で照合、ないものは候補の末尾に追加（D-19、D-32）
        let existingTags: [Tag] = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        var tagsByKey: [String: Tag] = [:]
        for tag in existingTags {
            tagsByKey[TagRules.normalized(tag.name)] = tag
        }
        var nextOrder: Int = (existingTags.map(\.sortOrder).max() ?? -1) + 1
        for backupTag in backup.tags {
            let key = TagRules.normalized(backupTag.name)
            if tagsByKey[key] == nil {
                let tag = Tag(name: backupTag.name, isPreset: true, sortOrder: nextOrder)
                nextOrder += 1
                context.insert(tag)
                tagsByKey[key] = tag
            }
        }

        let existingShops: [Shop] = (try? context.fetch(FetchDescriptor<Shop>())) ?? []
        let existingIDs: Set<UUID> = Set(existingShops.map(\.id))
        var addedShops = 0
        var skippedShops = 0
        var addedVisits = 0
        var addedPhotos = 0
        var photoErrors = 0
        let total = backup.shops.count

        for (index, backupShop) in backup.shops.enumerated() {
            if existingIDs.contains(backupShop.id) {
                skippedShops += 1
                continue
            }
            let shop = Shop(name: backupShop.name,
                            address: backupShop.address,
                            latitude: backupShop.latitude,
                            longitude: backupShop.longitude,
                            source: ShopSource(rawValue: backupShop.source) ?? .manual,
                            wantToGo: backupShop.wantToGo)
            shop.id = backupShop.id
            shop.phone = backupShop.phone
            shop.url = backupShop.url
            shop.memo = backupShop.memo
            shop.createdAt = Self.parseDateTime(backupShop.createdAt) ?? .now
            shop.updatedAt = Self.parseDateTime(backupShop.updatedAt) ?? .now
            context.insert(shop)
            shop.tags = backupShop.tags.compactMap { tagsByKey[TagRules.normalized($0)] }

            for backupVisit in backupShop.visits {
                let created: Date = Self.parseDateTime(backupVisit.createdAt) ?? .now
                let day: Date? = backupVisit.dateUnknown ? nil : Self.parseDay(backupVisit.date)
                let visit = Visit(date: day ?? created,
                                  rating: backupVisit.rating,
                                  memo: backupVisit.memo,
                                  isDateUnknown: day == nil)
                visit.id = backupVisit.id
                visit.createdAt = created
                visit.updatedAt = Self.parseDateTime(backupVisit.updatedAt) ?? created
                shop.visits.append(visit)
                addedVisits += 1

                for backupPhoto in backupVisit.photos.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    let fileURL = folderURL.appendingPathComponent(backupPhoto.file)
                    guard let data = try? Data(contentsOf: fileURL),
                          let thumbnail = ImageTools.makeThumbnail(data) else {
                        photoErrors += 1
                        continue
                    }
                    let photo = Photo(imageData: data,
                                      thumbnailData: thumbnail,
                                      takenAt: Self.parseDateTime(backupPhoto.takenAt),
                                      latitude: backupPhoto.latitude,
                                      longitude: backupPhoto.longitude,
                                      sortOrder: backupPhoto.sortOrder)
                    photo.id = backupPhoto.id
                    visit.photos.append(photo)
                    addedPhotos += 1
                }
            }
            addedShops += 1

            // 20店舗ごとに保存し、進捗を表示
            if index % 20 == 0 {
                progress = "取り込み中… \(index + 1) / \(total) 店舗"
                try? context.save()
                await Task.yield()
            }
        }
        try? context.save()

        var result = "取り込み完了：店舗\(addedShops)件、来店記録\(addedVisits)件、写真\(addedPhotos)枚"
        if skippedShops > 0 {
            result += "（登録済みのためスキップした店舗\(skippedShops)件）"
        }
        if photoErrors > 0 {
            result += "。読み込めなかった写真\(photoErrors)枚"
        }
        message = result
        summary = nil
        self.backup = nil
        self.folderURL = nil
    }

    // "2025-10-17T12:00:00+09:00" 形式
    private static func parseDateTime(_ text: String?) -> Date? {
        guard let text else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    // "2025-10-17" 形式 → その日の12時
    private static func parseDay(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let day = formatter.date(from: text) else { return nil }
        return Calendar.current.date(byAdding: .hour, value: 12, to: day)
    }
}
