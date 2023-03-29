//
// Extensions.swift
//
// Created by k1x
//



import Foundation
import XcodeEdit
import k2Utils

public extension String {

    func swiftImportHeaderPath(module : String) -> String {
        return "$(OBJROOT)/\(self).build/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)/\(module).build/DerivedSources"
    }

}

public struct ProjectPaths : Decodable {
    public let spmProject : String
    public let mainProject : String
    
    public static func parse(from path: String) throws -> ProjectPaths {
        return try PropertyListDecoder().decode(ProjectPaths.self, from: try Data(contentsOf: URL(fileURLWithPath: path)))
    }
}

public extension PBXProject {
    
    func group(where whereClosure : (PBXGroup) -> Bool) -> PBXGroup? {
        for (_, obj) in allObjects.objects {
            if let group = obj as? PBXGroup, whereClosure(group) {
               return group
            }
        }
        return nil
    }
    
    func loopBuildConfigurations(for targetName : String, element : (XCBuildConfiguration)->()) {
        guard let configList = target(named: targetName)?.buildConfigurationList.value else {
            return
        }
        for buildConfigRef in configList.buildConfigurations {
            guard let buildConfig = buildConfigRef.value else {
                return
            }
            element(buildConfig)
        }
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
                    guid = Guid("FREF-" + name.guidStyle)
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
            for buildPhaseRef in target.buildPhases {
                guard let buildPhase = buildPhaseRef.value else {
                    continue
                }
                buildPhase.files = buildPhase.files.filter { buildFileRef -> Bool in
                    guard let fileRef = buildFileRef.value?.fileRef?.value, fileRef.lastPathComponentOrName == "Package.swift" else {
                        return true
                    }
                    guids.append(buildFileRef.id)
//                    guids.append(fileRef.id)
                    return false
                }
                buildPhase.applyChanges()
                
            }
        }
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
            target.deleteBuildPhases(where: { _ in true })
        }
        for guid in guids {
            spmProject.project.allObjects.objects.removeValue(forKey: guid)
        }
        spmProject.project.targets = spmProject.project.targets.filter {
            !$0.id.value.hasSuffix("PackageDescription")
        }
        spmProject.project.applyChanges()
    }

}

public extension MainIosProjectRequirements {
    
    @inlinable
    func targetConfig(for target: String) -> XCBuildConfiguration? {
        return iosContext.spmProject.project.target(named: target)?.buildConfigurationList.value?.buildConfigurations.first?.value 
    }
   
    func removeLibraryLinkage(include : (PBXTarget)->Bool) {
        var guids = [Guid]()
        for targetRef in context.spmProject.project.targets {
            guard let target = targetRef.value,
                  include(target),
                  let frameworksPhase = target.buildPhaseOptional(of: PBXFrameworksBuildPhase.self) else {
                continue
            }
            for bfileRef in frameworksPhase.files {
                guids.append(bfileRef.id)
            }
            frameworksPhase.files = []
        }
        for guid in guids {
            context.spmProject.project.allObjects.objects.removeValue(forKey: guid)
        }
    }
    
    func sortExternalGroup() {
        externalGroup.children.sort(by: {
            $0.value?.lastPathComponentOrName < $1.value?.lastPathComponentOrName
        })
        externalGroup.applyChanges()
    }
    
    func copyBuildSettings(from: String, to : [String]) throws {
        guard let originalConfig = targetConfig(for: from),
              let headerSearchPaths = originalConfig.buildSettings["HEADER_SEARCH_PATHS"] as? [String] else {
            throw "Couldn't find an original configuration".error()
        }
        let targets = to.compactMap { iosContext.mainProject.project.target(named: $0) }
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
    
    func addSingleFramework(name: String, linkType : PBXProject.FrameworkType, from: String, to : [String]) throws {
        let allObjects = iosContext.mainProject.project.allObjects
        
        let frameworkObj = PBXFileReference(emptyObjectWithId: Guid("FREF-C-" + name.guidStyle), allObjects: allObjects)
//        frameworkObj.name = name
        frameworkObj.path = name
        frameworkObj.lastKnownFileType = .archive
        frameworkObj.sourceTree = .relativeTo(.buildProductsDir)
        let ref = allObjects.createReference(value: frameworkObj)
        let targets = to.compactMap { iosContext.mainProject.project.target(named: $0) }
        guard to.count == targets.count else {
            throw "Not all targets '\(to)' were found!".error()
        }
        
        try iosContext.mainProject.project.addFramework(framework: frameworkObj, group: externalGroup, targets: targets.map { (linkType, $0) })
        sortExternalGroup()
        try copyBuildSettings(from: from, to: to)
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
            try iosContext.mainProject.project.addFramework(framework: framework, group: externalGroup, targets: targetsWithType)
        } 
        sortExternalGroup()
        try copyBuildSettings(from: from, to: to)
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

    func addRswift(project : PBXProject, group : PBXGroup, path: String, shellScript: ((String)->String)? = nil, destTarget : PBXTarget? = nil) throws {
        let name = path.lastPathComponent
        let namePhase = "[ik2gen-R.swift] Generate \(name)"
        let phase : PBXShellScriptBuildPhase = buildPhase(where: {
            $0.name == namePhase
        }, append: { phases, phase in
            phases.insert(phase, at: 0)
        })
        phase.name = namePhase

        phase.inputPaths = [ "$TEMP_DIR/rswift-lastrun" ]
        phase.outputPaths = [ "$SRCROOT/\(path)" ]
        phase.shellScript = shellScript?(path) ?? """
        if [ "${ACTION}" != "indexbuild" ]; then
        \"$SRCROOT/../rswift\" generate \"$SRCROOT/\(path)\"
        fi
        """
        
        group.children = group.children.filter {
            !($0.value?.path?.contains(name) ?? false)
        }
        try project.addSourceFiles(files: [
            project.newFileReference(name: name, path: path, sourceTree: .relativeTo(.sourceRoot)),
        ], group: allObjects.createReference(value: group), targets: name.hasSuffix(".h") ? [] : [destTarget ?? self])
        
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
