import SwiftUI

@main
struct HandyApp3App: App {
    @State private var store: AssetStore = {
        let s = AssetStore()
        s.seedBuiltInComboLists()
        s.seedBuiltInCategories()
        s.seedBuiltInTypes()
        s.seedBuiltInAssets()
        return s
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
