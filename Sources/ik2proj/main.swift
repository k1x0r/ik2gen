import Foundation
import XcodeEdit
import DependencyRequirements

func getEnvironmentVar(_ name: String) -> String? {
    guard let rawValue = getenv(name) else { return nil }
    return String(utf8String: rawValue)
}

do {
    // remove Sources/ik2proj/main.swift
    // print("env \(ProcessInfo.processInfo.environment)")
    guard let ik2genRootDir = ProcessInfo.processInfo.environment["INSTALL_DIR"]?.appendIfNotEnds("/") else {
        fatalError("Couldn't get ik2gen install directory")
    }
    guard let currentDirectory = ProcessInfo.processInfo.environment["CURRENT_DIR"]?.appendIfNotEnds("/") else {
        fatalError("Could not get current directory")
    }

    let paths = try ProjectPaths.parse(from: currentDirectory + ".ik2proj")
    
    let spmUrl = URL(fileURLWithPath: currentDirectory + paths.spmProject)
    let targetDirectory = spmUrl.deletingLastPathComponent().path.appendIfNotEnds("/")
    print("Target directory: \(targetDirectory)")

//    let ret = shell(launchPath: "/usr/bin/swift", arguments: ["package", "generate-xcodeproj"], fromDirectory: targetDirectory)
//    print("\(ret.output ?? "<no output from terminal>")\nGenerate XcodeProj returnCode: \(ret.returnCode) ")
//    guard ret.returnCode == 0 else {
//        fatalError("Generate-xcodeproj return code is not 0")
//    }
    
    let dependenciesProject = try XCProjectFile(xcodeprojURL: URL(fileURLWithPath: currentDirectory + paths.spmProject))

    /// current dir
    let copyProjectUrl = URL(fileURLWithPath: targetDirectory + "ik2gen.xcodeproj")
    
    /// from enviroment variables or script...
    let ik2genProjectUrl = URL(fileURLWithPath: ik2genRootDir + "ik2gen.xcodeproj")
    /// All the variables which are required
    
    
    // in case if fails it means there wasn't a file before. so we skip
    try? FileManager.default.removeItem(atPath: copyProjectUrl.path)
    do {
        try FileManager.default.copyItem(atPath: ik2genProjectUrl.path, toPath: copyProjectUrl.path)
    } catch {
        print("Copying error: \(error)")
    }
        
    let ik2genProject = try XCProjectFile(xcodeprojURL: copyProjectUrl)
    
    let ik2genDependencies = dependenciesProject.project.allObjects.objects.compactMap({ (key: Guid, value: PBXObject) -> URL? in
        guard let fileRef = value as? PBXReference, fileRef.name == "Package.swift", let path = fileRef.path else {
            return nil
        }
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    })
    let existingFiles = ik2genDependencies.compactMap({ inUrl -> URL? in
        let url = inUrl.appendingPathComponent("ik2Package.swift")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    })
    
    let ik2generated = PBXGroup(emptyObjectWithId: Guid.random, allObjects: ik2genProject.project.allObjects)
    ik2generated.path = ""
    ik2generated.name = "ik2generated"
    ik2generated.sourceTree = .relativeTo(.sourceRoot)
    let ik2generatedRef = ik2genProject.project.allObjects.createReference(value: ik2generated)
    ik2genProject.project.mainGroup.value?.addChildGroup(ik2generatedRef)
    
    guard let templateTarget = ik2genProject.project.target(named: "ProjectTemplate") as? PBXNativeTarget,
          let ik2genTarget = ik2genProject.project.target(named: "ik2gen") as? PBXNativeTarget,
          let productsGroup = ik2genProject.project.mainGroup.value?.subGroups.first(where: { $0.value?.name == "Products" })?.value else {
        fatalError("ProjectTemplate target not found")
    }
    let appendPath = ik2genProjectUrl.deletingLastPathComponent().path.appendIfNotEnds("/")
    for (key, obj) in ik2genProject.project.allObjects.objects {
        guard let group = obj as? PBXGroup, group.sourceTree == .relativeTo(.sourceRoot) else {
            continue
        }
        if let path = group.path {
            group.path = appendPath + path
        }
        group.sourceTree = .absolute
        
    }
    
    var moduleNames = [String]()
    for (i, url) in existingFiles.enumerated() {
        let pbxRef = ik2genProject.project.newFileReference(name: "ik2Package.swift", path: url.path, sourceTree: .absolute)
        
        let target = try templateTarget.deepClone()
        let name = "Module\(i)"
        moduleNames.append(name)
        target.name = name
        target.productName = name
        target.updateBuildSettings([
            "TARGET_NAME" : name,
            "PRODUCT_BUNDLE_IDENTIFIER" : "ik2gen.\(name)"
        ])
        target.buildPhase(of: PBXSourcesBuildPhase.self).files = []
        try ik2genProject.project.addSourceFiles(files: [pbxRef], group: ik2generatedRef, targets: [target])
        let targetRef = ik2genProject.addReference(value: target)
        ik2genProject.project.targets.append(Reference(allObjects: targetRef.allObjects, id: targetRef.id))
        
        let targetProxy = PBXTargetDependency(emptyObjectWithId: Guid.random, allObjects: ik2genTarget.allObjects)
        targetProxy.targetProxy = Reference(allObjects: targetRef.allObjects, id: targetRef.id)
        ik2genTarget.dependencies.append(ik2genTarget.allObjects.createReference(value: targetProxy))
        
        let moduleFramework = ik2genProject.project.newFrameworkReference(path: name + ".framework", sourceTree: .relativeTo(.buildProductsDir))
        try ik2genProject.project.addFramework(framework: moduleFramework, group: productsGroup, targets: [(.library, ik2genTarget)])
    }
// Code Template
    let genreatedContents = """
/// 🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
/// 🚨🚨  DO NOT EDIT THIS FILE MANUALLY, IT'S GENERATED AUTOMATICALLY BY IK2GEN 🚨🚨
/// 🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨

\(moduleNames.map({ "import " + $0 }).joined(separator: "\n"))
import DependencyRequirements

let i2genModules : [ModuleRequirements.Type] = [\(moduleNames.map({ $0 + ".Module.self" }).joined(separator: ", "))]
"""
    let targetProjectPath = copyProjectUrl.deletingLastPathComponent().path.appendIfNotEnds("/")
    let generatedUrl = URL(fileURLWithPath: targetProjectPath + "ik2generated.swift")
    try genreatedContents.write(to: generatedUrl, atomically: true, encoding: .utf8)
    
    try ik2genProject.project.addSourceFiles(files: [
        ik2genProject.project.newFileReference(name: "ik2Project.swift", path: targetProjectPath + "ik2Project.swift", sourceTree: .absolute),
        ik2genProject.project.newFileReference(name: generatedUrl.lastPathComponent, path: generatedUrl.path, sourceTree: .absolute)
    ], group: ik2generatedRef, targets: [ik2genTarget])

    
    try ik2genProject.write(format: .openStep)
    
    print("Packages: \(ik2genDependencies)")
    print("Existing files: \(existingFiles)")

    
} catch {
    print("Caught error: \(error)")
}
