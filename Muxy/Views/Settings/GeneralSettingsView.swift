import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(UpdateChannel.storageKey)
    private var updateChannelRaw = UpdateChannel.stable.rawValue
    @AppStorage(QuitConfirmationPreferences.confirmQuitKey)
    private var confirmQuit = true
    @State private var sentry = SentryService.shared
    @State private var analytics = AnalyticsService.shared
    @State private var updateService = UpdateService.shared

    var body: some View {
        SettingsContainer {
            SettingsSection(
                "Updates",
                footer: """
                The Beta channel ships every change merged to main and may be unstable. Switch back to Stable to \
                receive only tagged releases.
                """
            ) {
                SettingsRow("Update channel") {
                    Picker("", selection: channelBinding) {
                        ForEach(UpdateChannel.allCases) { channel in
                            Text(L10n.resource(key: channel.displayName)).tag(channel)
                        }
                    }
                    .labelsHidden()
                    .settingsControl()
                }
                SettingsToggleRow(
                    label: L10n.resource("Install Downloaded Updates on Quit"),
                    isOn: automaticUpdatesBinding
                )
                .disabled(!updateService.allowsAutomaticUpdates)
                .help(L10n.string("Automatic updates are unavailable for this configuration."))
            }

            SettingsSection("Quit", showsDivider: sentry.hasDSN || analytics.hasAPIKey) {
                SettingsToggleRow(
                    label: L10n.resource("Confirm before quitting Muxy"),
                    isOn: $confirmQuit
                )
            }

            if sentry.hasDSN || analytics.hasAPIKey {
                SettingsSection(
                    "Diagnostics",
                    footer: """
                    Anonymous crash reports and usage statistics help us fix bugs and understand which features \
                    are used. Nothing sent ever includes project paths, file contents, or personal data.
                    """,
                    showsDivider: false
                ) {
                    if sentry.hasDSN {
                        SettingsToggleRow(
                            label: L10n.resource("Send anonymous crash reports"),
                            isOn: sentryConsentBinding
                        )
                    }
                    if analytics.hasAPIKey {
                        SettingsToggleRow(
                            label: L10n.resource("Send anonymous usage statistics"),
                            isOn: analyticsConsentBinding
                        )
                    }
                }
            }
        }
    }

    private var sentryConsentBinding: Binding<Bool> {
        Binding(
            get: { sentry.consent == .allowed },
            set: { newValue in sentry.setConsent(newValue ? .allowed : .denied) }
        )
    }

    private var analyticsConsentBinding: Binding<Bool> {
        Binding(
            get: { analytics.consent == .allowed },
            set: { newValue in analytics.setConsent(newValue ? .allowed : .denied) }
        )
    }

    private var channelBinding: Binding<UpdateChannel> {
        Binding(
            get: { UpdateChannel(rawValue: updateChannelRaw) ?? .stable },
            set: { newValue in
                updateChannelRaw = newValue.rawValue
                UpdateService.shared.channel = newValue
            }
        )
    }

    private var automaticUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updateService.automaticallyDownloadsUpdates },
            set: { updateService.setAutomaticallyDownloadsUpdates($0) }
        )
    }
}
