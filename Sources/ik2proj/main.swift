import Foundation
import XcodeEdit
import DependencyRequirements

do {
    //// The project from which Package.swift is retrieved
    // current dir + path to project. Let's call this SPM project. Maybe from file .ik2proj because it's permanent. If the file is not found then we throw an error and display error message
    
    // remove Sources/ik2proj/main.swift
    let ik2genRootDir = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .path.appendIfNotEnds("/")
    print("Root directory: \(ik2genRootDir)")
    guard let targetDirectory =  ProcessInfo.processInfo.environment["TARGET_DIR"]?.appendIfNotEnds("/") else {
        fatalError("Could not get current directory")
    }
    print("Target directory: \(targetDirectory)")

//    let currentDirectory = "/Workspace/RClaymore/"
//    let ik2genRootDir = "/Workspace/ik2gen/"
    let paths = try ProjectPaths.parse(from: targetDirectory + ".ik2proj")
    
    let spmUrl = URL(fileURLWithPath: targetDirectory + paths.spmProject)
    let ret = shell(launchPath: "/usr/bin/swift", arguments: ["package", "generate-xcodeproj"], fromDirectory: spmUrl.deletingLastPathComponent().path)
    print("\(ret.output ?? "<no output from terminal>")\nGenerate XcodeProj returnCode: \(ret.returnCode) ")
    guard ret.returnCode == 0 else {
        fatalError("Generate-xcodeproj return code is not 0")
    }
    
    let dependenciesProject = try XCProjectFile(xcodeprojURL: URL(fileURLWithPath: targetDirectory + paths.spmProject))

    /// current dir
    let copyProjectUrl = URL(fileURLWithPath: targetDirectory + "ik2gen.xcodeproj")
    
    /// from enviroment variables or script...
    let ik2genProjectUrl = URL(fileURLWithPath: ik2genRootDir + "ik2gen.xcodeproj")
    /// All the variables which are required
    
    
    // in case if fails it means there wasn't a file before. so we skip
    try? FileManager.default.removeItem(atPath: copyProjectUrl.path)
    let ik2genDir = try FileManager.default.copyItem(atPath: ik2genProjectUrl.path, toPath: copyProjectUrl.path)

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
          let productsGroup = ik2genProject.project.mainGroup.value?.subGroups.first(where: { $0.value?.name == "Products" }) else {
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
    
    let genreatedContents = """
/// 🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
/// 🚨🚨  DO NOT EDIT THIS FILE MANUALLY, IT'S GENERATED AUTOMATICALLY BY I2GEN 🚨🚨
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
