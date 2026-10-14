// ComputePlanInspector: where does each operation of a Core ML model run?
//
//   swift run ComputePlanInspector                       # all models in ./models
//   swift run ComputePlanInspector MiniLMEmbedding.mlpackage --units cpuAndNeuralEngine
//   swift run ComputePlanInspector CharLM.mlpackage --verbose
//
// MLComputePlan reports, for every operation in an ML Program (or layer in an
// older neural network model), the devices that can run it and the device
// Core ML prefers, plus an estimated relative cost. That tells us whether a
// model really runs on the Neural Engine and which ops push work to the
// CPU or GPU.

import CoreML
import Foundation
import MLSupport

func shortName(_ device: MLComputeDevice) -> String {
    switch device {
    case .cpu: "CPU"
    case .gpu: "GPU"
    case .neuralEngine: "ANE"
    @unknown default: "?"
    }
}

/// One row per operation that has a device assignment.
struct OpReport {
    let function: String
    let op: String
    let preferred: String
    let supported: [String]
    let cost: Double
}

func collect(_ block: MLModelStructure.Program.Block, function: String,
             plan: MLComputePlan, into rows: inout [OpReport]) {
    for operation in block.operations {
        // Constants and other bookkeeping ops have no device usage.
        if let usage = plan.deviceUsage(for: operation) {
            rows.append(OpReport(
                function: function,
                op: operation.operatorName,
                preferred: shortName(usage.preferred),
                supported: usage.supported.map(shortName),
                cost: plan.estimatedCost(of: operation)?.weight ?? 0))
        }
        // Control flow ops (cond, while_loop) carry nested blocks.
        for nested in operation.blocks {
            collect(nested, function: function, plan: plan, into: &rows)
        }
    }
}

func collect(_ structure: MLModelStructure, plan: MLComputePlan,
             into rows: inout [OpReport]) {
    switch structure {
    case .program(let program):
        for (name, function) in program.functions.sorted(by: { $0.key < $1.key }) {
            collect(function.block, function: name, plan: plan, into: &rows)
        }
    case .neuralNetwork(let network):
        for layer in network.layers {
            if let usage = plan.deviceUsage(for: layer) {
                rows.append(OpReport(function: "main", op: layer.type,
                                     preferred: shortName(usage.preferred),
                                     supported: usage.supported.map(shortName), cost: 0))
            }
        }
    case .pipeline(let pipeline):
        for model in pipeline.subModels {
            collect(model, plan: plan, into: &rows)
        }
    case .unsupported:
        break
    @unknown default:
        break
    }
}

func pct(_ x: Double) -> String { String(format: "%5.1f%%", x * 100) }

