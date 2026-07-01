import SwiftUI

struct ServicesListView: View {
    @ObservedObject var store: ServiceStore
    @Binding var errorMessage: String?

    var body: some View {
        Text("Services")
    }
}
