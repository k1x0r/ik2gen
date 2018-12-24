//
// Extensions.swift
//
// Created by k1x
//


import Foundation
import XcodeEdit
import k2Utils

public struct ProjectPaths : Decodable {
    public let spmProject : String
    public let mainProject : String
    
    public static func parse(from path: String) throws -> ProjectPaths {
        return try PropertyListDecoder().decode(ProjectPaths.self, from: try Data(contentsOf: URL(fileURLWithPath: path)))
    }
}

public extension PBXReference {
    
    func nameWithoutExtension() throws -> String {
        if let name = name {
            return name
        }
        guard let path = path else {
            throw "No path found".error()
        }
        let lastPathComponenet = path.substring(fromLast: "/") ?? path
        return lastPathComponenet.substring(toLast: ".") ?? lastPathComponenet
    }
    
}

public extension ProjectContext {
    
    func frameworks(for targetName: String, allObjects : AllObjects? = nil) throws -> [(TargetProcessing?, PBXFileReference)] {
        guard let target = spmProject.project.target(named: targetName) else {
            throw "Target not found!".error()
        }
        let frameworksPhase = target.buildPhase(of: PBXFrameworksBuildPhase.self)
        
        return try frameworksPhase.files.compactMap({ buildFile -> (TargetProcessing?, PBXFileReference)? in
            guard let fileRef = buildFile.value?.fileRef?.value as? PBXFileReference, let path = fileRef.path else {
                return nil
            }
            let name = try fileRef.nameWithoutExtension()
            let key = fileRef.key
            if let framework = frameworks[key] {
                return (targets[name], framework)
            } else {
                let clone = fileRef.clone(to: allObjects ?? spmProject.project.allObjects)
                frameworks[key] = clone
                return (targets[name], clone)
            }
        })
    }
    
    /// To be used in module dependencies for system frameworks
    /// If create the reference directly the way as in this method must be used. Or better to create a new one here nearby.
    func spmFramework(with path : String, type : PBXFileType = .framework) -> PBXFileReference {
        let reference = spmProject.project.newFrameworkReference(path: path, fileType: type)
        let key = reference.key
        if let framework = spmFrameworks[key] {
            return framework
        } else {
            spmFrameworks[key] = reference
            return reference
        }
    }

}

public extension MainIosProjectRequirements {
    
    func copyFrameworks(from: String, to : String, linkType : (TargetProcessing?, PBXFileReference)->(PBXProject.FrameworkType)) throws {
        var frameworks = try self.context.frameworks(for: from, allObjects: iosContext.mainProject.project.allObjects)
        guard let mainTarget =  iosContext.mainProject.project.target(named: to) else {
            throw "Target '\(from)' is not found!".error()
        }
        for (target, framework) in frameworks {
            try iosContext.mainProject.project.addFramework(framework: framework, targets: [(linkType(target, framework), mainTarget)])
        }
        let (otherSwiftFlags, headerSearchPath) = try swiftFlags(from: from)
        mainTarget.updateBuildSettings([
            "OTHER_SWIFT_FLAGS" : otherSwiftFlags,
            "HEADER_SEARCH_PATHS" : headerSearchPath
        ])
    }
    
    func swiftFlags(from target : String) throws -> (flags: String, headerSearchPath: String) {
        guard let targetConfig = iosContext.spmProject.project.target(named: target)?.buildConfigurationList.value?.buildConfigurations.first?.value else {
            throw "Swift flags not found for dependencies project".error()
        }
        
        var swiftFlags : String
        if let stringValue = targetConfig.buildSettings["OTHER_SWIFT_FLAGS"] as? String {
            swiftFlags = stringValue
        } else if let array = targetConfig.buildSettings["OTHER_SWIFT_FLAGS"] as? [String] {
            swiftFlags = array.joined(separator: " ")
        } else {
            throw "Other swift flags not found!".error()
        }
        
        print("Swift flags: \(swiftFlags)")
        guard let newFlags = swiftFlags.substring(fromFirst: " ") else {
            throw "swiftFlags is nil!".error()
        }
        swiftFlags = newFlags
        
        let smParsedConfig = swiftFlags
            .replacingOccurrences(of: "-Xcc ", with: " ")
            .replacingOccurrences(of: "$(SRCROOT)/", with: "$(SRCROOT)/Dependencies/")
            .split(separator: " ")
        
        let headerSearchPath = smParsedConfig.map({ subStr in
            let str = subStr.description
            return "$" + (str.substring(fromFirst: "$")?.substring(toLast: "/") ?? "")
        }).joined(separator: " ")
        
        let flagsString = smParsedConfig.joined(separator: " -Xcc ")
        let otherSwiftFlags = "$(inherited) $(DEFINES) -Xcc " + flagsString
        
        return (otherSwiftFlags, headerSearchPath)
    }
    
}

public extension PBXTarget {
    
    func addRswift(project : PBXProject, shellAppend: String = "") throws {
        guard let (path, group) : (String, PBXGroup) = allObjects.objects.firstMap(where: { (key, value) in
            guard let group = value as? PBXGroup, group.name == self.name,
                  let path = group.path, !path.isEmpty else {
                return nil
            }
            return (path, group)
        }) else {
            throw "Could not find group for target '\(name)'".error()
        }
        let phase = buildPhase(of: PBXShellScriptBuildPhase.self) { (phases, ref) in
            phases.insert(ref, at: 0)
        }
        phase.inputPaths = [ "$TEMP_DIR/rswift-lastrun" ]
        phase.outputPaths = [ "$SRCROOT/\(path)/R.generated.swift" ]
        phase.shellScript = "# Type a script or drag a script file from your workspace to insert its path.\n\"$SRCROOT/../rswift\" generate \"$SRCROOT/\(path)/R.generated.swift\"" + shellAppend
        
        if !group.fileRefs.contains(where: { $0.value?.path?.contains("R.generated.swift") ?? false }) {
            try project.addSourceFiles(files: [
                project.newFileReference(name: "R.generated.swift", path: "R.generated.swift", sourceTree: .group),
            ], group: allObjects.createReference(value: group), targets: [self])
        }
        
    }
    
}

public extension ModuleRequirements {

    static var targetsDictionary : [String : TargetProcessing] {
        return Dictionary(uniqueKeysWithValues: Self.targets.map({ ($0.name, $0) }) )
    }
}

public func shell(launchPath: String, arguments: [String], fromDirectory : String) -> (returnCode: Int32, output: String?) {
    let task = Process()
    task.launchPath = launchPath
    task.arguments = arguments
    task.currentDirectoryPath = fromDirectory
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()
    
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    task.waitUntilExit()
    
    return (task.terminationStatus, output)
}
