import Foundation

/// Packed binary encoding for `SubwayGeometryResource`. Points are stored as
/// contiguous Float32 triples so the catalog can be memory-mapped on load
/// without a Codable/JSON decode peak.
public enum GeometryBinaryCodec {
    public static let magic = Data("SCGM".utf8)
    public static let formatVersion: UInt32 = 3

    public enum Error: Swift.Error {
        case truncated
        case invalidMagic
        case unsupportedVersion(UInt32)
        case invalidUTF8
    }

    public static func encode(_ resource: SubwayGeometryResource) throws -> Data {
        var writer = Writer()
        writer.writeBytes(magic)
        writer.writeUInt32(formatVersion)
        writer.writeUInt32(UInt32(resource.version))
        writer.writeOptionalString(resource.feedVersion)
        writer.writeUInt32(UInt32(resource.routes.count))
        for route in resource.routes {
            writer.writeString(route.id)
            writer.writeString(route.shortName)
            writer.writeString(route.longName)
            writer.writeString(route.colorHex)
            writer.writeString(route.textColorHex)
            writer.writeInt32(Int32(route.sortOrder))
        }
        writer.writeUInt32(UInt32(resource.paths.count))
        for path in resource.paths {
            writer.writeString(path.shapeID)
            writer.writeUInt32(UInt32(path.routeIDs.count))
            for routeID in path.routeIDs {
                writer.writeString(routeID)
            }
            writer.writeUInt32(UInt32(path.directionIDs.count))
            for directionID in path.directionIDs {
                writer.writeInt32(Int32(directionID))
            }
            writer.writePoints(path.points)
            writer.writeUInt32(UInt32(path.anchors.count))
            for anchor in path.anchors {
                writer.writeString(anchor.stopID)
                writer.writeString(anchor.stationID)
                writer.writeInt32(Int32(anchor.sequence))
                writer.writeInt32(Int32(anchor.pointIndex))
                writer.writeFloat32(Float(anchor.distanceMeters))
                writer.writeOptionalInt32(anchor.medianDwellSeconds.map(Int32.init))
                writer.writeOptionalInt32(anchor.medianTravelSecondsToNext.map(Int32.init))
            }
        }
        writer.writeUInt32(UInt32(resource.corridors.count))
        for corridor in resource.corridors {
            writer.writeString(corridor.id)
            writer.writeUInt32(UInt32(corridor.shapeIDs.count))
            for shapeID in corridor.shapeIDs {
                writer.writeString(shapeID)
            }
            writer.writeUInt32(UInt32(corridor.routeIDs.count))
            for routeID in corridor.routeIDs {
                writer.writeString(routeID)
            }
            writer.writePoints(corridor.points)
        }
        writer.writeUInt32(UInt32(resource.transferGroups.count))
        for group in resource.transferGroups {
            writer.writeUInt32(UInt32(group.stationIDs.count))
            for stationID in group.stationIDs {
                writer.writeString(stationID)
            }
        }
        writer.writeUInt32(UInt32(resource.validationWarnings.count))
        for warning in resource.validationWarnings {
            writer.writeString(warning)
        }
        return writer.data
    }

