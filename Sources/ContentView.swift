import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            Tab("一覧", systemImage: "list.bullet") {
                ShopListView()
            }
            Tab("設定", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .task {
            TagSeeder.seedIfNeeded(context: context)
            DataMigration.migrateIfNeeded(context: context)
        }
    }
}
