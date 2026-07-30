import SwiftUI

/// Remaps the Nuraphone's touch-button gestures. Device reads/writes only happen
/// when the user explicitly taps, never automatically. Tap-and-hold is not
/// supported on the Nuraphone, so only single and double tap are offered.
struct ButtonRemapView: View {
    @ObservedObject var device: NuraDeviceManager
    @Environment(\.dismiss) private var dismiss

    @State private var leftSingle: NuraButtonFunction = .none
    @State private var rightSingle: NuraButtonFunction = .none
    @State private var leftDouble: NuraButtonFunction = .none
    @State private var rightDouble: NuraButtonFunction = .none
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card(accent: .orange) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label {
                                Text("Reading or changing buttons talks to the headphones. Keep the in-ear tips out of your ears the first time, just in case.")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                            Button {
                                device.refreshButtonConfig()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { applyFromDevice() }
                            } label: {
                                Label(loaded ? "Reload from headphones" : "Read current buttons",
                                      systemImage: "arrow.down.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }

                    if loaded {
                        Card("Single tap", systemImage: "hand.tap", accent: .teal) {
                            gestureRow("Left", $leftSingle)
                            Divider()
                            gestureRow("Right", $rightSingle)
                        }
                        Card("Double tap", systemImage: "hand.tap.fill", accent: .blue) {
                            gestureRow("Left", $leftDouble)
                            Divider()
                            gestureRow("Right", $rightDouble)
                        }
                    } else {
                        Card {
                            Text("Read your current mapping to start editing.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Touch buttons")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }.disabled(!loaded)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
        .onAppear { applyFromDevice() }
    }

    /// Functions offered in the picker, curated to what the Nuraphone actually
    /// supports (cross-checked against NuraLib's per-model capability map).
    /// Excluded on the Nuraphone: Immersion Up/Down (never honoured), voice
    /// assistant, spatial, and niche functions this model doesn't expose.
    private var offeredFunctions: [NuraButtonFunction] {
        [
            .none,
            .playPauseOnly,
            .playPauseAndCall,
            .previousTrack,
            .nextTrack,
            .volumeUp,
            .volumeDown,
            .toggleSocial,
            .toggleAnc,
            .togglePassthroughOnOneSide,
            .togglePassthroughOnBothSides,
            .toggleKickIt,
        ]
    }

    private func gestureRow(_ side: String, _ selection: Binding<NuraButtonFunction>) -> some View {
        HStack {
            Text(side)
                .font(.callout.weight(.medium))
                .frame(width: 56, alignment: .leading)
            Spacer()
            Picker("", selection: selection) {
                // Keep the current value selectable even if it's one we no
                // longer offer, so the menu never shows blank.
                let options = offeredFunctions.contains(selection.wrappedValue)
                    ? offeredFunctions
                    : offeredFunctions + [selection.wrappedValue]
                ForEach(options) { fn in Text(fn.label).tag(fn) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }

    private func applyFromDevice() {
        guard let c = device.state.buttons else { return }
        leftSingle = c.leftSingleTap
        rightSingle = c.rightSingleTap
        leftDouble = c.leftDoubleTap ?? .none
        rightDouble = c.rightDoubleTap ?? .none
        loaded = true
    }

    private func apply() {
        // Tap-and-hold is unsupported on the Nuraphone, so those slots stay none.
        let config = NuraButtonConfiguration(
            leftSingleTap: leftSingle,
            rightSingleTap: rightSingle,
            leftDoubleTap: leftDouble,
            rightDoubleTap: rightDouble,
            leftTapAndHold: NuraButtonFunction.none,
            rightTapAndHold: NuraButtonFunction.none
        )
        device.setButtonConfiguration(config)
        dismiss()
    }
}
