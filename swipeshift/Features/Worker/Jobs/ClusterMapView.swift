//
//  ClusterMapView.swift
//  swipeShift
//
//  UIViewRepresentable um MKMapView mit nativen Clustering zu nutzen.
//  Clustering ist in SwiftUI Map API (iOS 17) noch nicht unterstützt.
//

import SwiftUI
import MapKit

// MARK: - Job Annotation (MKAnnotation)

final class JobAnnotation: NSObject, MKAnnotation {
    let job: Job
    let pinUIColor: UIColor
    let coordinate: CLLocationCoordinate2D
    var title: String? { job.title }

    init(job: Job, pinUIColor: UIColor) {
        self.job = job
        self.pinUIColor = pinUIColor
        self.coordinate = CLLocationCoordinate2D(latitude: job.lat!, longitude: job.lng!)
    }
}

// MARK: - Single Job Annotation View

final class JobAnnotationView: MKAnnotationView {
    static let reuseID = "JobAnnotationView"
    private let size: CGFloat = 20

    override var annotation: MKAnnotation? { didSet { render() } }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        // Wichtig: gleiche clusteringIdentifier → MapKit gruppiert automatisch
        clusteringIdentifier = "job"
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        centerOffset = .zero
        render()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func render() {
        guard let ann = annotation as? JobAnnotation else { return }
        let s = size
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
        image = renderer.image { _ in
            // Farbiger Kreis
            ann.pinUIColor.setFill()
            UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: s - 4, height: s - 4)).fill()
            // Weißer Rand
            UIColor.white.setStroke()
            let border = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: s - 4, height: s - 4))
            border.lineWidth = 2
            border.stroke()
        }
    }
}

// MARK: - Selected Job Annotation View (größer, mit Pulsring)

final class SelectedJobAnnotationView: MKAnnotationView {
    static let reuseID = "SelectedJobAnnotationView"
    private let size: CGFloat = 26

    override var annotation: MKAnnotation? { didSet { render() } }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = nil  // ausgewählter Pin nicht clustern
        frame = CGRect(x: 0, y: 0, width: size + 14, height: size + 14)
        centerOffset = .zero
        render()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func render() {
        guard let ann = annotation as? JobAnnotation else { return }
        let total: CGFloat = size + 14
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: total, height: total))
        image = renderer.image { _ in
            // Pulsring
            ann.pinUIColor.withAlphaComponent(0.25).setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: total, height: total)).fill()
            // Hauptkreis
            ann.pinUIColor.setFill()
            let inner = (total - size) / 2
            UIBezierPath(ovalIn: CGRect(x: inner, y: inner, width: size, height: size)).fill()
            UIColor.white.setStroke()
            let border = UIBezierPath(ovalIn: CGRect(x: inner, y: inner, width: size, height: size))
            border.lineWidth = 2.5
            border.stroke()
        }
    }
}

// MARK: - Cluster Annotation View

final class JobClusterAnnotationView: MKAnnotationView {
    static let reuseID = "JobClusterAnnotationView"
    private let size: CGFloat = 36

    override var annotation: MKAnnotation? { didSet { render() } }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        render()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func render() {
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let count = cluster.memberAnnotations.count

        // Dominante Farbe aus Member-Annotations bestimmen
        let colors = cluster.memberAnnotations.compactMap { ($0 as? JobAnnotation)?.pinUIColor }
        let dominantColor: UIColor = colors.first ?? UIColor(red: 91/255, green: 92/255, blue: 230/255, alpha: 1)

        let s = size
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
        image = renderer.image { _ in
            // Hintergrundkreis
            dominantColor.setFill()
            UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: s - 4, height: s - 4)).fill()
            // Weißer Rand
            UIColor.white.setStroke()
            let border = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: s - 4, height: s - 4))
            border.lineWidth = 2
            border.stroke()
            // Anzahl
            let text = "\(count)"
            let fontSize: CGFloat = count > 9 ? 11 : 13
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let ts = attrStr.size()
            attrStr.draw(at: CGPoint(x: s / 2 - ts.width / 2, y: s / 2 - ts.height / 2))
        }
    }
}

// MARK: - ClusterMapView (UIViewRepresentable)

