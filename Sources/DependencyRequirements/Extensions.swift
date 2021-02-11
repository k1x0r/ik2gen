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
    
    func frameworks(for targetName: String, to allObjects : AllObjects? = nil) throws -> [(TargetProcessing?, PBXFileReference)] {
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
                let guid : Guid
                if let name = fileRef.lastPathComponentOrName {
                    guid = Guid("FR-" + name.guidStyle)
                } else {
                    guid = Guid.random
                }
                let clone = fileRef.clone(to: allObjects ?? spmProject.project.allObjects, guid: guid)
                frameworks[key] = clone
                return (targets[name], clone)
            }
        }).sorted(by: {
            $0.1.lastPathComponentOrName < $1.1.lastPathComponentOrName
        })
    }
    
    /// To be used in module dependencies for system frameworks
    /// If create the reference directly the way as in this method must be used. Or better to create a new one here nearby.
    func spmFramework(with path : String, sourceTree : SourceTree = .relativeTo(.sdkRoot), type : PBXFileType = .framework) -> PBXFileReference {
        let reference = spmProject.project.newFrameworkReference(path: path, sourceTree: sourceTree, fileType: type)
        let key = reference.key
        if let framework = spmFrameworks[key] {
            return framework
        } else {
            spmFrameworks[key] = reference
            return reference
        }
    }
    
    func deletePackageDescriptionTargets()  {
        var guids = [Guid]()
        for targetRef in spmProject.project.targets {
            guard let target = targetRef.value, target.name.hasSuffix("PackageDescription") else {
                continue
            }
            guids.append(targetRef.id)
            if let buildConfigList = target.buildConfigurationList.value {
                for configRef in buildConfigList.buildConfigurations {
                    guids.append(configRef.id)
                }
            }
            for buildPhaseRef in target.buildPhases {
                guids.append(buildPhaseRef.id)
                guard let buildPhase = buildPhaseRef.value else {
                    continue
                }
                for buildFileRef in buildPhase.files {
                    guids.append(buildFileRef.id)
                }
            }
        }
        for guid in guids {
            spmProject.project.allObjects.objects.removeValue(forKey: guid)
        }
    }

}

public extension MainIosProjectRequirements {
    
    @inlinable
    func targetConfig(for target: String) -> XCBuildConfiguration? {
        return iosContext.spmProject.project.target(named: target)?.buildConfigurationList.value?.buildConfigurations.first?.value 
    }
    
    func copyFrameworks(from: String, to : [String], linkType : (TargetProcessing?, PBXFileReference)->(PBXProject.FrameworkType?)) throws {
        let frameworks = try context.frameworks(for: from, to: iosContext.mainProject.project.allObjects)
        
        let targets = to.compactMap { iosContext.mainProject.project.target(named: $0) }
        guard to.count == targets.count else {
            throw "Not all targets '\(to)' were found!".error()
        }
        for (target, framework) in frameworks {
            guard let fLinkType = linkType(target, framework) else {
                continue
            }
            let targetsWithType = targets.map { (fLinkType, $0) }
            try iosContext.mainProject.project.addFramework(framework: framework, targets: targetsWithType)
        }
        guard let originalConfig = targetConfig(for: from),
              let headerSearchPaths = originalConfig.buildSettings["HEADER_SEARCH_PATHS"] as? [String] else {
            throw "Couldn't find an original configuration".error()
        }
        let sourceHeaderSearchPaths = headerSearchPaths.map {
            $0.replacingOccurrences(of: "$(SRCROOT)/", with: "$(SRCROOT)/Dependencies/")
        }
        let otherSwiftFlags = try swiftFlags(from: from)
        do {
            for target in targets {
                target.updateBuildSettings([
                    "OTHER_SWIFT_FLAGS" : otherSwiftFlags,
                    "HEADER_SEARCH_PATHS" : sourceHeaderSearchPaths
                ])
            }
        } catch {
            print("Error with processing swift flags: \(error)")
        }
    }
    
    func swiftFlags(from target : String) throws -> String {
        guard let targetConfig = targetConfig(for: target) else {
            throw "Swift flags not found for dependencies project".error()
        }
        
        var swiftFlags : String
        if let stringValue = targetConfig.buildSettings["OTHER_SWIFT_FLAGS"] as? String {
            swiftFlags = stringValue
        } else if let array = targetConfig.buildSettings["OTHER_SWIFT_FLAGS"] as? [String] {
            swiftFlags = array.joined(separator: " ")
        } else {
            swiftFlags = ""
        }
        print("Swift flags: \(swiftFlags)")
        swiftFlags = swiftFlags.substring(fromFirst: " ") ?? swiftFlags
        
        let smParsedConfig = swiftFlags
            .replacingOccurrences(of: "-Xcc ", with: " ")
            .replacingOccurrences(of: "$(SRCROOT)/", with: "$(SRCROOT)/Dependencies/")
            .split(separator: " ")
        return "$(inherited) $(DEFINES) -Xcc " + smParsedConfig.joined(separator: " -Xcc ")
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
