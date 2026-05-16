import SwiftUI

struct InstantSearchResultRow: View {
    let query: String
    let hostLabel: String
    let isDomain: Bool
    let isSelected: Bool
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 0.42, green: 0.38, blue: 0.95).opacity(0.88))
                    .frame(width: 26, height: 26)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: isDomain ? "globe" : "bolt.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Instant Search")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.40))
                Text(query)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(hostLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.32))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.40))
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .foregroundColor(isSelected ? .white : .white.opacity(0.82))
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isSelected)
    }
}
