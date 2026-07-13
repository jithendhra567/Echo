import SwiftUI

struct DevicesSettingsPane: View {
    @Environment(CompanionController.self) private var companion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                paneHeader(
                    icon: "iphone",
                    title: "Phone",
                    subtitle: "Pair Echo on Android over your local Wi‑Fi"
                )

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Allow phone connections", isOn: Binding(
                            get: { companion.isEnabled },
                            set: { companion.setEnabled($0) }
                        ))
                        .font(.headline)

                        Text(companion.statusText)
                            .font(.subheadline)
                            .foregroundStyle(companion.isPaired ? .green : .secondary)

                        if let device = companion.pairedDeviceName, companion.isPaired {
                            Label("Paired with \(device)", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }

                        if let err = companion.lastError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(8)
                }

                if companion.isEnabled {
                    GroupBox {
                        VStack(spacing: 16) {
                            Text("Scan with the Echo Android app")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let qr = companion.pairingQR {
                                Image(nsImage: qr)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 220, height: 220)
                                    .padding(12)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                ProgressView()
                                    .frame(width: 220, height: 220)
                            }

                            Text("Phone and Mac must be on the same Wi‑Fi. Grant Screen Recording when asked so individual apps can stream.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack {
                                Button("Refresh QR") {
                                    companion.rotateCode()
                                }
                                Button("Refresh network IP") {
                                    companion.refreshPairingPayload()
                                }
                                Spacer()
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .padding(24)
        }
    }

    private func paneHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
