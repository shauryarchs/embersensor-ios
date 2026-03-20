import SwiftUI
import MapKit

struct FireMapView: View {
    let api: APIService

    @State private var fires: [FirePoint] = []
    @State private var selectedFire: FirePoint?

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

    @State private var lastFetchedRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.1, longitude: -117.6),
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )

    @State private var debounceTask: DispatchWorkItem?
    @State private var isLoading = false
    @State private var hasLoadedInitially = false

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
                        Button {
                            selectedFire = fire
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: selectedFire?.id == fire.id ? "flame.fill" : "flame")
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(selectedFire?.id == fire.id ? Color.orange : Color.red)
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
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture {
                selectedFire = nil
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                scheduleRegionFetchIfNeeded()
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

            if let fire = selectedFire {
                VStack {
                    Spacer()

                    FireDetailCard(fire: fire) {
                        selectedFire = nil
                    }
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut, value: selectedFire?.id)
        .onAppear {
            guard !hasLoadedInitially else { return }
            hasLoadedInitially = true
            loadFires(forceRefresh: true)
        }
    }

    private func scheduleRegionFetchIfNeeded() {
        guard shouldFetch(for: visibleRegion, comparedTo: lastFetchedRegion) else {
            return
        }

        debounceTask?.cancel()

        let task = DispatchWorkItem {
            loadFires(forceRefresh: false)
        }

        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: task)
    }

    private func loadFires(forceRefresh: Bool) {
        debounceTask?.cancel()
        isLoading = true

        let regionToFetch = visibleRegion

        api.fetchFires(region: regionToFetch, forceRefresh: forceRefresh) { result in
            DispatchQueue.main.async {
                self.fires = result
                self.isLoading = false
                self.lastFetchedRegion = regionToFetch

                if let selected = self.selectedFire,
                   !result.contains(where: { $0.id == selected.id }) {
                    self.selectedFire = nil
                }
            }
        }
    }

    private func shouldFetch(for newRegion: MKCoordinateRegion, comparedTo oldRegion: MKCoordinateRegion) -> Bool {
        let latMove = abs(newRegion.center.latitude - oldRegion.center.latitude)
        let lonMove = abs(newRegion.center.longitude - oldRegion.center.longitude)
        let latSpanChange = abs(newRegion.span.latitudeDelta - oldRegion.span.latitudeDelta)
        let lonSpanChange = abs(newRegion.span.longitudeDelta - oldRegion.span.longitudeDelta)

        let movedEnough =
            latMove > oldRegion.span.latitudeDelta * 0.20 ||
            lonMove > oldRegion.span.longitudeDelta * 0.20

        let zoomChangedEnough =
            latSpanChange > oldRegion.span.latitudeDelta * 0.20 ||
            lonSpanChange > oldRegion.span.longitudeDelta * 0.20

        return movedEnough || zoomChangedEnough
    }
}
