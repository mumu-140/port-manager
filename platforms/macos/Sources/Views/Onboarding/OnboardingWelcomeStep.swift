import SwiftUI

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "network")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)

            Text(L("onboarding.welcome.title"))
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(L("onboarding.welcome.subtitle"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
        }
        .padding(32)
    }
}
