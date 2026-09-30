import SwiftUI

struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("k8s.serviceDetails"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            VStack {
                Spacer()
                Image(systemName: "arrow.left")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text(L("k8s.selectService"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}
