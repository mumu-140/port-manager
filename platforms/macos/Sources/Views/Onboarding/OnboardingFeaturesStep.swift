import SwiftUI

struct OnboardingFeaturesStep: View {
    private let features: [(icon: String, title: String, description: String, color: Color)] = [
        ("magnifyingglass", L("onboarding.features.scanning.title"), L("onboarding.features.scanning.detail"), .blue),
        ("xmark.circle.fill", L("onboarding.features.quickKill.title"), L("onboarding.features.quickKill.detail"), .red),
        ("star.fill", L("onboarding.features.favorites.title"), L("onboarding.features.favorites.detail"), .yellow),
        ("eye.fill", L("onboarding.features.watched.title"), L("onboarding.features.watched.detail"), .purple),
        ("globe", L("onboarding.features.tunnels.title"), L("onboarding.features.tunnels.detail"), .orange),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("onboarding.features.title"))
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 4)

            ForEach(features, id: \.title) { feature in
                HStack(spacing: 14) {
                    Image(systemName: feature.icon)
                        .font(.title3)
                        .foregroundStyle(feature.color)
                        .frame(width: 28, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .fontWeight(.medium)
                        Text(feature.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
