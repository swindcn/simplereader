import SwiftUI

struct PaywallView: View {
    @Environment(\.appStrings) private var strings
    @Environment(\.openURL) private var openURL
    @ObservedObject var accessStore: PurchaseAccessStore
    @ObservedObject var purchaseManager: StoreKitPurchaseManager
    let onClose: () -> Void
    @State private var selectedKind: PurchaseProductKind = .annual
    @State private var isPurchasing = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 20) {
                    planStack
                    callToAction
                }
                .padding(.horizontal, DesignTokens.edgeMargin)
                .padding(.vertical, 24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            footer
        }
        .background(paywallBackground.ignoresSafeArea())
        .task { await purchaseManager.loadProducts() }
        .alert(strings.purchaseNotice, isPresented: purchaseErrorPresented) {
            Button(strings.ok, role: .cancel) { purchaseManager.dismissError() }
        } message: {
            Text(purchaseManager.errorMessage ?? strings.unknownError)
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .foregroundStyle(paywallPrimaryText)
            .accessibilityLabel(strings.closePaywall)
            Spacer()
        }
        .padding(.horizontal, 18)
        .background(paywallBackground)
        .overlay(alignment: .bottom) {
            Divider().background(paywallOutline)
        }
    }

    private var planStack: some View {
        VStack(spacing: 16) {
            ForEach(purchaseManager.options) { option in
                planCard(option)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func planCard(_ option: PurchaseProductOption) -> some View {
        let isSelected = selectedKind == option.kind
        return Button {
            selectedKind = option.kind
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(option.kind.title(in: strings))
                            .font(.title2.bold())
                            .foregroundStyle(paywallPrimaryText)
                        if option.kind == .annual {
                            Text(strings.includesSevenDayTrial)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(paywallAccent)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(option.displayPrice)
                            .font(.title2.bold())
                            .foregroundStyle(paywallPrimaryText)
                        let suffix = option.kind.priceSuffix(in: strings)
                        if !suffix.isEmpty {
                            Text(suffix)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(paywallSecondaryText)
                        }
                    }
                }
                Text(option.kind.detail(in: strings))
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(paywallSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(paywallCardBackground)
            .overlay(alignment: .topTrailing) {
                if option.kind == .annual {
                    Text(strings.bestValue)
                        .font(.caption.bold())
                        .textCase(.uppercase)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(paywallAccent)
                        .foregroundStyle(paywallAccentText)
                        .clipShape(Capsule())
                        .offset(x: -18, y: 0)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? paywallAccent : paywallOutline, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(planAccessibilityLabel(option))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var callToAction: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchaseSelectedPlan() }
            } label: {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(paywallAccentText)
                            .accessibilityHidden(true)
                    }
                    Text(ctaText)
                        .font(.title3.bold())
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(paywallAccent)
                .foregroundStyle(paywallAccentText)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .disabled(isPurchasing)
            .accessibilityLabel(ctaText)

            Text(strings.cancelInAppStoreSettings)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(paywallMutedText)
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 24) {
                Button(strings.restorePurchases) {
                    Task {
                        if await purchaseManager.restorePurchases() {
                            onClose()
                        }
                    }
                }
                Button(strings.privacyPolicy) {
                    openURL(LegalDocument.privacy.url)
                }
                Button(strings.termsOfService) {
                    openURL(LegalDocument.terms.url)
                }
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(paywallSecondaryText)
            .buttonStyle(.plain)
            .accessibilityElement(children: .contain)

            Text(strings.paywallCopyright)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(paywallMutedText)
        }
        .padding(.horizontal, DesignTokens.edgeMargin)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(paywallBackground)
        .overlay(alignment: .top) {
            Divider().background(paywallOutline)
        }
    }

    private var selectedOption: PurchaseProductOption {
        purchaseManager.options.first { $0.kind == selectedKind }
            ?? PurchaseProductOption(kind: selectedKind, product: nil)
    }

    private var ctaText: String {
        selectedKind == .annual ? strings.startSevenDayTrial : strings.continuePurchase
    }

    private func purchaseSelectedPlan() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        if await purchaseManager.purchase(selectedOption) {
            onClose()
        }
    }

    private func planAccessibilityLabel(_ option: PurchaseProductOption) -> String {
        var parts = [
            option.kind.title(in: strings),
            option.displayPrice,
            option.kind.detail(in: strings)
        ]
        if option.kind == .annual {
            parts.append(strings.includesSevenDayTrial)
            parts.append(strings.bestValue)
        }
        return parts.joined(separator: ", ")
    }

    private var purchaseErrorPresented: Binding<Bool> {
        Binding(
            get: { purchaseManager.errorMessage != nil },
            set: { if !$0 { purchaseManager.dismissError() } }
        )
    }

    private var paywallBackground: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.051, green: 0.051, blue: 0.051, alpha: 1)
                : UIColor.systemBackground
        })
    }

    private var paywallCardBackground: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1)
                : UIColor.secondarySystemBackground
        })
    }

    private var paywallPrimaryText: Color { Color(uiColor: .pureVoiceOnSurface) }
    private var paywallSecondaryText: Color { Color(uiColor: .pureVoiceOnSurfaceVariant) }
    private var paywallMutedText: Color { Color(uiColor: .secondaryLabel) }
    private var paywallOutline: Color { Color(uiColor: .pureVoiceOutline) }
    private var paywallAccent: Color { Color(red: 1, green: 0.72, blue: 0.35) }
    private var paywallAccentText: Color { Color(red: 0.16, green: 0.09, blue: 0) }
}