    public static func decode(_ data: Data) throws -> SubwayGeometryResource {
        var reader = Reader(data: data)
        let magicBytes = try reader.readBytes(4)
        guard magicBytes == magic else { throw Error.invalidMagic }
        let format = try reader.readUInt32()
        guard format == formatVersion else { throw Error.unsupportedVersion(format) }
        let version = Int(try reader.readUInt32())
        let feedVersion = try reader.readOptionalString()
        let routeCount = Int(try reader.readUInt32())
        var routes: [RouteGeometryMetadata] = []
        routes.reserveCapacity(routeCount)
        for _ in 0..<routeCount {
            routes.append(
                RouteGeometryMetadata(
                    id: try reader.readString(),
                    shortName: try reader.readString(),
                    longName: try reader.readString(),
                    colorHex: try reader.readString(),
                    textColorHex: try reader.readString(),
                    sortOrder: Int(try reader.readInt32())
                )
            )
        }
        let pathCount = Int(try reader.readUInt32())
        var paths: [TrackPath] = []
        paths.reserveCapacity(pathCount)
        for _ in 0..<pathCount {
            let shapeID = try reader.readString()
            let routeCount = Int(try reader.readUInt32())
            var routeIDs: [String] = []
            routeIDs.reserveCapacity(routeCount)
            for _ in 0..<routeCount {
                routeIDs.append(try reader.readString())
            }
            let directionCount = Int(try reader.readUInt32())
            var directionIDs: [Int] = []
            directionIDs.reserveCapacity(directionCount)
            for _ in 0..<directionCount {
                directionIDs.append(Int(try reader.readInt32()))
            }
            let points = try reader.readPoints()
            let anchorCount = Int(try reader.readUInt32())
            var anchors: [TrackStopAnchor] = []
            anchors.reserveCapacity(anchorCount)
            for _ in 0..<anchorCount {
                anchors.append(
                    TrackStopAnchor(
                        stopID: try reader.readString(),
                        stationID: try reader.readString(),
                        sequence: Int(try reader.readInt32()),
                        pointIndex: Int(try reader.readInt32()),
                        distanceMeters: Double(try reader.readFloat32()),
                        medianDwellSeconds: try reader.readOptionalInt32().map(Int.init),
                        medianTravelSecondsToNext: try reader.readOptionalInt32().map(Int.init)
                    )
                )
            }
            paths.append(
                TrackPath(
                    shapeID: shapeID,
                    routeIDs: routeIDs,
                    directionIDs: directionIDs,
                    points: points,
                    anchors: anchors
                )
            )
        }
        let corridorCount = Int(try reader.readUInt32())
        var corridors: [RenderCorridor] = []
        corridors.reserveCapacity(corridorCount)
        for _ in 0..<corridorCount {
            let id = try reader.readString()
            let shapeCount = Int(try reader.readUInt32())
            var shapeIDs: [String] = []
            shapeIDs.reserveCapacity(shapeCount)
            for _ in 0..<shapeCount {
                shapeIDs.append(try reader.readString())
            }
            let routeCount = Int(try reader.readUInt32())
            var routeIDs: [String] = []
            routeIDs.reserveCapacity(routeCount)
            for _ in 0..<routeCount {
                routeIDs.append(try reader.readString())
            }
            let points = try reader.readPoints()
            corridors.append(
                RenderCorridor(id: id, shapeIDs: shapeIDs, routeIDs: routeIDs, points: points)
            )
        }
        let transferCount = Int(try reader.readUInt32())
        var transferGroups: [StationTransferGroup] = []
        transferGroups.reserveCapacity(transferCount)
        for _ in 0..<transferCount {
            let stationCount = Int(try reader.readUInt32())
            var stationIDs: [String] = []
            stationIDs.reserveCapacity(stationCount)
            for _ in 0..<stationCount {
                stationIDs.append(try reader.readString())
            }
            transferGroups.append(StationTransferGroup(stationIDs: stationIDs))
        }
        let warningCount = Int(try reader.readUInt32())
        var warnings: [String] = []
        warnings.reserveCapacity(warningCount)
        for _ in 0..<warningCount {
            warnings.append(try reader.readString())
        }
        return SubwayGeometryResource(
            version: version,
            feedVersion: feedVersion,
            routes: routes,
            paths: paths,
            corridors: corridors,
            transferGroups: transferGroups,
            validationWarnings: warnings
        )
    }
}

private struct Writer {
    var data = Data()

    mutating func writeBytes(_ bytes: Data) {
        data.append(bytes)
    }

    mutating func writeUInt32(_ value: UInt32) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    mutating func writeInt32(_ value: Int32) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    mutating func writeFloat32(_ value: Float) {
        var le = value.bitPattern.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    mutating func writeString(_ value: String) {
        let utf8 = Data(value.utf8)
        writeUInt32(UInt32(utf8.count))
        data.append(utf8)
    }

    mutating func writeOptionalString(_ value: String?) {
        if let value {
            writeUInt32(1)
            writeString(value)
        } else {
            writeUInt32(0)
        }
    }

    mutating func writeOptionalInt32(_ value: Int32?) {
        if let value {
            writeUInt32(1)
            writeInt32(value)
        } else {
            writeUInt32(0)
        }
    }

    mutating func writePoints(_ points: [TrackPoint]) {
        writeUInt32(UInt32(points.count))
        for point in points {
            writeFloat32(Float(point.latitude))
            writeFloat32(Float(point.longitude))
            writeFloat32(Float(point.distanceMeters))
        }
    }
}

private struct Reader {
    let data: Data
    var offset = 0

    mutating func readBytes(_ count: Int) throws -> Data {
        guard offset + count <= data.count else { throw GeometryBinaryCodec.Error.truncated }
        let slice = data.subdata(in: offset..<(offset + count))
        offset += count
        return slice
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(4)
        return bytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }

    mutating func readInt32() throws -> Int32 {
        let bytes = try readBytes(4)
        return Int32(bitPattern: bytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
    }

    mutating func readFloat32() throws -> Float {
        let bits = try readUInt32()
        return Float(bitPattern: bits)
    }

    mutating func readString() throws -> String {
        let count = Int(try readUInt32())
        let bytes = try readBytes(count)
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw GeometryBinaryCodec.Error.invalidUTF8
        }
        return string
    }

    mutating func readOptionalString() throws -> String? {
        let flag = try readUInt32()
        guard flag != 0 else { return nil }
        return try readString()
    }

    mutating func readOptionalInt32() throws -> Int32? {
        let flag = try readUInt32()
        guard flag != 0 else { return nil }
        return try readInt32()
    }

    mutating func readPoints() throws -> [TrackPoint] {
        let count = Int(try readUInt32())
        var points: [TrackPoint] = []
        points.reserveCapacity(count)
        for _ in 0..<count {
            points.append(
                TrackPoint(
                    latitude: Double(try readFloat32()),
                    longitude: Double(try readFloat32()),
                    distanceMeters: Double(try readFloat32())
                )
            )
        }
        return points
    }
}
