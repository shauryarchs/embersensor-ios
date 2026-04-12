import SwiftUI
import Combine
import UserNotifications

struct ContentView: View {
    @State private var status: FireStatus?
    @State private var isLoadingStatus = false
    @State private var lastRiskLevel: String = "LOW RISK"
    @State private var showEmergencyAlert = false
    @State private var showBreakdown = false
    @State private var selectedTab = 0

    let api = APIService()
    let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $selectedTab) {
            dashboardTab
                .tabItem {
                    Label("Status", systemImage: "flame.fill")
                }
                .tag(0)

            NavigationStack {
                FireMapView(api: api)
            }
            .tabItem {
                Label("Map", systemImage: "map.fill")
            }
            .tag(1)

            NavigationStack {
                FireGraphView()
                    .navigationTitle("Wildfire Analysis")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Analysis", systemImage: "chart.dots.scatter")
            }
            .tag(2)

            NavigationStack {
                LiveFeedView()
                    .navigationTitle("Live Feed")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Live Feed", systemImage: "video.fill")
            }
            .tag(3)
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 0 {
                loadData()
            }
        }
    }

    private var dashboardTab: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 4) {
                        Text("Live Monitoring")
                            .font(.caption)
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundColor(.orange)
                        Text("Live Fire Risk")
                            .font(.title)
                            .bold()
                        Text("Real-time sensor, weather, and wildfire data.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 4)

                    if let s = status {
                        let risk = getRiskLevel(from: s.riskIndex)

                        // Risk Card
                        VStack(spacing: 8) {
                            Text("🔥")
                                .font(.system(size: 40))
                            Text(risk.label)
                                .font(.title2)
                                .bold()
                                .foregroundColor(risk.color)
                            Text("Risk Index: \(s.riskIndex) / 10")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(risk.color.opacity(0.1))
                        .cornerRadius(15)

                        // Score Breakdown
                        if let bd = s.scoreBreakdown {
                            breakdownSection(s: s, bd: bd)
                        }

                        // Temperature
                        sectionCard(title: nil) {
                            dataRow(icon: "sun.max.fill",
                                    label: "Weather Temp",
                                    value: fmt(s.weatherTemperature, "°F"))
                            if let sensorTemp = s.sensorTemperature {
                                dataRow(icon: "thermometer",
                                        label: "Sensor Temp",
                                        value: fmt(sensorTemp, "°F"))
                                dataRow(icon: "thermometer.variable",
                                        label: "Temp Delta",
                                        value: fmtDelta(sensorTemp - s.weatherTemperature, "°F"))
                            }
                        }

                        // Sensors
                        if s.smoke != nil || s.flame != nil {
                            sectionCard(title: nil) {
                                if let smoke = s.smoke {
                                    dataRow(icon: "smoke.fill",
                                            label: "Smoke",
                                            value: "\(String(format: "%.0f", smoke)) ppm")
                                }
                                if let flame = s.flame {
                                    flameRow(flame: flame)
                                }
                            }
                        }

                        // Weather
                        sectionCard(title: nil) {
                            dataRow(icon: "drop.fill",
                                    label: "Humidity",
                                    value: "\(String(format: "%.0f", s.humidity))%")
                            dataRow(icon: "wind",
                                    label: "Wind Speed",
                                    value: "\(String(format: "%.1f", s.wind)) m/s")
                            dataRow(icon: "safari",
                                    label: "Wind Direction",
                                    value: "\(String(format: "%.0f", s.windDirection))°")
                            dataRow(icon: "cloud.fill",
                                    label: "Condition",
                                    value: s.condition)
                            boolRow(icon: s.raining ? "cloud.rain.fill" : "sun.max.fill",
                                    label: "Rain",
                                    value: s.raining)
                        }

                        // FIRMS Satellite Detections
                        sectionCard(title: "🛰 FIRMS Satellite Detections") {
                            boolRow(icon: "flame.fill",
                                    label: "Fire Nearby",
                                    value: s.fireNearby)
                            dataRow(icon: "mappin.circle.fill",
                                    label: "Closest Detection",
                                    value: closestFireText(s.closestFireDistanceMiles))
                            boolRow(icon: "wind",
                                    label: "Wind Toward Home",
                                    value: s.windTowardsHome)
                            dataRow(icon: "map.fill",
                                    label: "Nearby Detection Count",
                                    value: "\(s.nearbyCount)")
                        }

                        // CAL FIRE Incidents
                        sectionCard(title: "🚒 CAL FIRE Reported Incidents") {
                            boolRow(icon: "flame.fill",
                                    label: "Incident Nearby",
                                    value: s.calfireNearby ?? false)
                            dataRow(icon: "map.fill",
                                    label: "Nearby Incident Count",
                                    value: "\(s.calfireCount ?? 0)")
                        }

                        // CAL FIRE incident list
                        if let fires = s.calfireFires, !fires.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(fires, id: \.name) { f in
                                    calFireRow(f)
                                }
                            }
                            .cardStyle()
                        }

                        // Generated at
                        if let ts = s.generatedAt {
                            Text("Updated \(formatTimestamp(ts))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                    } else if isLoadingStatus {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.orange)
                            Text("Loading live data...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
                    } else {
                        Text("Unable to load live data. Please try again.")
                            .foregroundColor(.red)
                            .padding(.top, 40)
                    }

                    // Refresh button
                    Button(action: refreshLiveData) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .padding()
            }

            if showEmergencyAlert {
                EmergencyAlertView(showAlert: $showEmergencyAlert)
            }
        }
        .onAppear {
            loadData()
            requestNotificationPermission()
        }
        .onReceive(timer) { _ in
            loadData()
        }
    }

    // MARK: - Score Breakdown

    private func breakdownSection(s: FireStatus, bd: ScoreBreakdown) -> some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation { showBreakdown.toggle() } }) {
                HStack {
                    Text("Score Breakdown")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: showBreakdown ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }

            if showBreakdown {
                VStack(spacing: 12) {
                    scoreRow(emoji: "🌡️", title: "Sensor Score",
                             score: "\(bd.sensorScore) / 4",
                             factors: sensorFactors(s: s))
                    Divider()
                    scoreRow(emoji: "🔥", title: "Fire Score",
                             score: "\(bd.fireScore) / 4",
                             factors: fireFactors(s: s))
                    Divider()
                    scoreRow(emoji: "☀️", title: "Weather Score",
                             score: "\(bd.weatherScore) (range: -2 to 3)",
                             factors: weatherFactors(s: s))
                    Divider()
                    scoreRow(emoji: "💨", title: "Wind Score",
                             score: "\(bd.windScore) / 2",
                             factors: windFactors(s: s))
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            }
        }
    }

    private func scoreRow(emoji: String, title: String, score: String, factors: [(String, String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(emoji) \(title)")
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text(score)
                    .font(.caption)
                    .bold()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
            }
            ForEach(factors, id: \.0) { factor in
                HStack {
                    Text(factor.0)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(factor.1)
                        .font(.caption)
                        .bold()
                        .foregroundColor(factor.2)
                }
            }
        }
    }

    private func sensorFactors(s: FireStatus) -> [(String, String, Color)] {
        let flame = s.flame ?? 1
        let flamePts = flame == 0 ? "+8" : "0"
        let flameColor: Color = flame == 0 ? .red : .secondary

        let smoke = s.smoke ?? 0
        let smokePts: String
        let smokeColor: Color
        if smoke > 600 { smokePts = "+8"; smokeColor = .red }
        else if smoke > 500 { smokePts = "+3"; smokeColor = .red }
        else if smoke >= 400 { smokePts = "+2"; smokeColor = .orange }
        else if smoke >= 300 { smokePts = "+1"; smokeColor = .orange }
        else { smokePts = "0"; smokeColor = .secondary }

        let sensorTemp = s.sensorTemperature ?? s.weatherTemperature
        let tempPts: String
        let tempColor: Color
        if sensorTemp > 120 { tempPts = "+8"; tempColor = .red }
        else if sensorTemp > 90 { tempPts = "+2"; tempColor = .orange }
        else { tempPts = "0"; tempColor = .secondary }

        let delta = sensorTemp - s.weatherTemperature
        let deltaPts: String
        let deltaColor: Color
        if delta > 30 { deltaPts = "+2"; deltaColor = .red }
        else if delta >= 15 { deltaPts = "+1"; deltaColor = .orange }
        else { deltaPts = "0"; deltaColor = .secondary }

        return [
            ("Flame detected", flamePts, flameColor),
            ("Smoke (\(String(format: "%.0f", smoke)) ppm)", smokePts, smokeColor),
            ("Sensor temp (\(String(format: "%.0f", sensorTemp))°F)", tempPts, tempColor),
            ("Temp delta (\(String(format: "%.0f", delta))°F)", deltaPts, deltaColor)
        ]
    }

    private func fireFactors(s: FireStatus) -> [(String, String, Color)] {
        let calCount = s.calfireCount ?? 0
        let calPts: String
        let calColor: Color
        if calCount >= 2 { calPts = "+3"; calColor = .red }
        else if calCount == 1 { calPts = "+2"; calColor = .orange }
        else { calPts = "0"; calColor = .secondary }

        let firmsPts: String
        let firmsColor: Color
        if s.nearbyCount > 5 { firmsPts = "+1"; firmsColor = .orange }
        else { firmsPts = "0"; firmsColor = .secondary }

        let proxPts: String
        let proxColor: Color
        if s.nearbyCount > 0, let dist = s.closestFireDistanceMiles, dist < 5 {
            proxPts = "+1"; proxColor = .orange
        } else {
            proxPts = "0"; proxColor = .secondary
        }

        return [
            ("CAL FIRE incidents (\(calCount))", calPts, calColor),
            ("FIRMS detections (\(s.nearbyCount))", firmsPts, firmsColor),
            ("Closest fire proximity", proxPts, proxColor)
        ]
    }

    private func weatherFactors(s: FireStatus) -> [(String, String, Color)] {
        let humPts: String
        let humColor: Color
        if s.humidity < 20 { humPts = "+2"; humColor = .red }
        else if s.humidity <= 30 { humPts = "+1"; humColor = .orange }
        else if s.humidity > 50 { humPts = "-2"; humColor = .green }
        else if s.humidity > 40 { humPts = "-1"; humColor = .green }
        else { humPts = "0"; humColor = .secondary }

        let windPts: String
        let windColor: Color
        let fireScore = s.scoreBreakdown?.fireScore ?? 0
        if fireScore == 0 {
            windPts = "(ignored — no fires)"; windColor = .secondary
        } else if s.wind > 8 {
            windPts = "+2"; windColor = .red
        } else if s.wind >= 5 {
            windPts = "+1"; windColor = .orange
        } else {
            windPts = "0"; windColor = .secondary
        }

        let tempPts: String
        let tempColor: Color
        if s.weatherTemperature > 95 { tempPts = "+1"; tempColor = .orange }
        else { tempPts = "0"; tempColor = .secondary }

        let rainPts: String
        let rainColor: Color
        if s.raining { rainPts = "-10"; rainColor = .green }
        else { rainPts = "0"; rainColor = .secondary }

        return [
            ("Humidity (\(String(format: "%.0f", s.humidity))%)", humPts, humColor),
            ("Wind speed (\(String(format: "%.1f", s.wind)) m/s)", windPts, windColor),
            ("Temperature (\(String(format: "%.0f", s.weatherTemperature))°F)", tempPts, tempColor),
            ("Rain", rainPts, rainColor)
        ]
    }

    private func windFactors(s: FireStatus) -> [(String, String, Color)] {
        let fireScore = s.scoreBreakdown?.fireScore ?? 0
        let pts: String
        let color: Color
        if fireScore == 0 {
            pts = "(ignored — fire score is 0)"; color = .secondary
        } else if s.windTowardsHome {
            pts = "+2"; color = .red
        } else {
            pts = "0"; color = .secondary
        }
        return [("Wind threat toward home", pts, color)]
    }

    // MARK: - Section Card

    private func sectionCard<Content: View>(title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            if let title = title {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .bold()
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            content()
        }
        .cardStyle()
    }

    // MARK: - Row Helpers

    private func flameRow(flame: Int) -> some View {
        HStack {
            Image(systemName: "flame")
                .frame(width: 25)
            Text("Flame Sensor")
            Spacer()
            Text(flame == 0 ? "Flame Detected" : "No Flame")
                .bold()
                .foregroundColor(flame == 0 ? .red : .green)
        }
    }

    private func boolRow(icon: String, label: String, value: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 25)
            Text(label)
            Spacer()
            Text(value ? "Yes" : "No")
                .bold()
                .foregroundColor(value ? .red : .green)
        }
    }

    private func calFireRow(_ f: CalFireIncident) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(f.name)
                .font(.subheadline)
                .bold()
            HStack(spacing: 8) {
                if let d = f.distanceMiles {
                    Text("\(String(format: "%.1f", d)) mi")
                }
                if let a = f.acresBurned {
                    Text("\(a) acres")
                }
                if let p = f.percentContained {
                    Text("\(p)% contained")
                }
                if let st = f.state {
                    Text(st)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Formatters

    private func fmt(_ val: Double, _ unit: String) -> String {
        "\(String(format: "%.1f", val)) \(unit)"
    }

    private func fmtDelta(_ val: Double, _ unit: String) -> String {
        let sign = val >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", val)) \(unit)"
    }

    private func formatTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let df = DateFormatter()
            df.dateFormat = "h:mm:ss a"
            return df.string(from: date)
        }
        return iso
    }

    func loadData() {
        isLoadingStatus = (status == nil)

        api.fetchStatus(forceRefresh: false) { result in
            DispatchQueue.main.async {
                self.isLoadingStatus = false

                guard let s = result else {
                    print("Status fetch returned nil - keeping previous data")
                    return
                }

                self.status = s

                let risk = getRiskLevel(from: s.riskIndex).label

                if risk == "HIGH RISK" && lastRiskLevel != "HIGH RISK" {
                    triggerHighRiskAlert()
                    showEmergencyAlert = true
                }

                lastRiskLevel = risk
            }
        }
    }

    func refreshLiveData() {
        isLoadingStatus = (status == nil)

        api.fetchStatus(forceRefresh: true) { result in
            DispatchQueue.main.async {
                self.isLoadingStatus = false

                guard let s = result else {
                    print("Forced refresh failed - keeping previous data")
                    return
                }

                self.status = s

                let risk = getRiskLevel(from: s.riskIndex).label

                if risk == "HIGH RISK" && lastRiskLevel != "HIGH RISK" {
                    triggerHighRiskAlert()
                    showEmergencyAlert = true
                }

                lastRiskLevel = risk
            }
        }
    }

    func getRiskLevel(from riskIndex: Int) -> (label: String, color: Color) {
        if riskIndex >= 8 {
            return ("HIGH RISK", .red)
        } else if riskIndex >= 5 {
            return ("MEDIUM RISK", .orange)
        } else {
            return ("LOW RISK", .green)
        }
    }

    func closestFireText(_ miles: Double?) -> String {
        guard let miles = miles else { return "N/A" }
        return "\(String(format: "%.1f", miles)) miles"
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error:", error)
            } else {
                print("Notification permission granted:", granted)
            }
        }
    }

    func triggerHighRiskAlert() {
        let content = UNMutableNotificationContent()
        content.title = "🔥 HIGH FIRE RISK"
        content.body = "EmberSensor detected dangerous conditions. Sprinklers may activate."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification:", error)
            } else {
                print("Notification scheduled successfully")
            }
        }
    }
}

struct EmergencyAlertView: View {
    @Binding var showAlert: Bool
    @State private var isFlashing = false

    var body: some View {
        ZStack {
            Color.red
                .opacity(isFlashing ? 1 : 0.6)
                .ignoresSafeArea()
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                        isFlashing.toggle()
                    }
                }

            VStack(spacing: 30) {
                Text("🔥")
                    .font(.system(size: 80))

                Text("HIGH FIRE RISK")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)

                Text("Immediate action required.\nSprinklers may activate.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)

                Button(action: {
                    showAlert = false
                }) {
                    Text("DISMISS")
                        .bold()
                        .padding()
                        .frame(maxWidth: 200)
                        .background(Color.white)
                        .foregroundColor(.red)
                        .cornerRadius(12)
                }
            }
        }
    }
}

func dataRow(icon: String, label: String, value: String) -> some View {
    HStack {
        Image(systemName: icon)
            .frame(width: 25)

        Text(label)

        Spacer()

        Text(value)
            .bold()
    }
}

extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(15)
    }
}
