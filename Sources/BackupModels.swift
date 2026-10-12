import Foundation

// MoguLogバックアップ形式（formatVersion 1、D-33）
struct BackupFile: Decodable {
    let format: String
    let formatVersion: Int
    let createdAt: String?
    let origin: BackupOrigin?
    let tags: [BackupTag]
    let shops: [BackupShop]
}

struct BackupOrigin: Decodable {
    let type: String?
    let title: String?
    let recordCount: Int?
}

struct BackupTag: Decodable {
    let name: String
    let sortOrder: Int?
}

struct BackupShop: Decodable {
    let id: UUID
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?
    let phone: String?
    let url: String?
    let wantToGo: Bool
    let memo: String
    let source: String
    let createdAt: String
    let updatedAt: String
    let tags: [String]
    let visits: [BackupVisit]
}

struct BackupVisit: Decodable {
    let id: UUID
    let date: String?          // "yyyy-MM-dd"、日付不明はnull
    let dateUnknown: Bool
    let rating: Double?
    let memo: String
    let createdAt: String
    let updatedAt: String
    let externalID: String?    // 元データとの照合用（もぐレコの記録番号など）
    let photos: [BackupPhoto]
}

struct BackupPhoto: Decodable {
    let id: UUID
    let file: String           // フォルダ内の相対パス（photos/xxx.jpg）
    let takenAt: String?
    let latitude: Double?
    let longitude: Double?
    let sortOrder: Int
}
