import SwiftUI

struct ContentView: View {
    
    @State private var status: FireStatus?
    let api = APIService()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                Text("🔥 EmberSensor")
                    .font(.largeTitle)
                    .bold()
                
                if let s = status {
                    
                    // MARK: - Status Card
                    VStack(spacing: 10) {
                        Image(systemName: s.fireDetected ? "flame.fill" : "checkmark.shield.fill")
                            .font(.system(size: 40))
                            .foregroundColor(s.fireDetected ? .red : .green)
                        
                        Text(s.fireDetected ? "HIGH RISK" : "SAFE")
                            .font(.title2)
                            .bold()
                            .foregroundColor(s.fireDetected ? .red : .green)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(15)
                    
                    // MARK: - Sensor Data
                    VStack(spacing: 12) {
                        dataRow(icon: "thermometer", label: "Temperature", value: "\(String(format: "%.1f", s.temperature)) °F")
                        dataRow(icon: "smoke.fill", label: "Smoke", value: "\(String(format: "%.0f", s.smoke)) ppm")
                        dataRow(icon: "flame", label: "Flame", value: "\(String(format: "%.1f", s.wind)) m/s")
                    }
                    .cardStyle()
                    
                    // MARK: - Weather Data
                    VStack(spacing: 12) {
                        dataRow(icon: "drop.fill", label: "Humidity", value: "\(s.humidity)%")

                        dataRow(icon: "wind", label: "Wind", value: "\(String(format: "%.1f", s.wind)) m/s")

                        dataRow(icon: "cloud.fill", label: "Condition", value: s.condition)

                        dataRow(icon: s.raining ? "cloud.rain.fill" : "sun.max.fill",
                                label: "Rain",
                                value: s.raining ? "Yes" : "No")
                    }
                    .cardStyle()
                    
                } else {
                    ProgressView("Loading...")
                }
                
                Button(action: loadData) {
                    Text("Refresh")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
            }
            .padding()
        }
        .onAppear {
            loadData()
        }
    }
    
    func loadData() {
        api.fetchStatus { result in
            self.status = result
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
