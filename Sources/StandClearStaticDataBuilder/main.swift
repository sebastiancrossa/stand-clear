import Foundation
import StandClearStaticDataCompiler

enum BuilderError: LocalizedError {
    case usage

    var errorDescription: String? {
        "Usage: StandClearStaticDataBuilder <unpacked-gtfs-directory> <output-json>"
    }
}

func read(_ name: String, from directory: URL, required: Bool = true) throws -> String? {
    let url = directory.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else {
        if required { throw CocoaError(.fileNoSuchFile) }
        return nil
    }
    return try String(contentsOf: url, encoding: .utf8)
}

do {
    guard CommandLine.arguments.count == 3 else { throw BuilderError.usage }
    let inputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let input = try StaticGTFSInput(
        routesCSV: read("routes.txt", from: inputDirectory)!,
        tripsCSV: read("trips.txt", from: inputDirectory)!,
        stopTimesCSV: read("stop_times.txt", from: inputDirectory)!,
        stopsCSV: read("stops.txt", from: inputDirectory)!,
        transfersCSV: read("transfers.txt", from: inputDirectory)!,
        shapesCSV: read("shapes.txt", from: inputDirectory)!,
        feedInfoCSV: read("feed_info.txt", from: inputDirectory, required: false)
    )
    let resource = try StaticGTFSCompiler().compile(input)
    let data = try StaticGTFSCompiler.encode(resource)
    try data.write(to: outputURL, options: .atomic)
    print("Compiled \(resource.paths.count) paths for \(resource.routes.count) routes (\(data.count) bytes).")
    for warning in resource.validationWarnings { print("warning: \(warning)") }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
