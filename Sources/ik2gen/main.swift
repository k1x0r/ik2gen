import k2Utils
import XcodeEdit
import Foundation
import DependencyRequirements

do {

let currentDirectory = URL(fileURLWithPath: MainProject.filePath).deletingLastPathComponent().path.appendIfNotEnds("/")

let paths = try ProjectPaths.parse(from: currentDirectory + ".ik2proj")
    
let modules = i2genModules.reduce(into: [String : TargetProcessing]()) { (res, next) in
    res.merge(next.targetsDictionary, uniquingKeysWith: { $1 })
}

let spmUrl = URL(fileURLWithPath: currentDirectory + paths.spmProject)
let ret = shell(launchPath: "/usr/bin/swift", arguments: ["package", "generate-xcodeproj"], fromDirectory: spmUrl.deletingLastPathComponent().path)
print("\(ret.output ?? "<no output from terminal>")\nGenerate XcodeProj returnCode: \(ret.returnCode) ")
guard ret.returnCode == 0 else {
    fatalError("Generate-xcodeproj return code is not 0")
}
let ik2project : MainProjectRequirements
if let Class = MainProject.self as? MainIosProjectRequirements.Type {
    let spmProject = try XCProjectFile(xcodeprojURL: spmUrl)
    let mainProject = try XCProjectFile(xcodeprojURL: URL(fileURLWithPath: currentDirectory + paths.mainProject))
    ik2project = Class.init(context: IosProjectContext(spmProject : spmProject, mainProject : mainProject, targets: modules))
} else if let Class = MainProject.self as? MainSpmProjectRequirements.Type {
    let spmProject = try XCProjectFile(xcodeprojURL: spmUrl)
    ik2project = Class.init(context: ProjectContext(spmProject : spmProject, targets: modules))
} else {
    fatalError("No supported types found")
}
    
let dependenciesProject = ik2project.context.spmProject
    
guard let configurations = dependenciesProject.project.buildConfigurationList.value else {
    fatalError("No build configurations!")
}
print("Using Modules : \(i2genModules)")
for ref in configurations.buildConfigurations {
    guard let config = ref.value else {
        continue
    }
    if ik2project is MainIosProjectRequirements {
        config.buildSettings = config.buildSettings.merging([
            "SDKROOT" : "iphoneos",
            "CURRENT_PROJECT_VERSION" : "1.0",
            "ENABLE_BITCODE" : "YES",
            "IPHONEOS_DEPLOYMENT_TARGET" : "12.2",
            "DEBUG_INFORMATION_FORMAT" : config.name == "Release" ? "dwarf-with-dsym" : "dwarf"
        ]) { $1 }
    }
    try ik2project.mainBuildConfigurationLoop(config: config)
}
try ik2project.mainBuildConfigurationDidFinish(configList: configurations)


print("Groups: \(dependenciesProject.project.groups)")
try dependenciesProject.addXibsAndStoryboards()
    
for ref in dependenciesProject.project.targets {
    guard let target = ref.value, let buildConfig = target.buildConfigurationList.value, !target.name.hasSuffix("PackageDescription") else {
        continue
    }
    let module = modules[target.name]
    for ref in buildConfig.buildConfigurations {
        guard let bConfig = ref.value else {
            continue
        }
        bConfig.buildSettings.add(for: "FRAMEWORK_SEARCH_PATHS", values: ["$(SDKROOT)/usr/lib"])
        if ik2project is MainIosProjectRequirements {
            bConfig.buildSettings = bConfig.buildSettings.merging([
                "PRODUCT_BUNDLE_IDENTIFIER" : "com.k1x.\(target.name)",
                "PRODUCT_NAME" : target.name,
                "PRODUCT_MODULE_NAME" : target.name,
                "APPLICATION_EXTENSION_API_ONLY" : module?.extensionApiOnly ?? true ? "YES" : "NO"
            ]) { $1 }
        }
        
    }
    try module?.process(target: target)
    try ik2project.targetBuildConfigurationLoop(target: target, list: buildConfig)

}
try ik2project.targetBuildConfigurationDidFinish()

    


/// Ok, here is a problem with the same framework ober multiple targets
/// We need to add only single instance of jsCore to two targets in completely separate packages
/// Maybe to have a single holder of extenal framework references?
/// Something like class { refs : [String : FrameworkRef] }
/// But in this case we'll have to look by name
/// Or maybe Set<FrameworkRef>
/// So we'll get unique references. And we'll be able to look by any param we want
/// The question remains about some context that will be global or local based on whatever requirements

for (targetName, module) in modules {
    guard let target = ik2project.context.spmProject.project.target(named: targetName) else {
        continue
    }
    try module.addFrameworks(context: ik2project.context, target: target)
}

guard let frameworksGroupRef = dependenciesProject.project.mainGroup.value?.group(with: "ik2genFrameworks"),
      let frameworksGroup = frameworksGroupRef.value else {
        fatalError("No external group!")
}
let spmFrameworks = ik2project.context.spmFrameworks.map({ dependenciesProject.project.allObjects.createReference(value: $1 as PBXReference) })
frameworksGroup.children.append(contentsOf: spmFrameworks)
    
try dependenciesProject.write(format: .openStep)

guard let iosProject = ik2project as? MainIosProjectRequirements else {
    print("Success")
    exit(0)
}
    
// as a var
let mainProject = iosProject.iosContext.mainProject // try XCProjectFile(xcodeprojURL: URL(fileURLWithPath: "/Workspace/RClaymore/RClaymore.xcodeproj"))

// as a var

let externalGroupName = iosProject.externalGroupName
    
guard let externalGroupRef = mainProject.project.mainGroup.value?.group(with: externalGroupName),
      let externalGroup = externalGroupRef.value else {
    fatalError("No external group!")
}

mainProject.project.removeFrameworks(frameworks: externalGroup.frameworks, groups: [externalGroup])
    
/// here we need preffered linkage of framework and linkage to the target...
/// for example for XMLHttpRequest for target RClaymore is Both and for Share is library. For everything else for RClaymore is embeddedBinary, for Share is library...
/// Ok... resolved, just send a tuple with prefferedLinkageType and Framework reference
/// also we need to know is it safe or not to link the framework and filter that
/// That's why we should pass some Module object along with framework reference...
/// But what we need to do in case if it's empty....
/// Provide optional value with default value should be ok in case if there's no other places where it's used
/// And it'll provide additional benefit for end user to determine default values
/// Summarize: providex [(Module?, PBXFileReference)]
try iosProject.addNewFrameworks()
    
let mainFrameworks = ik2project.context.frameworks.map({ mainProject.project.allObjects.createReference(value: $1 as PBXReference) })
externalGroup.children.append(contentsOf: mainFrameworks)


try mainProject.write(format: .openStep)

} catch {
    print("Error \(error)")
}
