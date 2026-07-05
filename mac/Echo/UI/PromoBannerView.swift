import AppKit
import SwiftUI

enum PromoDismissStore {
    private static let key = "echo.dismissed_promo_ids"

    static func isDismissed(promoID: String) -> Bool {
        dismissedIDs.contains(promoID)
    }

    static func dismiss(promoID: String) {
        var ids = dismissedIDs
        ids.insert(promoID)
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    private static var dismissedIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
}

struct PromoBannerView: View {
    let promo: PromoConfig
    let onLinkTap: () -> Void
    let onDismiss: () -> Void

    @State private var didLogImpression = false

    var body: some View {
        HStack(spacing: 10) {
            Text(promo.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let url = promo.linkURL {
                Button {
                    NSWorkspace.shared.open(url)
                    AnalyticsService.logPromoClick(promoID: promo.id, linkURL: url.absoluteString)
                    onLinkTap()
                } label: {
                    HStack(spacing: 4) {
                        Text(promo.linkText)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                }
                .buttonStyle(.plain)
            }

            Button {
                PromoDismissStore.dismiss(promoID: promo.id)
                AnalyticsService.logPromoDismiss(promoID: promo.id)
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(promo.backgroundColor)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .onAppear {
            guard !didLogImpression else { return }
            didLogImpression = true
            AnalyticsService.logPromoImpression(promoID: promo.id)
        }
    }
}
