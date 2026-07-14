import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Text("书架")
                .tabItem {
                    Label("书架", systemImage: "books.vertical")
                }

            Text("导入")
                .tabItem {
                    Label("导入", systemImage: "square.and.arrow.down")
                }

            Text("设置")
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
    }
}
