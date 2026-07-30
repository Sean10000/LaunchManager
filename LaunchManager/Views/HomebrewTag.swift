import SwiftUI

struct HomebrewTag: View {
    var body: some View {
        Text("Homebrew")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.24, green: 0.21, blue: 0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(red: 0.36, green: 0.29, blue: 0.07), lineWidth: 1)
            )
            .foregroundStyle(Color(red: 0.96, green: 0.84, blue: 0.44))
    }
}
