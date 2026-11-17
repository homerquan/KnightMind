import ChessCore
import RealityKit
import SwiftUI

@MainActor
enum PieceModels {
    static func make(_ kind: PieceKind, material: PhysicallyBasedMaterial) throws -> ModelEntity {
        let profile = shape(for: kind)
        let model = try ModelEntity(mesh: turned(profile), materials: [material])
        switch kind {
        case .pawn:
            addBall(to: model, material: material, radius: 0.0162, at: [0, 0.064, 0])
        case .rook:
            for i in 0..<4 {
                let angle = Float(i) * .pi / 2 + .pi / 4
                let post = detailBox(material, size: [0.017, 0.011, 0.012], radius: 0.0014)
                post.position = [0.020 * sin(angle), 0.080, 0.020 * cos(angle)]
                post.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
                model.addChild(post)
            }
        case .knight:
            let head = try knightHead(material)
            model.addChild(head)
        case .bishop:
            // A thin dark seam crossing the head reads as the bishop's traditional mitre.
            var groove = material
            groove.baseColor = .init(tint: UIColor(white: 0.19, alpha: 1))
            let slit = detailBox(groove, size: [0.003, 0.016, 0.001], radius: 0.0004)
            slit.position = [0.004, 0.088, 0.0161]
            slit.orientation = simd_quatf(angle: -.pi / 4, axis: [0, 0, 1])
            model.addChild(slit)
            addBall(to: model, material: material, radius: 0.0054, at: [0, 0.105, 0])
        case .queen:
            for i in 0..<6 {
                let angle = Float(i) * .pi / 3
                addBall(to: model, material: material, radius: 0.0044,
                        at: [0.019 * sin(angle), 0.109, 0.019 * cos(angle)])
            }
            addBall(to: model, material: material, radius: 0.0078, at: [0, 0.116, 0])
        case .king:
            let stem = detailBox(material, size: [0.010, 0.022, 0.009], radius: 0.0015)
            stem.position.y = 0.124
            model.addChild(stem)
            let crossbar = detailBox(material, size: [0.027, 0.008, 0.009], radius: 0.0015)
            crossbar.position.y = 0.128
            model.addChild(crossbar)
        }
        return model
    }

    // Profile points are (height, radius) in meters. Closer points keep the turned rings crisp.
    private static func shape(for kind: PieceKind) -> [(Float, Float)] {
        let base: [(Float, Float)] = [
            (0, 0), (0, 0.024), (0.001, 0.029), (0.003, 0.032),
            (0.006, 0.033), (0.008, 0.033), (0.010, 0.031),
            (0.011, 0.029), (0.012, 0.029), (0.014, 0.030),
            (0.016, 0.029), (0.018, 0.026), (0.022, 0.023)
        ]
        switch kind {
        case .pawn:
            return base.map { ($0.0 * 0.88, $0.1 * 0.84) } + [
                (0.025, 0.017), (0.035, 0.012), (0.044, 0.010), (0.048, 0.011),
                (0.050, 0.015), (0.053, 0.016), (0.055, 0.013), (0.056, 0.009), (0.058, 0)
            ]
        case .rook:
            return base + [
                (0.024, 0.022), (0.028, 0.022), (0.030, 0.021), (0.035, 0.018),
                (0.054, 0.018), (0.057, 0.019), (0.059, 0.022), (0.061, 0.025),
                (0.065, 0.026), (0.074, 0.026), (0.075, 0.024), (0.075, 0.016),
                (0.073, 0.014), (0.064, 0.014), (0.063, 0)
            ]
        case .knight:
            return base + [
                (0.025, 0.022), (0.027, 0.022), (0.029, 0.020),
                (0.031, 0.017), (0.032, 0)
            ]
        case .bishop:
            return base + [
                (0.027, 0.020), (0.036, 0.015), (0.053, 0.011), (0.063, 0.010),
                (0.066, 0.013), (0.068, 0.017), (0.071, 0.017), (0.074, 0.014),
                (0.076, 0.009), (0.079, 0.014), (0.084, 0.017), (0.090, 0.017),
                (0.096, 0.013), (0.101, 0.007), (0.106, 0)
            ]
        case .queen, .king:
            let stem = base.map { ($0.0, $0.1 * 1.13) } + [
                (0.026, 0.023), (0.034, 0.018), (0.050, 0.012),
                (0.064, 0.011), (0.072, 0.012), (0.075, 0.015), (0.078, 0.019),
                (0.081, 0.019), (0.083, 0.016), (0.085, 0.016), (0.087, 0.019),
                (0.090, 0.019), (0.092, 0.016)
            ]
            if kind == .queen {
                return stem + [
                    (0.095, 0.018), (0.100, 0.021), (0.106, 0.024), (0.109, 0.023),
                    (0.110, 0.019), (0.107, 0.013), (0.107, 0.008), (0.112, 0.007), (0.112, 0)
                ]
            }
            return stem + [
                (0.096, 0.017), (0.099, 0.023), (0.102, 0.026), (0.105, 0.025),
                (0.108, 0.018), (0.110, 0.012), (0.114, 0.010), (0.116, 0)
            ]
        }
    }

