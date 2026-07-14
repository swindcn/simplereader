import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Text(tab.title)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
            }
        }
    }
}
