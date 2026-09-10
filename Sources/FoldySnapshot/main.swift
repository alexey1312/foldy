import CoreGraphics
import Foundation
import ImageIO
import FoldyCore
import Metal

// foldy-snapshot: render the fold, or the MacBook preview, to a PNG.
//
//   foldy-snapshot --out fold.png --progress 0.7 --style silk
//   foldy-snapshot --out mac.png --scene macbook --lid 60 --style frost --width 1600
//   foldy-snapshot --out mac.png --scene macbook --lid 60 --source ~/Desktop/shot.png

struct Options {
    var out = "snapshot.png"
    var scene = "flat"
    var style = FoldStyle.silk
    var progress: Double?
    var lid: Double = 60
    var width = 1400
    var source: String?
    var bend: Double?
    var background = "clear"
}

func parse() -> Options {
    var options = Options()
    var args = CommandLine.arguments.dropFirst().makeIterator()
    func value(_ flag: String) -> String {
        guard let v = args.next() else {
            FileHandle.standardError.write("missing value for \(flag)\n".data(using: .utf8)!)
            exit(2)
        }
        return v
    }
    while let arg = args.next() {
        switch arg {
        case "--out": options.out = value(arg)
        case "--scene": options.scene = value(arg)
        case "--style":
            guard let style = FoldStyle(rawValue: value(arg).lowercased()) else { exit(2) }
            options.style = style
        case "--progress": options.progress = Double(value(arg))
        case "--lid": options.lid = Double(value(arg)) ?? 60
        case "--width": options.width = Int(value(arg)) ?? 1400
        case "--source": options.source = value(arg)
        case "--bend": options.bend = Double(value(arg))
        case "--background": options.background = value(arg)
        case "-h", "--help":
            print("usage: foldy-snapshot [--out file.png] [--scene flat|macbook] [--style silk|shade|frost] [--progress 0..1] [--lid degrees] [--width px] [--source image.png] [--bend 0..1] [--background clear|white|black]")
            exit(0)
        default:
            FileHandle.standardError.write("unknown argument \(arg)\n".data(using: .utf8)!)
            exit(2)
        }
    }
    return options
}

let options = parse()
let graphics = try FoldGraphics()

let sourceImage: CGImage
if let path = options.source {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard let cgSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(cgSource, 0, nil) else {
        FileHandle.standardError.write("could not read \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    sourceImage = image
} else {
    sourceImage = WallpaperArt.image()!
}

let clear: MTLClearColor = switch options.background {
case "white": MTLClearColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)
case "black": MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
default: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
}

let curve = FoldCurve.default
let output: MTLTexture
guard let commandBuffer = graphics.commandQueue.makeCommandBuffer() else { exit(1) }

if options.scene == "macbook" {
    let scene = try MacBookScene(graphics: graphics)
    try scene.fold.setSource(cgImage: sourceImage)
    var parameters = options.style.parameters
    if let bend = options.bend { parameters.bend = bend }
    scene.fold.parameters = parameters
    scene.smoothing = 1
    scene.targetLidAngle = options.progress.map { curve.angle(forFraction: $0) } ?? options.lid
    scene.backgroundColor = clear
    scene.step()
    let height = Int(Double(options.width) * 0.64)
    guard let target = graphics.makeTargetTexture(width: options.width, height: height, label: "Snapshot") else { exit(1) }
    scene.encode(into: commandBuffer, target: target, depth: nil)
    output = target
} else {
    let fold = try FoldRenderer(graphics: graphics)
    try fold.setSource(cgImage: sourceImage)
    var parameters = options.style.parameters
    if let bend = options.bend { parameters.bend = bend }
    fold.parameters = parameters
    fold.smoothing = 1
    fold.targetProgress = options.progress ?? curve.progress(forAngle: options.lid)
    fold.step()
    let aspect = Double(sourceImage.width) / Double(sourceImage.height)
    guard let target = graphics.makeTargetTexture(width: options.width, height: Int(Double(options.width) / aspect), label: "Snapshot") else { exit(1) }
    fold.encode(into: commandBuffer, target: target, clearColor: options.background == "clear" ? MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1) : clear)
    output = target
}

commandBuffer.commit()
commandBuffer.waitUntilCompleted()

guard let image = ImageExport.cgImage(from: output, commandQueue: graphics.commandQueue) else {
    FileHandle.standardError.write("readback failed\n".data(using: .utf8)!)
    exit(1)
}
let outURL = URL(fileURLWithPath: (options.out as NSString).expandingTildeInPath)
try ImageExport.writePNG(image, to: outURL)
print("wrote \(outURL.path) (\(image.width)×\(image.height))")
