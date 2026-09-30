import SwiftUI

struct OnboardingReadyStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text(L("onboarding.ready.title"))
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(L("onboarding.ready.detail"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            HStack(spacing: 24) {
                tipView(icon: "menubar.arrow.up.rectangle", text: L("onboarding.ready.tipMenuBar"))
                tipView(icon: "gearshape.fill", text: L("onboarding.ready.tipSettings"))
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(32)
    }

    private func tipView(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 140)
    }
}
