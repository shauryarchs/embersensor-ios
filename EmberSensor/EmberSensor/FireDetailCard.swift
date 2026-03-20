import SwiftUI

struct FireDetailCard: View {
    let fire: FirePoint
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Fire Details", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundColor(.red)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            detailRow("Latitude", String(format: "%.4f", fire.latitude))
            detailRow("Longitude", String(format: "%.4f", fire.longitude))

            if let confidence = fire.confidence {
                detailRow("Confidence", confidence.uppercased())
            }

            if let brightness = fire.brightness {
                detailRow("Brightness", String(format: "%.1f", brightness))
            }

            if let satellite = fire.satellite {
                detailRow("Satellite", satellite)
            }

            if let acquiredDate = fire.acquiredDate {
                detailRow("Date", acquiredDate)
            }

            if let acquiredTime = fire.acquiredTime {
                detailRow("Time", formatAcquiredTime(acquiredTime))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(radius: 8)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .bold()
        }
    }

    private func formatAcquiredTime(_ time: String) -> String {
        guard time.count == 4 else { return time }
        let hour = String(time.prefix(2))
        let minute = String(time.suffix(2))
        return "\(hour):\(minute)"
    }
}
