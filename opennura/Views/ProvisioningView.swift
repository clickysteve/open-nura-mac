import SwiftUI

/// Sign in to a Nura account and recover the connected headphone's device key
/// via backend-assisted provisioning.
struct ProvisioningView: View {
    @ObservedObject var device: NuraDeviceManager
    @ObservedObject var provisioning: NuraProvisioningManager
    @Environment(\.dismiss) private var dismiss

    @State private var email: String = ""
    @State private var code: String = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                switch provisioning.authStep {
                case .loggedOut:
                    emailSection
                case .codeSent(let sentTo):
                    codeSection(sentTo: sentTo)
                case .loggedIn(let account):
                    recoverySection(account: account)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                statusSection
                explanationSection
            }
            .navigationTitle("Recover Device Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
        .onAppear {
            if email.isEmpty { email = provisioning.userEmail ?? "" }
        }
    }

    // MARK: - Sign in

    private var emailSection: some View {
        Section("Nura account") {
            TextField("Email address", text: $email)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
                .disableAutocorrection(true)

            Button {
                run { try await provisioning.requestEmailCode(email) }
            } label: {
                Label("Send login code", systemImage: "envelope")
            }
            .disabled(provisioning.isBusy || email.isEmpty)
        }
    }

    private func codeSection(sentTo: String) -> some View {
        Section("Enter the code") {
            Text("We sent a login code to \(sentTo).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Login code", text: $code)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif

            Button {
                run { try await provisioning.verifyEmailCode(code) }
            } label: {
                Label("Verify & sign in", systemImage: "checkmark.shield")
            }
            .disabled(provisioning.isBusy || code.isEmpty)

            Button("Use a different email") {
                provisioning.logout()
                code = ""
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Recover

    private func recoverySection(account: String) -> some View {
        Section {
            LabeledContent("Account") { Text(account) }

            Button {
                errorText = nil
                device.fetchDeviceKey()
            } label: {
                Label("Recover key from connected nuraphone", systemImage: "key.horizontal")
            }
            .disabled(provisioning.isBusy || !device.phase.isIdle)

            Button("Sign out", role: .destructive) {
                provisioning.logout()
            }
        } header: {
            Text("Signed in")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recovery talks to both the headphone and the Nura backend and can take up to a minute.")
                Label {
                    Text("Tip: the nuraphone should be **paired but not connected** for audio. If it's connected, disconnect it in Bluetooth settings first (leave it paired), then Recover.")
                } icon: {
                    Image(systemName: "lightbulb")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Status & help

    private var statusSection: some View {
        Section {
            HStack {
                StatusBadge(phase: device.phase)
                Spacer()
                if provisioning.isBusy || !device.phase.isIdle {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if !provisioning.status.isEmpty {
                Text(provisioning.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var explanationSection: some View {
        Section {
            Text("Each nuraphone has a unique device key that encrypts all control commands. This recovers that key from Nura's servers using your account, then saves it so the app can control the headphones locally, no account needed afterwards.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func run(_ operation: @escaping () async throws -> Void) {
        errorText = nil
        Task { @MainActor in
            do {
                try await operation()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
