import SwiftUI
import MapKit

struct FireMapView: View {
    let api: APIService

    @State private var fires: [FirePoint] = []
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.1, longitude: -117.6),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
    )

    @State private var visibleRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.1, longitude: -117.6),
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )

    @State private var isLoading = false

    private let homeCoordinate = CLLocationCoordinate2D(latitude: 34.1, longitude: -117.6)

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                Annotation("Home", coordinate: homeCoordinate) {
                    VStack(spacing: 4) {
                        Image(systemName: "house.fill")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.blue)
                            .clipShape(Circle())

                        Text("Home")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                ForEach(fires) { fire in
                    Annotation("Fire", coordinate: fire.coordinate) {
                        VStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(Color.red)
                                .clipShape(Circle())

                            if let confidence = fire.confidence {
                                Text(confidence.uppercased())
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(0.9))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                loadFires(forceRefresh: false)
            }
            .navigationTitle("Fire Map")
            .navigationBarTitleDisplayMode(.inline)

            VStack(spacing: 8) {
                HStack {
                    Text("Nearby Fires: \(fires.count)")
                        .font(.subheadline)
                        .bold()

                    Spacer()

                    Button("Refresh") {
                        loadFires(forceRefresh: true)
                    }
                    .font(.subheadline)
                    .bold()
                }

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding()
        }
        .onAppear {
            loadFires(forceRefresh: true)
        }
    }

    private func loadFires(forceRefresh: Bool) {
        isLoading = true

        api.fetchFires(region: visibleRegion, forceRefresh: forceRefresh) { result in
            DispatchQueue.main.async {
                self.fires = result
                self.isLoading = false
            }
        }
    }
}
