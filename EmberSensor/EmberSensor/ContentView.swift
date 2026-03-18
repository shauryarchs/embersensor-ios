import SwiftUI
import Combine

struct ContentView: View {
    
    @State private var status: FireStatus?
    
    let api = APIService()
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                Text("🔥 EmberSensor")
                    .font(.largeTitle)
                    .bold()
                
                if let s = status {
                    
                    // MARK: - Risk Level Card
                    let risk = getRiskLevel(s)
                    
                    VStack(spacing: 10) {
                        Image(systemName: risk.label == "HIGH RISK" ? "flame.fill" : "shield.fill")
                            .font(.system(size: 40))
                            .foregroundColor(risk.color)
                        
                        Text(risk.label)
                            .font(.title2)
                            .bold()
                            .foregroundColor(risk.color)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(risk.color.opacity(0.1))
                    .cornerRadius(15)
                    
                    // MARK: - Sensor Data Card
                    VStack(spacing: 12) {
                        dataRow(icon: "thermometer", label: "Temperature",
                                value: "\(String(format: "%.1f", s.temperature)) °F")
                        
                        dataRow(icon: "smoke.fill", label: "Smoke",
                                value: "\(String(format: "%.0f", s.smoke)) ppm")
                        
                        dataRow(icon: "flame", label: "Flame",
                                value: "\(s.flame)")
                    }
                    .cardStyle()
                    
                    // MARK: - Weather Data Card
                    VStack(spacing: 12) {
                        dataRow(icon: "drop.fill", label: "Humidity",
                                value: "\(s.humidity)%")
                        
                        dataRow(icon: "wind", label: "Wind",
                                value: "\(String(format: "%.1f", s.wind)) m/s")
                        
                        dataRow(icon: "cloud.fill", label: "Condition",
                                value: s.condition)
                        
                        dataRow(icon: s.raining ? "cloud.rain.fill" : "sun.max.fill",
                                label: "Rain",
                                value: s.raining ? "Yes" : "No")
                    }
                    .cardStyle()
                    
                } else {
                    ProgressView("Loading...")
                }
                
                // MARK: - Buttons
                
                Button(action: loadData) {
                    Text("Refresh")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button(action: openGoogleHome) {
                    HStack {
                        Image(systemName: "video.fill")
                        Text("Live Video Feed")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
            }
            .padding()
        }
        .onAppear {
            loadData()
        }
        .onReceive(timer) { _ in
            loadData()
        }
    }
    
    // MARK: - API
    
    func loadData() {
        api.fetchStatus { result in
            self.status = result
        }
    }
    
    // MARK: - Google Home
    
    func openGoogleHome() {
        if let url = URL(string: "https://home.google.com") {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Risk Logic
    
    func getRiskLevel(_ s: FireStatus) -> (label: String, color: Color) {
        
        var score = 0
        
        if s.fireDetected { score += 3 }
        if s.smoke > 300 { score += 1 }
        if s.temperature > 90 { score += 1 }
        if s.humidity < 25 { score += 1 }
        if s.wind > 5 { score += 1 }
        
        if score >= 4 {
            return ("HIGH RISK", .red)
        } else if score >= 2 {
            return ("MEDIUM RISK", .yellow)
        } else {
            return ("LOW RISK", .green)
        }
    }
}

// MARK: - Reusable Row

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

// MARK: - Card Style

extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(15)
    }
}
