import SwiftUI
import MapKit

struct FireMapView: View {
    let api: APIService

    @State private var fires: [FirePoint] = []
    @State private var nifcFires: [NIFCFire] = []
    @State private var selectedFire: FirePoint?
    @State private var selectedNIFC: NIFCFire?

    // Layer toggles (matches the web map.html TOC)
    @State private var showFIRMS = true
    @State private var showHeatMap = true
    @State private var showNIFC = true
    @State private var filter25mi = true
    @State private var showWindDirection = false

    // Wind data (loaded when wind layer is on)
    @State private var windDirection: Double?
    @State private var windSpeed: Double?

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
    private let radiusMiles: Double = 25
    private let radiusMeters: Double = 25 * 1609.34

    /// Filtered FIRMS fires (applies the 25-mi filter when enabled)
    private var visibleFIRMS: [FirePoint] {
        guard showFIRMS else { return [] }
        if filter25mi {
            return fires.filter { ($0.distanceMiles ?? .infinity) <= radiusMiles }
        }
        return fires
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                // Home marker
                Annotation("Home", coordinate: homeCoordinate) {
                    Image(systemName: "house.fill")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.blue)
                        .clipShape(Circle())
                }

                // 25-mi radius ring (only when filter is on)
                if filter25mi {
                    MapCircle(center: homeCoordinate, radius: radiusMeters)
                        .foregroundStyle(.clear)
                        .stroke(.white.opacity(0.6), lineWidth: 1.5)
                }

                // Heat Map: translucent gradient circles per FIRMS point
                if showHeatMap {
                    ForEach(visibleFIRMS) { fire in
                        MapCircle(center: fire.coordinate, radius: heatRadiusMeters)
                            .foregroundStyle(heatColor(for: fire.brightness).opacity(0.35))
                            .stroke(.clear)
                    }
                }

                // FIRMS markers
                if showFIRMS {
                    ForEach(visibleFIRMS) { fire in
                        Annotation("FIRMS", coordinate: fire.coordinate) {
                            Button {
                                selectedFire = fire
                                selectedNIFC = nil
                            } label: {
                                Image(systemName: selectedFire?.id == fire.id ? "flame.fill" : "flame")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Color.orange)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.orange.opacity(0.6), lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // NIFC incidents
                if showNIFC {
                    ForEach(nifcFires) { incident in
                        Annotation(incident.name, coordinate: incident.coordinate) {
                            Button {
                                selectedNIFC = incident
                                selectedFire = nil
                            } label: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.red.opacity(0.6), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Wind direction arrow at home
                if showWindDirection, let dir = windDirection {
                    Annotation("Wind", coordinate: homeCoordinate) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.purple)
                            .rotationEffect(.degrees((dir + 180).truncatingRemainder(dividingBy: 360)))
                            .shadow(radius: 2)
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture {
                selectedFire = nil
                selectedNIFC = nil
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                scheduleRegionFetchIfNeeded()
            }
            .navigationTitle("Fire Map")
            .navigationBarTitleDisplayMode(.inline)

            // Top status bar with layer menu
            topBar

            // Detail card (FIRMS or NIFC)
            if let fire = selectedFire {
                VStack {
                    Spacer()
                    FireDetailCard(fire: fire) {
                        selectedFire = nil
                    }
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            } else if let incident = selectedNIFC {
                VStack {
                    Spacer()
                    NIFCDetailCard(incident: incident) {
                        selectedNIFC = nil
                    }
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut, value: selectedFire?.id)
        .animation(.easeInOut, value: selectedNIFC?.id)
        .onAppear {
            guard !hasLoadedInitially else { return }
            hasLoadedInitially = true
            loadAllData(forceRefresh: true)
        }
        .onChange(of: showWindDirection) { _, newValue in
            if newValue { loadWindData() }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("FIRMS: \(visibleFIRMS.count)  •  NIFC: \(nifcFires.count)")
                    .font(.subheadline)
                    .bold()

                Spacer()

                // Layers menu
                Menu {
                    Toggle("FIRMS", isOn: $showFIRMS)
                    Toggle("Heat Map", isOn: $showHeatMap)
                    Toggle("NIFC Incidents", isOn: $showNIFC)
                    Toggle("25-mi Filter", isOn: $filter25mi)
                    Toggle("Wind Direction", isOn: $showWindDirection)
                } label: {
                    Image(systemName: "square.3.layers.3d")
                        .font(.title3)
                }

                Button {
                    loadAllData(forceRefresh: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                }
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

    // MARK: - Heat map helpers

    private var heatRadiusMeters: Double {
        // Scale heat circle radius with current zoom
        let baseSpan = visibleRegion.span.latitudeDelta
        return max(800, baseSpan * 8000)
    }

    private func heatColor(for brightness: Double?) -> Color {
        let intensity = max(0, min(1, ((brightness ?? 380) - 320) / 150))
        if intensity < 0.35 { return .orange }
        if intensity < 0.65 { return .red }
        return Color(red: 1.0, green: 0.97, blue: 0.92)
    }

    // MARK: - Loading

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

    private func loadAllData(forceRefresh: Bool) {
        loadFires(forceRefresh: forceRefresh)
        loadNIFC()
        if showWindDirection { loadWindData() }
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

    private func loadNIFC() {
        api.fetchNIFCFires { result in
            DispatchQueue.main.async {
                self.nifcFires = result
            }
        }
    }

    private func loadWindData() {
        api.fetchStatus(forceRefresh: false) { status in
            DispatchQueue.main.async {
                guard let s = status else { return }
                self.windDirection = s.windDirection
                self.windSpeed = s.wind
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

// MARK: - NIFC Detail Card

struct NIFCDetailCard: View {
    let incident: NIFCFire
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(incident.name)
                    .font(.headline)
                    .bold()
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            if let d = incident.distanceMiles {
                Label("\(String(format: "%.1f", d)) mi from sensor", systemImage: "ruler")
                    .font(.subheadline)
            }
            if let acres = incident.acresBurned {
                Label("\(acres.formatted()) acres", systemImage: "flame")
                    .font(.subheadline)
            }
            if let pct = incident.percentContained {
                Label("\(pct)% contained", systemImage: "shield")
                    .font(.subheadline)
            }
            if let st = incident.state {
                Label(st, systemImage: "mappin")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
