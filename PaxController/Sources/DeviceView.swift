import SwiftUI

private enum TemperatureUnit: String {
    case celsius
    case fahrenheit

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    func convert(celsius: Double) -> Double {
        switch self {
        case .celsius: return celsius
        case .fahrenheit: return (celsius * 9 / 5) + 32
        }
    }
}

struct DeviceView: View {
    @EnvironmentObject var viewModel: PaxDeviceViewModel
    @AppStorage("temperatureUnit") private var temperatureUnitRawValue = TemperatureUnit.celsius.rawValue

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRawValue) ?? .celsius
    }

    var body: some View {
        NavigationView {
            Group {
                if viewModel.connectionState.isConnected {
                    connectedContent
                } else {
                    notConnectedPlaceholder
                }
            }
            .navigationTitle("Controller")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        temperatureUnitRawValue = temperatureUnit == .celsius
                            ? TemperatureUnit.fahrenheit.rawValue
                            : TemperatureUnit.celsius.rawValue
                    } label: {
                        Text(temperatureUnit.symbol)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Temperature unit")
                    .accessibilityValue(temperatureUnit == .celsius ? "Celsius" : "Fahrenheit")
                    .accessibilityHint("Switches between Celsius and Fahrenheit")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.connectionState.isConnected {
                        Button {
                            viewModel.requestFullStatus()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Connected UI

    private var connectedContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                temperatureCard
                setTempCard
                dynamicModeCard
                deviceInfoCard
            }
            .padding()
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        CardView(title: "Status") {
            VStack(spacing: 12) {
                paxServiceBadge
                HStack(spacing: 24) {
                    batteryView
                    Divider().frame(height: 44)
                    heatingStateView
                    Divider().frame(height: 44)
                    lockView
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
        }
    }

    private var paxServiceBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.paxServiceConfirmed ? "checkmark.shield.fill" : "exclamationmark.shield")
                .foregroundColor(viewModel.paxServiceConfirmed ? .green : .orange)
            Text(viewModel.paxServiceConfirmed
                 ? "PAX service confirmed (read + write + notify)"
                 : "Waiting for PAX service verification…")
                .font(.caption)
                .foregroundColor(viewModel.paxServiceConfirmed ? .secondary : .orange)
            Spacer()
            if viewModel.paxServiceConfirmed {
                HStack(spacing: 4) {
                    charDot(found: viewModel.paxCharReadFound,   label: "R")
                    charDot(found: viewModel.paxCharWriteFound,  label: "W")
                    charDot(found: viewModel.paxCharNotifyFound, notifying: viewModel.paxCharNotifying, label: "N")
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func charDot(found: Bool, notifying: Bool = false, label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .frame(width: 18, height: 18)
            .background(found ? (notifying ? Color.green : Color.blue) : Color.gray)
            .clipShape(Circle())
    }

    private var batteryView: some View {
        VStack(spacing: 4) {
            Image(systemName: batteryIcon)
                .font(.title2)
                .foregroundColor(batteryColor)
            if let batt = viewModel.batteryLevel {
                HStack(spacing: 2) {
                    Text("\(batt)%")
                        .font(.headline)
                    if viewModel.isCharging == true {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
            } else {
                Text("--")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            Text("Battery")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var heatingStateView: some View {
        VStack(spacing: 4) {
            Image(systemName: heatingIcon)
                .font(.title2)
                .foregroundColor(heatingColor)
            if let state = viewModel.heatingState {
                Text(state.description)
                    .font(.headline)
            } else {
                Text("--")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            Text("State")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var lockView: some View {
        VStack(spacing: 4) {
            Image(systemName: (viewModel.isLocked == true) ? "lock.fill" : "lock.open.fill")
                .font(.title2)
                .foregroundColor((viewModel.isLocked == true) ? .orange : .secondary)
            Text((viewModel.isLocked == true) ? "Locked" : "Unlocked")
                .font(.headline)
                .foregroundColor((viewModel.isLocked == true) ? .orange : .primary)
            Text("Lock")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Temperature Card

    private var temperatureCard: some View {
        CardView(title: "Temperature") {
            HStack(spacing: 24) {
                tempDisplay(label: "Current", value: viewModel.actualTempC)
                Divider().frame(height: 44)
                tempDisplay(label: "Target", value: viewModel.targetTempC)
                Divider().frame(height: 44)
                tempDisplay(label: "PID Target", value: viewModel.currentTargetTempC)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private func tempDisplay(label: String, value: Double?) -> some View {
        VStack(spacing: 4) {
            if let t = value {
                Text(formattedTemperature(t, decimals: 1))
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundColor(tempColor(t))
            } else {
                Text("--")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Set Temperature Card

    private var setTempCard: some View {
        CardView(title: "Set Temperature") {
            VStack(spacing: 14) {
                if !viewModel.paxServiceConfirmed {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text("PAX service not yet verified — commands blocked")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Slider row
                HStack(spacing: 12) {
                    Text(formattedTemperature(180, decimals: 0))
                        .font(.caption2).foregroundColor(.secondary)
                    Slider(value: $viewModel.customTargetTempC, in: 180...215, step: 1)
                        .accentColor(.orange)
                        .disabled(!viewModel.paxServiceConfirmed)
                    Text(formattedTemperature(215, decimals: 0))
                        .font(.caption2).foregroundColor(.secondary)
                }

                // Current slider value + device target
                HStack {
                    Text(formattedTemperature(viewModel.customTargetTempC, decimals: 0))
                        .font(.title2.monospacedDigit())
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                    Spacer()
                    if let t = viewModel.targetTempC {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(formattedTemperature(t, decimals: 1))
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.secondary)
                            Text("on device")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Button {
                        viewModel.setCustomTemperature(viewModel.customTargetTempC)
                    } label: {
                        Label("Set", systemImage: "thermometer.sun")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(viewModel.paxServiceConfirmed ? Color.orange : Color(.quaternarySystemFill))
                            .foregroundColor(viewModel.paxServiceConfirmed ? .white : .secondary)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.paxServiceConfirmed)
                }

                // Quick preset buttons
                HStack(spacing: 8) {
                    ForEach(PaxPresetTemp.allCases) { preset in
                        Button {
                            viewModel.setTemperature(preset)
                        } label: {
                            Text(formattedTemperature(Double(preset.rawValue), decimals: 0))
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(viewModel.selectedPreset == preset ? Color.orange : Color(.tertiarySystemBackground))
                                .foregroundColor(viewModel.selectedPreset == preset ? .white : .primary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.paxServiceConfirmed)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Dynamic Mode Card

    private var dynamicModeCard: some View {
        CardView(title: "Heating Mode") {
            VStack(spacing: 12) {
                if !viewModel.paxServiceConfirmed {
                    Text("Unavailable until PAX service is verified")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach(PaxDynamicMode.allCases) { mode in
                            DynamicModeButton(
                                mode: mode,
                                isActive: viewModel.dynamicMode == mode
                            ) {
                                viewModel.setDynamicMode(mode)
                            }
                        }
                    }
                    if let m = viewModel.dynamicMode {
                        Text(modeDescription(m))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private func modeDescription(_ mode: PaxDynamicMode) -> String {
        switch mode {
        case .standard:   return "Balanced heating — default experience."
        case .boost:      return "Faster heat-up, higher oven temp."
        case .efficiency: return "Slower, cooler heating — conserves material."
        case .stealth:    return "Reduced vapour production and LED brightness."
        case .flavor:     return "PAX Flavor dynamic heating profile."
        }
    }

    // MARK: - Device Info Card

    private var deviceInfoCard: some View {
        CardView(title: "Device Info") {
            VStack(spacing: 8) {
                infoRow("Name", viewModel.displayName)
                infoRow("Serial", viewModel.serialNumber)
                infoRow("Model", viewModel.modelNumber)
                infoRow("Firmware", viewModel.firmwareRevision)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value ?? "—")
                .fontWeight(.medium)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Not Connected

    private var notConnectedPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Not Connected")
                .font(.title2.bold())
            Text("Go to the Scan tab to connect to a device.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Computed helpers

    private var batteryIcon: String {
        guard let b = viewModel.batteryLevel else { return "battery.0" }
        switch b {
        case 76...:   return "battery.100"
        case 51..<76: return "battery.75"
        case 26..<51: return "battery.50"
        case 11..<26: return "battery.25"
        default:      return "battery.0"
        }
    }

    private var batteryColor: Color {
        guard let b = viewModel.batteryLevel else { return .secondary }
        if b > 30 { return .green }
        if b > 15 { return .yellow }
        return .red
    }

    private var heatingIcon: String {
        switch viewModel.heatingState {
        case .heating, .boostMode: return "flame.fill"
        case .ready:               return "checkmark.circle.fill"
        case .cooling:             return "wind"
        case .standby:             return "pause.circle"
        case .off, .none:          return "circle"
        }
    }

    private var heatingColor: Color {
        switch viewModel.heatingState {
        case .heating, .boostMode: return .orange
        case .ready:               return .green
        case .cooling:             return .blue
        case .standby, .off, .none: return .secondary
        }
    }

    private func tempColor(_ t: Double) -> Color {
        if t >= 210 { return .red }
        if t >= 180 { return .orange }
        return .primary
    }

    private func formattedTemperature(_ celsius: Double, decimals: Int) -> String {
        let converted = temperatureUnit.convert(celsius: celsius)
        return String(format: "%.\(decimals)f%@", converted, temperatureUnit.symbol)
    }
}

// MARK: - Reusable Card

struct CardView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

// MARK: - Temp Preset Button

struct TempPresetButton: View {
    let preset: PaxPresetTemp
    let isActive: Bool
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(preset.label)
                    .font(.title3.monospacedDigit())
                    .fontWeight(isActive ? .bold : .regular)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(disabled ? Color(.quaternarySystemFill)
                        : isActive ? Color.orange : Color(.tertiarySystemBackground))
            .foregroundColor(disabled ? .secondary : isActive ? .white : .primary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive && !disabled ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Dynamic Mode Button

struct DynamicModeButton: View {
    let mode: PaxDynamicMode
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18))
                Text(mode.label)
                    .font(.system(size: 10, weight: isActive ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isActive ? Color.orange : Color(.tertiarySystemBackground))
            .foregroundColor(isActive ? .white : .primary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
