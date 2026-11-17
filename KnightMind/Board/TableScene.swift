import ChessCore
import RealityKit
import SwiftUI
import UIKit

@MainActor
final class TableScene {
    let root = Entity()
    let camera = PerspectiveCamera()

    private let figures = Entity()
    private let markers = Entity()
    private var prototypes: [Piece: Entity] = [:]
    private var occupants: [Square: (piece: Piece, entity: Entity)] = [:]
    private var visibleMarks: [Square: BoardMark] = [:]
    private var lastRevision: Int?
    private var viewport = CGSize.zero

    init() throws {
        setUpCamera()
        setUpLights()
        setUpBoard()
        try setUpPieces()
        root.addChild(figures)
        root.addChild(markers)
    }

    /// Fit the tabletop and tall pieces to the viewport. Ray picking uses this same camera.
    func fit(in size: CGSize) {
        guard size.width > 0, size.height > 0, size != viewport else { return }
        viewport = size
        let inverse = camera.orientation.inverse
        let aspect = Float(size.height / size.width)
        var slope: Float = 0
        for x: Float in [-0.456, 0.456] {
            for z: Float in [-0.456, 0.456] {
                let point = inverse.act(SIMD3<Float>(x, -0.045, z) - camera.position)
                slope = max(slope, abs(point.x / point.z) / 0.98,
                            abs(point.y / point.z) / (aspect * 0.94))
            }
        }
        for x: Float in [-0.35, 0.35] {
            for z: Float in [-0.35, 0.35] {
                let point = inverse.act(SIMD3<Float>(x, 0.15, z) - camera.position)
                slope = max(slope, abs(point.x / point.z) / 0.98,
                            abs(point.y / point.z) / (aspect * 0.94))
            }
        }
        camera.camera.fieldOfViewInDegrees = 2 * atan(slope) * 180 / .pi
    }

    func update(_ state: BoardState, animate: Bool) {
        if lastRevision != state.revision {
            if animate, lastRevision != nil, let move = state.recent,
               let moving = occupants[move.from], moving.piece == state.position[move.to] {
                relocate(from: move.from, to: move.to)
                if moving.piece.kind == .king, abs(move.to.file - move.from.file) == 2 {
                    let kingside = move.to.file > move.from.file
                    let from = Square(file: kingside ? 7 : 0, rank: move.from.rank)!
                    let to = Square(file: kingside ? 5 : 3, rank: move.from.rank)!
                    relocate(from: from, to: to)
                }
            }
            for square in Square.all {
                let piece = state.position[square]
                if occupants[square]?.piece == piece { continue }
                occupants.removeValue(forKey: square)?.entity.removeFromParent()
                if let piece, let prototype = prototypes[piece] {
                    let copy = prototype.clone(recursive: true)
                    copy.position = location(for: square, height: 0.001)
                    copy.name = square.name
                    figures.addChild(copy)
                    occupants[square] = (piece, copy)
                }
            }
            lastRevision = state.revision
        }

        var nextMarks: [Square: BoardMark] = [:]
        for square in Square.all {
            nextMarks[square] = state.mark(at: square)
        }
        if nextMarks != visibleMarks {
            markers.children.removeAll()
            for (square, mark) in nextMarks {
                let token = makeMarker(mark)
                token.position = location(for: square, height: 0.0015)
                markers.addChild(token)
            }
            visibleMarks = nextMarks
        }
    }

    func square(at point: CGPoint, in viewport: CGSize, state: BoardState) -> Square? {
        guard viewport.width > 0 else { return nil }
        let origin = camera.position
        let slope = tan(camera.camera.fieldOfViewInDegrees * .pi / 360)
        let x = Float((2 * point.x - viewport.width) / viewport.width)
        let y = Float((viewport.height - 2 * point.y) / viewport.width)
        let direction = camera.orientation.act(simd_normalize(SIMD3<Float>(x * slope, y * slope, -1)))
        guard direction.y < 0 else { return nil }
        let distance = (0.0003 - origin.y) / direction.y
        let boardPoint = origin + distance * direction
        let square = Square(file: Int(floor((0.4 + boardPoint.x) / 0.1)),
                            rank: Int(floor((0.4 - boardPoint.z) / 0.1)))
        if let square, state.destinations.contains(square), state.position[square] == nil {
            return square
        }
        let hit = root.scene?.raycast(origin: origin, direction: direction, length: distance,
                                      query: .nearest, relativeTo: root).first
        return hit.flatMap { Square(named: $0.entity.name) } ?? square
    }

    private func relocate(from: Square, to: Square) {
        guard let moving = occupants.removeValue(forKey: from) else { return }
        occupants.removeValue(forKey: to)?.entity.removeFromParent()
        moving.entity.name = to.name
        moving.entity.stopAllAnimations(recursive: false)
        let final = Transform(translation: location(for: to, height: 0.001))
        moving.entity.move(to: final, relativeTo: figures, duration: 0.19, timingFunction: .easeInOut)
        occupants[to] = moving
    }

    private func location(for square: Square, height: Float = 0) -> SIMD3<Float> {
        [(Float(square.file) - 3.5) * 0.1, height, (3.5 - Float(square.rank)) * 0.1]
    }

    private func setUpCamera() {
        camera.camera = PerspectiveCameraComponent(near: 0.03, far: 12, fieldOfViewInDegrees: 32.5,
                                                  fieldOfViewOrientation: .horizontal)
        camera.look(at: [0, 0.020, 0.035], from: [0, 1.90, 0.95], relativeTo: nil)
        root.addChild(camera)
    }