func inspect(_ fileName: String, units: MLComputeUnits, unitsName: String,
             verbose: Bool) async throws {
    let compiled = try await ModelStore.compiledURL(for: Paths.model(fileName))
    print("\n\(fileName)   [computeUnits: \(unitsName)]")

    // A multifunction model needs one plan per function, selected with
    // MLModelConfiguration.functionName.
    let structure = try await MLModelStructure.load(contentsOf: compiled)
    var functionNames: [String?] = [nil]
    if case .program(let program) = structure, program.functions.count > 1 {
        functionNames = program.functions.keys.sorted()
    }

    var rows: [OpReport] = []
    for functionName in functionNames {
        let config = MLModelConfiguration()
        config.computeUnits = units
        config.functionName = functionName
        let plan: MLComputePlan
        do {
            plan = try await MLComputePlan.load(contentsOf: compiled, configuration: config)
        } catch {
            let label = functionName.map { "function \"\($0)\": " } ?? ""
            print("  \(label)no compute plan: \(error.localizedDescription)")
            continue
        }
        var functionRows: [OpReport] = []
        collect(plan.modelStructure, plan: plan, into: &functionRows)
        if let functionName {
            functionRows = functionRows.filter { $0.function == functionName }
        }
        rows += functionRows
    }

    guard !rows.isEmpty else { return }

    for function in Set(rows.map(\.function)).sorted() {
        let ops = rows.filter { $0.function == function }
        // Core ML gives no cost estimates for some models (for example ones
        // with flexible input shapes); then we rank by op count instead.
        let hasCost = ops.contains { $0.cost > 0 }
        let totalCost = max(ops.reduce(0) { $0 + $1.cost }, 1e-12)
        func share(_ group: [OpReport]) -> String {
            hasCost ? pct(group.reduce(0) { $0 + $1.cost } / totalCost) : "   n/a"
        }
        print("  function \"\(function)\": \(ops.count) ops")
        print("    device   ops   est. cost")
        for device in ["ANE", "GPU", "CPU"] {
            let onDevice = ops.filter { $0.preferred == device }
            guard !onDevice.isEmpty else { continue }
            print("    \(device)    \(String(format: "%5d", onDevice.count))   \(share(onDevice))")
        }

        // Ops that are not on the ANE, grouped by operator, with the reason:
        // either the ANE cannot run them, or Core ML chose another device.
        let offANE = ops.filter { $0.preferred != "ANE" }
        if units != .cpuOnly && units != .cpuAndGPU && !offANE.isEmpty {
            print("    not on the ANE:")
            let groups = Dictionary(grouping: offANE) { "\($0.op)|\($0.preferred)|\($0.supported.contains("ANE"))" }
            let byCost = groups.values.sorted {
                hasCost ? $0.reduce(0) { $0 + $1.cost } > $1.reduce(0) { $0 + $1.cost }
                        : $0.count > $1.count
            }
            for group in byCost.prefix(8) {
                let first = group[0]
                let why = first.supported.contains("ANE")
                    ? "ANE capable, \(first.preferred) preferred"
                    : "ANE unsupported, supported: \(first.supported.joined(separator: "/"))"
                print("      \(first.op.padding(toLength: 22, withPad: " ", startingAt: 0)) x\(String(format: "%-3d", group.count)) \(share(group))  -> \(first.preferred)  (\(why))")
            }
        }

        if verbose {
            print("    per-op detail:")
            for row in ops {
                print("      \(row.op.padding(toLength: 22, withPad: " ", startingAt: 0)) \(row.preferred)  supported \(row.supported.joined(separator: "/"))  cost \(String(format: "%.4f", row.cost))")
            }
        }
    }
}

// MARK: - command line

var args = Array(CommandLine.arguments.dropFirst())
let verbose = args.contains("--verbose")
args.removeAll { $0 == "--verbose" }

let unitChoices: [String: MLComputeUnits] = [
    "all": .all, "cpuOnly": .cpuOnly, "cpuAndGPU": .cpuAndGPU,
    "cpuAndNeuralEngine": .cpuAndNeuralEngine,
]
var unitsName = "all"
if let i = args.firstIndex(of: "--units") {
    guard i + 1 < args.count else {
        print("missing value for --units; choose from \(unitChoices.keys.sorted())")
        exit(1)
    }
    unitsName = args[i + 1]
    args.removeSubrange(i...(i + 1))
}
guard let units = unitChoices[unitsName] else {
    print("unknown --units \(unitsName); choose from \(unitChoices.keys.sorted())")
    exit(1)
}

let defaultModels = ["MiniLMEmbedding.mlpackage", "MiniLMEmbeddingFlexible.mlpackage",
                     "CharLM.mlpackage", "CancerClassifier.mlpackage", "TopicRouter.mlmodel"]
print("Compute devices on this Mac: \(MLComputeDevice.allComputeDevices.map(shortName))")
for name in args.isEmpty ? defaultModels : args {
    do {
        try await inspect(name, units: units, unitsName: unitsName, verbose: verbose)
    } catch {
        print("\n\(name): \(error)")
    }
}
