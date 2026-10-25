//
//  MapScreen.swift
//  DementiaCareHackathon
//
//  Map showing the home safe zone as a circle and the patient's location as a pin.
//

import SwiftUI
import MapKit

struct MapScreen: View {
    let home: CLLocationCoordinate2D?
    let radiusMiles: Double
    let patient: CLLocationCoordinate2D?
    let isOutside: Bool
    let distanceMeters: Double?
    let lastUpdate: Date?
    /// Shown in the status card while there is no patient location yet.
    let waitingMessage: String?
    let batteryPercent: Int?
    let batteryCharging: Bool
    let lowBatteryThreshold: Int
    /// Minutes outside the safe zone, shown on the caretaker's map.
    var minutesOutside: Double? = nil

    @State private var recenterToken = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ZoneMapView(
                home: home,
                radiusMeters: radiusMiles * Distance.metersPerMile,
                patient: patient,
                isOutside: isOutside,
                recenterToken: recenterToken
            )
            .ignoresSafeArea(edges: .top)

            statusCard
                .padding()
        }
        .overlay(alignment: .topTrailing) {
            Button {
                recenterToken += 1
            } label: {
                Image(systemName: "location.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(.regularMaterial)
                    .clipShape(Circle())
            }
            .padding()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            batteryLine

            if patient == nil {
                Label("Location not available yet", systemImage: "location.slash")
                    .font(.title2.bold())
                if let waitingMessage = waitingMessage {
                    Text(waitingMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            } else {
                Label(
                    isOutside ? "Outside the safe zone" : "Inside the safe zone",
                    systemImage: isOutside ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
                )
                .font(.title2.bold())
                .foregroundColor(isOutside ? .red : .green)

                if let distanceMeters = distanceMeters {
                    Text("\(Distance.milesText(meters: distanceMeters)) from home")
                        .font(.title3)
                }
                if isOutside, let minutesOutside = minutesOutside {
                    Text("Outside for \(Int(minutesOutside)) minutes")
                        .font(.title3.bold())
                        .foregroundColor(.red)
                }
                if let lastUpdate = lastUpdate {
                    Text("Updated \(lastUpdate.formatted(date: .omitted, time: .shortened))")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .cornerRadius(16)
    }

    @ViewBuilder
    private var batteryLine: some View {
        if let percent = batteryPercent {
            let isLow = percent <= lowBatteryThreshold && !batteryCharging
            Label(
                "Battery \(Battery.text(percent: percent, charging: batteryCharging))",
                systemImage: Battery.iconName(percent: percent, charging: batteryCharging)
            )
            .font(.title3.bold())
            .foregroundColor(isLow ? .red : .primary)
        } else {
            Label("Battery unknown", systemImage: "battery.0")
                .font(.title3)
                .foregroundColor(.secondary)
        }
    }
}

final class ZoneAnnotation: MKPointAnnotation {
    enum Kind {
        case home
        case patient
    }

    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
        super.init()
    }
}

struct ZoneMapView: UIViewRepresentable {
    var home: CLLocationCoordinate2D?
    var radiusMeters: CLLocationDistance
    var patient: CLLocationCoordinate2D?
    var isOutside: Bool
    var recenterToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        let dataKey = [
            home.map { "\($0.latitude),\($0.longitude)" } ?? "-",
            "\(radiusMeters)",
            patient.map { "\($0.latitude),\($0.longitude)" } ?? "-",
            "\(isOutside)"
        ].joined(separator: "|")

        // Rebuild the circle and pins only when the data changed.
        if dataKey != coordinator.lastDataKey {
            coordinator.lastDataKey = dataKey
            coordinator.isOutside = isOutside
            mapView.removeOverlays(mapView.overlays)
            mapView.removeAnnotations(mapView.annotations)

            if let home = home {
                mapView.addOverlay(MKCircle(center: home, radius: radiusMeters))
                let annotation = ZoneAnnotation(kind: .home)
                annotation.coordinate = home
                annotation.title = "Home"
                mapView.addAnnotation(annotation)
            }
            if let patient = patient {
                let annotation = ZoneAnnotation(kind: .patient)
                annotation.coordinate = patient
                annotation.title = "Patient"
                mapView.addAnnotation(annotation)
            }
        }

        // Fit the circle and the patient on screen when the data changes or the recenter button is tapped.
        let fitKey = "\(dataKey)|\(recenterToken)"
        if fitKey != coordinator.lastFitKey {
            coordinator.lastFitKey = fitKey
            fit(mapView, animated: coordinator.hasFitOnce)
            coordinator.hasFitOnce = true
        }
    }

    private func fit(_ mapView: MKMapView, animated: Bool) {
        var rect = MKMapRect.null
        if let home = home {
            rect = rect.union(MKCircle(center: home, radius: radiusMeters).boundingMapRect)
        }
        if let patient = patient {
            let point = MKMapPoint(patient)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }

        if home == nil, let patient = patient {
            let region = MKCoordinateRegion(center: patient, latitudinalMeters: 800, longitudinalMeters: 800)
            mapView.setRegion(region, animated: animated)
        } else if !rect.isNull {
            mapView.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 220, right: 40),
                animated: animated
            )
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var isOutside = false
        var lastDataKey = ""
        var lastFitKey = ""
        var hasFitOnce = false

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKCircleRenderer(circle: circle)
            let color: UIColor = isOutside ? .systemRed : .systemGreen
            renderer.fillColor = color.withAlphaComponent(0.15)
            renderer.strokeColor = color
            renderer.lineWidth = 2
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let zoneAnnotation = annotation as? ZoneAnnotation else { return nil }
            let identifier = zoneAnnotation.kind == .home ? "home" : "patient"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: zoneAnnotation, reuseIdentifier: identifier)
            view.annotation = zoneAnnotation
            view.displayPriority = .required
            switch zoneAnnotation.kind {
            case .home:
                view.glyphImage = UIImage(systemName: "house.fill")
                view.markerTintColor = .systemBlue
            case .patient:
                view.glyphImage = UIImage(systemName: "figure.walk")
                view.markerTintColor = isOutside ? .systemRed : .systemGreen
            }
            return view
        }
    }
}