struct ClusterMapView: UIViewRepresentable {
    let jobs: [Job]
    let pinColor: (Job) -> Color
    let selectedJobId: String?
    let onJobTapped: (Job) -> Void
    @Binding var region: MKCoordinateRegion

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.mapType = .standard
        map.register(JobAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: JobAnnotationView.reuseID)
        map.register(SelectedJobAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: SelectedJobAnnotationView.reuseID)
        map.register(JobClusterAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        map.setRegion(region, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        updateAnnotations(on: map)

        // Kamera nur setzen wenn SwiftUI-seitig geändert (nicht durch User-Interaktion)
        if !context.coordinator.isUserInteracting {
            if abs(map.region.center.latitude  - region.center.latitude)  > 0.001 ||
               abs(map.region.center.longitude - region.center.longitude) > 0.001 {
                map.setRegion(region, animated: true)
            }
        }
    }

    // MARK: - Annotation Update

    private func updateAnnotations(on map: MKMapView) {
        let newJobs = jobs.filter { $0.lat != nil && $0.lng != nil }
        let newIds  = Set(newJobs.map { $0.id })
        let existing = map.annotations.compactMap { $0 as? JobAnnotation }
        let existingIds = Set(existing.map { $0.job.id })

        // Entfernen was nicht mehr da ist
        let toRemove = existing.filter { !newIds.contains($0.job.id) }
        if !toRemove.isEmpty { map.removeAnnotations(toRemove) }

        // Hinzufügen was neu ist
        let toAdd: [JobAnnotation] = newJobs.compactMap { job in
            guard !existingIds.contains(job.id) else { return nil }
            return JobAnnotation(job: job, pinUIColor: uiColor(from: pinColor(job)))
        }
        if !toAdd.isEmpty { map.addAnnotations(toAdd) }

        // zPriority für ausgewählten Pin setzen → er wird nicht geclustert
        map.annotations
            .compactMap { $0 as? JobAnnotation }
            .forEach { ann in
                if let view = map.view(for: ann) {
                    view.zPriority = ann.job.id == selectedJobId ? .max : .defaultSelected
                }
            }
    }

    private func uiColor(from color: Color) -> UIColor { UIColor(color) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ClusterMapView
        var isUserInteracting = false

        init(_ parent: ClusterMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if annotation is MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: annotation
                )
            }

            guard let jobAnn = annotation as? JobAnnotation else { return nil }

            // Ausgewählter Pin bekommt eigene View (kein Clustering, größer)
            if jobAnn.job.id == parent.selectedJobId {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: SelectedJobAnnotationView.reuseID,
                    for: jobAnn
                ) as? SelectedJobAnnotationView ?? SelectedJobAnnotationView(annotation: jobAnn, reuseIdentifier: SelectedJobAnnotationView.reuseID)
                view.annotation = jobAnn
                view.zPriority = .max
                return view
            }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: JobAnnotationView.reuseID,
                for: jobAnn
            ) as? JobAnnotationView ?? JobAnnotationView(annotation: jobAnn, reuseIdentifier: JobAnnotationView.reuseID)
            view.annotation = jobAnn
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            mapView.deselectAnnotation(view.annotation, animated: false)

            if let jobAnn = view.annotation as? JobAnnotation {
                parent.onJobTapped(jobAnn.job)
                return
            }

            // Cluster-Tap → Zoom rein
            if let cluster = view.annotation as? MKClusterAnnotation {
                let coords = cluster.memberAnnotations.map { $0.coordinate }
                let lats   = coords.map { $0.latitude }
                let lngs   = coords.map { $0.longitude }
                guard let minLat = lats.min(), let maxLat = lats.max(),
                      let minLng = lngs.min(), let maxLng = lngs.max() else { return }

                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude:  (minLat + maxLat) / 2,
                        longitude: (minLng + maxLng) / 2
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta:  max((maxLat - minLat) * 2.5, 0.01),
                        longitudeDelta: max((maxLng - minLng) * 2.5, 0.01)
                    )
                )
                mapView.setRegion(region, animated: true)
                parent.region = region
            }
        }

        func mapViewWillStartInteracting(_ mapView: MKMapView) {
            isUserInteracting = true
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
            isUserInteracting = false
        }
    }
}