    private func setUpLights() {
        let key = DirectionalLight()
        key.light.color = UIColor(red: 1, green: 0.92, blue: 0.80, alpha: 1)
        key.light.intensity = 3_150
        var shadow = DirectionalLightComponent.Shadow()
        shadow.depthBias = 0.55
        shadow.shadowProjection = .automatic(maximumDistance: 3)
        key.shadow = shadow
        key.look(at: .zero, from: [-0.43, 0.91, 0.64], relativeTo: nil)
        root.addChild(key)

        let fill = DirectionalLight()
        fill.light.color = UIColor(red: 0.81, green: 0.87, blue: 1, alpha: 1)
        fill.light.intensity = 820
        fill.look(at: .zero, from: [0.70, 0.70, -0.52], relativeTo: nil)
        root.addChild(fill)
    }

    private func setUpBoard() {
        let edge = wood("WoodEdge", fallback: UIColor(red: 0.38, green: 0.22, blue: 0.11, alpha: 1), polish: 0.37)
        let lower = ModelEntity(mesh: .generateBox(width: 0.912, height: 0.018, depth: 0.912, cornerRadius: 0.005),
                                materials: [edge])
        lower.position.y = -0.036
        root.addChild(lower)
        let casework = ModelEntity(mesh: .generateBox(width: 0.908, height: 0.032, depth: 0.908, cornerRadius: 0.004),
                                   materials: [edge])
        casework.position.y = -0.016
        root.addChild(casework)

        let surface = wood("BoardFace", fallback: .brown, polish: 0.48)
        let face = ModelEntity(mesh: .generatePlane(width: 0.9, depth: 0.9), materials: [surface])
        face.position.y = 0.0003
        root.addChild(face)

    }

    private func setUpPieces() throws {
        var contact = UnlitMaterial(applyPostProcessToneMap: false)
        contact.color = .init(tint: .white, texture: texture("Contact"))
        contact.blending = .transparent(opacity: .init(floatLiteral: 1))
        contact.writesDepth = false
        let shade = MeshResource.generatePlane(width: 0.105, depth: 0.099)
        let maple = wood("Maple", fallback: UIColor(red: 0.82, green: 0.70, blue: 0.55, alpha: 1), polish: 0.30)
        var walnut = wood("Walnut", fallback: UIColor(red: 0.28, green: 0.15, blue: 0.09, alpha: 1), polish: 0.32)
        if let map = walnut.baseColor.texture {
            walnut.baseColor = .init(tint: UIColor(red: 0.79, green: 0.81, blue: 0.85, alpha: 1), texture: map)
        }
        let finishes = [(Side.white, maple), (Side.black, walnut)]
        for (side, material) in finishes {
            for kind in PieceKind.allCases {
                let figure = Entity()
                let mesh = try PieceModels.make(kind, material: material)
                if side == .black && kind == .knight {
                    mesh.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
                }
                figure.addChild(mesh)
                let shadow = ModelEntity(mesh: shade, materials: [contact])
                shadow.position = [0.012, 0.0001, -0.011]
                figure.addChild(shadow)
                let bounds = mesh.visualBounds(relativeTo: figure)
                let hitbox = ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)
                figure.components.set(CollisionComponent(shapes: [hitbox]))
                prototypes[Piece(side, kind)] = figure
            }
        }
    }

    private func makeMarker(_ mark: BoardMark) -> Entity {
        let color = UIColor(mark.tint)
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: color)
        material.blending = .transparent(opacity: .init(floatLiteral: mark == .recent ? 0.23 : 0.38))
        material.writesDepth = false
        if mark == .target(capture: false) {
            return ModelEntity(mesh: .generateCylinder(height: 0.0018, radius: 0.010), materials: [UnlitMaterial(color: color)])
        }
        let group = Entity()
        group.addChild(ModelEntity(mesh: .generatePlane(width: 0.094, depth: 0.094), materials: [material]))
        let stroke = UnlitMaterial(color: color)
        let horizontal = MeshResource.generatePlane(width: 0.094, depth: 0.0023)
        let vertical = MeshResource.generatePlane(width: 0.0023, depth: 0.094)
        for sign: Float in [-1, 1] {
            let x = ModelEntity(mesh: vertical, materials: [stroke])
            x.position = [sign * 0.046, 0.0003, 0]
            group.addChild(x)
            let z = ModelEntity(mesh: horizontal, materials: [stroke])
            z.position = [0, 0.0003, sign * 0.046]
            group.addChild(z)
        }
        return group
    }

    private func wood(_ name: String, fallback: UIColor, polish: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let map = texture(name)
        material.baseColor = .init(tint: map == nil ? fallback : .white, texture: map)
        material.roughness = .init(floatLiteral: polish)
        material.metallic = .init(floatLiteral: 0)
        material.clearcoat = .init(floatLiteral: 0.28)
        material.clearcoatRoughness = .init(floatLiteral: 0.34)
        return material
    }

    private func texture(_ name: String) -> MaterialParameters.Texture? {
        guard let image = UIImage(named: name)?.cgImage,
              let resource = try? TextureResource(image: image, withName: name, options: .init(semantic: .color)) else {
            return nil
        }
        return MaterialParameters.Texture(resource)
    }
}
