import Foundation
import XcodeEdit

do {
    let dependenciesProject = try XCProjectFile(xcodeprojURL: URL(fileURLWithPath: "/Workspace/RClaymore/Dependencies/Dependencies.xcodeproj"))

    let copyProjectPath = "/Workspace/ik2gen/ik2gen-RClaymore.xcodeproj"
    
    try? FileManager.default.removeItem(atPath: copyProjectPath)
    let ik2genDir = try FileManager.default.copyItem(atPath: "/Workspace/ik2gen/ik2gen.xcodeproj", toPath: copyProjectPath)

    let ik2genProject = try XCProjectFile(xcodeprojURL: URL(fileURLWithPath: copyProjectPath))
    
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
    
    let newReferences : [Reference<PBXReference>] = existingFiles.map({
        let fileReference = PBXFileReference(emptyObjectWithId: Guid.random, allObjects: ik2genProject.project.allObjects)
        fileReference.path = $0.path
        fileReference.name = "ik2Package.swift"
        fileReference.sourceTree = .absolute
        let ref = ik2genProject.project.allObjects.createReference(value: fileReference)
        return Reference(allObjects: fileReference.allObjects, id: ref.id)
    })
    // ClassName should be resolved as in js files

    guard let ik2genTarget = ik2genProject.project.target(named: "ik2gen") else {
        fatalError("ik2gen target not found")
    }
    try ik2genProject.project.addSourceFiles(files: newReferences, group: ik2generatedRef, targets: [ik2genTarget])
    
    try ik2genProject.write(format: .openStep)
    
    print("Packages: \(ik2genDependencies)")
    print("Existing files: \(existingFiles)")

    
} catch {
    print("Caught error: \(error)")
}
