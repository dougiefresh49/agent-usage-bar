import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct DevicesSettingsView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var connectedService: ConnectedUsageService
    @ObservedObject var deviceSyncManager: DeviceSyncManager
    @State private var showingAddDevice = false
    @State private var deviceToRemove: PairedDevice?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Sync to Android", systemImage: "iphone.and.arrow.forward")
                        .font(.title3.weight(.semibold))
                    Text("Pair a phone over your local network. The QR code contains no credentials, and the Mac must approve every new device.")
                        .foregroundStyle(.secondary)

                    Button("Add Device") {
                        showingAddDevice = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }

            Section("Paired Devices") {
                if deviceSyncManager.devices.isEmpty {
                    Text("No paired devices")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(deviceSyncManager.devices) { device in
                        deviceRow(device)
                    }
                }
            }

            Section("If a device is lost") {
                Text("Removing a device stops future sync and queues deletion of credentials transferred by this Mac. The phone receives the wipe when it next reaches this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Emergency provider revocation") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For immediate protection, invalidate the credentials at their source:")
                        Link("OpenAI — review active sessions", destination: URL(string: "https://chatgpt.com/")!)
                        Link("Claude — log out all sessions", destination: URL(string: "https://claude.ai/settings/account")!)
                        Link("Cursor — sign out and re-authenticate", destination: URL(string: "https://cursor.com/settings")!)
                        Link("ElevenLabs — replace the API key", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                    }
                    .font(.caption)
                    .padding(.top, 6)
                }
            }

            if let message = deviceSyncManager.serverMessage {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddDevice) {
            AddDeviceSheet(
                service: service,
                notificationService: notificationService,
                connectedService: connectedService,
                deviceSyncManager: deviceSyncManager
            )
        }
        .alert(
            "Remove \(deviceToRemove?.name ?? "device")?",
            isPresented: Binding(
                get: { deviceToRemove != nil },
                set: { if !$0 { deviceToRemove = nil } }
            ),
            presenting: deviceToRemove
        ) { device in
            Button("Cancel", role: .cancel) {}
            Button("Remove Device", role: .destructive) {
                deviceSyncManager.removeDevice(device)
                deviceToRemove = nil
            }
        } message: { _ in
            Text("Future sync will stop immediately. A credential wipe will be delivered when the phone next contacts this Mac.")
        }
    }

    private func deviceRow(_ device: PairedDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: device.isRevoked ? "iphone.slash" : "iphone")
                .font(.title2)
                .foregroundStyle(device.isRevoked ? Color.secondary : Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .fontWeight(.medium)
                Text("Key \(device.fingerprint)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if device.isRevoked {
                    Text("Removed — credential wipe queued")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let lastSeen = device.lastSeenAt {
                    Text("Last seen \(lastSeen.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if device.isRevoked {
                if wipeWasDelivered(to: device) {
                    Button("Forget") {
                        deviceSyncManager.forgetDevice(device)
                    }
                } else {
                    Text("Waiting for phone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Remove", role: .destructive) {
                    deviceToRemove = device
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func wipeWasDelivered(to device: PairedDevice) -> Bool {
        device.wipeAcknowledgedAt != nil
    }
}

private struct AddDeviceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var connectedService: ConnectedUsageService
    @ObservedObject var deviceSyncManager: DeviceSyncManager

    @State private var syncPolling = true
    @State private var syncAppearance = true
    @State private var syncNotifications = true
    @State private var syncOpenAI = false
    @State private var syncCursor = false
    @State private var syncElevenLabs = false
    @State private var transfer: DeviceSyncTransfer?
    @State private var errorMessage: String?
    @State private var approved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") {
                    cancelAndDismiss()
                }
            }

            if let transfer {
                if deviceSyncManager.completedSessionID == transfer.sessionID {
                    completionStep
                } else if let pending = deviceSyncManager.pendingPair,
                          pending.sessionID == transfer.sessionID {
                    approvalStep(pending)
                } else {
                    qrStep(transfer)
                }
            } else {
                selectionStep
            }
        }
        .padding(24)
        .frame(width: 500, height: 640)
    }

    private var title: String {
        guard let transfer else { return "Add Android Device" }
        if deviceSyncManager.completedSessionID == transfer.sessionID {
            return "Device Paired"
        }
        if deviceSyncManager.pendingPair?.sessionID == transfer.sessionID {
            return "Approve Device"
        }
        return "Scan on Android"
    }

    private var selectionStep: some View {
        Form {
            Section("Settings") {
                Toggle("Polling interval", isOn: $syncPolling)
                Toggle("Appearance and graph display", isOn: $syncAppearance)
                Toggle("Notification thresholds", isOn: $syncNotifications)
            }

            Section("Connections") {
                connectionToggle(
                    "OpenAI / Codex session",
                    isOn: $syncOpenAI,
                    available: connectedService.isOpenAIConfigured
                )
                connectionToggle(
                    "Cursor session",
                    isOn: $syncCursor,
                    available: connectedService.isCursorConfigured
                )
                connectionToggle(
                    "ElevenLabs API key",
                    isOn: $syncElevenLabs,
                    available: connectedService.isElevenLabsConfigured
                )

                LabeledContent("Claude") {
                    Text("Sign in on phone")
                        .foregroundStyle(.secondary)
                }

                Text("Claude uses rotating OAuth credentials, so Android signs in separately instead of risking either device's session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Security") {
                Text("The QR code contains only a one-time handshake and this Mac's public key. Selected credentials are encrypted for the approved phone after the codes match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Create Pairing Code") {
                    generateTransfer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasSelection)
            }
        }
        .formStyle(.grouped)
    }

    private func qrStep(_ transfer: DeviceSyncTransfer) -> some View {
        VStack(spacing: 14) {
            Text("On your phone, open Settings → Devices → Scan QR Code. Both devices must be on the same local network.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Image(nsImage: transfer.image)
                .interpolation(.none)
                .resizable()
                .frame(width: 330, height: 330)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Secure device pairing QR code")

            ProgressView()
                .controlSize(.small)
            Text("Waiting for a phone…")
                .font(.headline)

            Text("Expires \(transfer.expiresAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Back") {
                deviceSyncManager.cancelPairing(sessionID: transfer.sessionID)
                self.transfer = nil
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func approvalStep(_ pending: PendingDevicePair) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text(pending.deviceName)
                .font(.title3.weight(.semibold))

            Text("Confirm this code is also shown on the phone:")
                .foregroundStyle(.secondary)

            Text(formattedCode(pending.confirmationCode))
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .textSelection(.enabled)

            Text("Approving encrypts the selected settings specifically for this device. Reject if the code or device name does not match.")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            if approved {
                ProgressView("Waiting for phone to finish…")
            } else {
                HStack {
                    Button("Reject", role: .destructive) {
                        deviceSyncManager.rejectPendingPair()
                        transfer = nil
                    }
                    Spacer()
                    Button("Approve Device") {
                        approved = true
                        deviceSyncManager.approvePendingPair()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: 380)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var completionStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Settings transferred securely")
                .font(.title3.weight(.semibold))
            Text("The phone is now listed in Devices. You can remove it later to stop future sync and queue a credential wipe.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func connectionToggle(
        _ title: String,
        isOn: Binding<Bool>,
        available: Bool
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack {
                Text(title)
                if !available {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!available)
    }

    private var hasSelection: Bool {
        syncPolling || syncAppearance || syncNotifications
            || syncOpenAI || syncCursor || syncElevenLabs
    }

    private var hasSelectedConnection: Bool {
        syncOpenAI || syncCursor || syncElevenLabs
    }

    private func generateTransfer() {
        do {
            let credentials = connectedService.deviceSyncCredentials()
            let payload = DeviceSyncPayload(
                general: syncPolling
                    ? DeviceSyncGeneral(pollingMinutes: service.pollingMinutes)
                    : nil,
                appearance: syncAppearance
                    ? DeviceSyncAppearance(
                        preferredProvider: UserDefaults.standard.string(
                            forKey: UsagePresentationDefaults.menuBarProviderKey
                        ) ?? UsagePresentationDefaults.menuBarProvider.rawValue,
                        menuBarStyle: UserDefaults.standard.string(
                            forKey: UsagePresentationDefaults.menuBarStyleKey
                        ) ?? UsagePresentationDefaults.menuBarStyle.rawValue,
                        primaryMetric: UserDefaults.standard.string(
                            forKey: UsagePresentationDefaults.menuBarPrimaryMetricKey
                        ) ?? UsagePresentationMetrics.claudeFiveHourID,
                        secondaryMetric: UserDefaults.standard.string(
                            forKey: UsagePresentationDefaults.menuBarSecondaryMetricKey
                        ) ?? UsagePresentationMetrics.claudeSevenDayID,
                        detailStyle: UserDefaults.standard.string(
                            forKey: UsagePresentationDefaults.detailStyleKey
                        ) ?? UsagePresentationDefaults.detailStyle.rawValue,
                        textSize: UserDefaults.standard.string(
                            forKey: UsagePresentationDefaults.textSizeKey
                        ) ?? UsagePresentationDefaults.textSize.rawValue
                    )
                    : nil,
                notifications: syncNotifications
                    ? DeviceSyncNotifications(
                        claudeSession: notificationService.claudeSessionThreshold,
                        claudeSevenDay: notificationService.claudeSevenDayThreshold,
                        claudeFable: notificationService.claudeFableThreshold,
                        openAIWeekly: notificationService.openAIWeeklyThreshold,
                        openAIResetCredits: notificationService.openAIResetCreditsThreshold,
                        cursorAPI: notificationService.cursorAPIThreshold,
                        cursorAuto: notificationService.cursorAutoThreshold,
                        cursorCredit: notificationService.cursorCreditThreshold
                    )
                    : nil,
                connections: hasSelectedConnection
                    ? DeviceSyncConnections(
                        openAISessionToken: syncOpenAI ? credentials.openAISessionToken : nil,
                        cursorSessionToken: syncCursor ? credentials.cursorSessionToken : nil,
                        elevenLabsAPIKey: syncElevenLabs ? credentials.elevenLabsAPIKey : nil
                    )
                    : nil
            )
            let pairing = try deviceSyncManager.beginPairing(payload: payload)
            transfer = DeviceSyncTransfer(
                sessionID: pairing.sessionID,
                image: try QRCodeRenderer.image(for: pairing.urlString),
                expiresAt: pairing.expiresAt
            )
            approved = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelAndDismiss() {
        if let transfer,
           deviceSyncManager.completedSessionID != transfer.sessionID {
            deviceSyncManager.cancelPairing(sessionID: transfer.sessionID)
        }
        dismiss()
    }

    private func formattedCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}

private struct DeviceSyncTransfer {
    let sessionID: String
    let image: NSImage
    let expiresAt: Date
}

private enum QRCodeRenderer {
    static func image(for value: String) throws -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else {
            throw DeviceSyncError.codeTooLarge
        }

        let scale = 12.0
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw DeviceSyncError.codeTooLarge
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
