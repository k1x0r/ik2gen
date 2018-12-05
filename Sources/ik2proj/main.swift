import Foundation
import XcodeEdit

do {
    let dependenciesProject = try XCProjectFile(xcodeprojURL: URL(fileURLWithPath: "/Workspace/RClaymore/Dependencies/Dependencies.xcodeproj"))

    let copyProjectUrl = URL(fileURLWithPath: "/Workspace/RClaymore/ik2gen.xcodeproj")
    let ik2genProjectUrl = URL(fileURLWithPath: "/Workspace/ik2gen/ik2gen.xcodeproj")
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
    
    for (i, url) in existingFiles.enumerated() {
        let fileReference = PBXFileReference(emptyObjectWithId: Guid.random, allObjects: ik2genProject.project.allObjects)
        fileReference.path = url.path
        fileReference.name = "ik2Package.swift"
        fileReference.sourceTree = .absolute
        let ref = ik2genProject.project.allObjects.createReference(value: fileReference)
        let pbxRef : Reference<PBXReference> = Reference(allObjects: fileReference.allObjects, id: ref.id)
        
        let target = try templateTarget.deepClone()
        let name = "Module\(i)"
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
    try ik2genProject.write(format: .openStep)
    
    print("Packages: \(ik2genDependencies)")
    print("Existing files: \(existingFiles)")

    
} catch {
    print("Caught error: \(error)")
}