    private static func turned(_ profile: [(Float, Float)]) throws -> MeshResource {
        let segments = 36
        let span = Float(segments)
        let stride = segments + 1
        let highest = profile.map(\.0).max() ?? 1
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uv: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for (row, point) in profile.enumerated() {
            let previous = profile[max(0, row - 1)]
            let next = profile[min(profile.count - 1, row + 1)]
            let dy = next.0 - previous.0
            let dr = next.1 - previous.1
            for slice in 0...segments {
                let angle = Float(slice) * (.pi * 2) / span
                let c = cos(angle)
                let s = sin(angle)
                positions.append([point.1 * c, point.0, point.1 * s])
                normals.append(simd_normalize([dy * c, -dr, dy * s]))
                uv.append([Float(slice) / span, point.0 / highest])
                if row < profile.count - 1 && slice < segments {
                    let a = UInt32(row * stride + slice)
                    let c = a + UInt32(stride)
                    if point.1 > 0 { indices += [a, c, a + 1] }
                    if profile[row + 1].1 > 0 { indices += [a + 1, c, c + 1] }
                }
            }
        }

        var mesh = MeshDescriptor(name: "Turned wood")
        mesh.positions = MeshBuffers.Positions(positions)
        mesh.normals = MeshBuffers.Normals(normals)
        mesh.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        mesh.primitives = .triangles(indices)
        return try MeshResource.generate(from: [mesh])
    }

    private static func knightHead(_ material: PhysicallyBasedMaterial) throws -> ModelEntity {
        let profile = Path { path in
            path.move(to: CGPoint(x: -0.020, y: 0.027))
            path.addQuadCurve(to: CGPoint(x: -0.013, y: 0.078), control: CGPoint(x: -0.026, y: 0.058))
            path.addQuadCurve(to: CGPoint(x: 0.001, y: 0.096), control: CGPoint(x: -0.009, y: 0.093))
            path.addLine(to: CGPoint(x: 0.006, y: 0.107))
            path.addLine(to: CGPoint(x: 0.013, y: 0.093))
            path.addQuadCurve(to: CGPoint(x: 0.032, y: 0.069), control: CGPoint(x: 0.020, y: 0.084))
            path.addQuadCurve(to: CGPoint(x: 0.024, y: 0.057), control: CGPoint(x: 0.034, y: 0.061))
            path.addQuadCurve(to: CGPoint(x: 0.006, y: 0.066), control: CGPoint(x: 0.014, y: 0.058))
            path.addQuadCurve(to: CGPoint(x: 0.013, y: 0.028), control: CGPoint(x: 0.002, y: 0.052))
            path.closeSubpath()
        }
        var options = MeshResource.ShapeExtrusionOptions()
        options.extrusionMethod = .linear(depth: 0.018)
        options.chamferRadius = 0.0027
        options.chamferMode = .both
        options.materialAssignment = .init(assignAll: 0)
        let mesh = try MeshResource(extruding: profile, extrusionOptions: options)
        let head = ModelEntity(mesh: mesh, materials: [material])
        let bounds = mesh.bounds
        head.position = [0, 0.028 - bounds.min.y, -bounds.center.z]
        return head
    }

    private static func addBall(to parent: Entity, material: PhysicallyBasedMaterial,
                                radius: Float, at position: SIMD3<Float>) {
        let detail = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
        detail.position = position
        parent.addChild(detail)
    }

    private static func detailBox(_ material: PhysicallyBasedMaterial, size: SIMD3<Float>, radius: Float) -> ModelEntity {
        ModelEntity(mesh: .generateBox(size: size, cornerRadius: radius), materials: [material])
    }
}
