import Foundation
import StandClearStaticDataCompiler

enum BuilderError: LocalizedError {
    case usage

    var errorDescription: String? {
        "Usage: StandClearStaticDataBuilder <unpacked-gtfs-directory> <output.scgm>"
    }
}

func readRequired(_ name: String, from directory: URL) throws -> String {
    try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
}

func readOptional(_ name: String, from directory: URL) throws -> String? {
    do {
        return try readRequired(name, from: directory)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        return nil
    }
}

do {
    guard CommandLine.arguments.count == 3 else { throw BuilderError.usage }
    let inputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let input = try StaticGTFSInput(
        routesCSV: readRequired("routes.txt", from: inputDirectory),
        tripsCSV: readRequired("trips.txt", from: inputDirectory),
        stopTimesCSV: readRequired("stop_times.txt", from: inputDirectory),
        stopsCSV: readRequired("stops.txt", from: inputDirectory),
        transfersCSV: readRequired("transfers.txt", from: inputDirectory),
        shapesCSV: readRequired("shapes.txt", from: inputDirectory),
        feedInfoCSV: readOptional("feed_info.txt", from: inputDirectory)
    )
    let resource = try StaticGTFSCompiler().compile(input)
    let data = try StaticGTFSCompiler.encode(resource)
    try data.write(to: outputURL, options: .atomic)
    let routeStylesURL = outputURL
        .deletingLastPathComponent()
        .appendingPathComponent("subway_route_styles.json")
    try StaticGTFSCompiler.encodeRouteStyles(resource).write(to: routeStylesURL, options: .atomic)
    print("Compiled \(resource.paths.count) paths for \(resource.routes.count) routes (\(data.count) bytes).")
    for warning in resource.validationWarnings { print("warning: \(warning)") }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
