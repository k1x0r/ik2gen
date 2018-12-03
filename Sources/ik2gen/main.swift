import k2Utils
import XcodeEdit
import Foundation

do {

let dependenciesProject = try XCProjectFile(xcodeprojURL: URL(fileURLWithPath: "/Workspace/RClaymore/Dependencies/Dependencies.xcodeproj"))

guard let configurations = dependenciesProject.project.buildConfigurationList.value else {
    fatalError("No build configurations!")
}

for config in configurations.buildConfigurations {
    guard let val = config.value else {
        continue
    }
    val.buildSettings["SDKROOT"] = "iphoneos"

}

guard let debug = configurations.configuration(named: "Debug") else{
    fatalError("No debug configuration found!")
}
let debugLan = try debug.copy(with: Guid.random, name: "DebugLan")
configurations.addBuildConfiguration(debugLan)

print("Groups: \(dependenciesProject.project.groups)")
try dependenciesProject.addXibsAndStoryboards()
    
for ref in dependenciesProject.project.targets {
    guard let target = ref.value, let buildConfig = target.buildConfigurationList.value else {
        continue
    }
    for ref in buildConfig.buildConfigurations {
        guard let bConfig = ref.value else {
            continue
        }

        bConfig.buildSettings.add(for: "FRAMEWORK_SEARCH_PATHS", values: ["$(SDKROOT)/usr/lib"])
        bConfig.buildSettings = bConfig.buildSettings.merging([
            "PRODUCT_BUNDLE_IDENTIFIER" : "com.k1x.\(target.name)",
            "PRODUCT_NAME" : target.name,
            "PRODUCT_MODULE_NAME" : target.name,
            //// Maybe to common settings...
            "CURRENT_PROJECT_VERSION" : "1.0",
            "ENABLE_BITCODE" : "YES",
            "IPHONEOS_DEPLOYMENT_TARGET" : "9.0",
            "DEBUG_INFORMATION_FORMAT" : bConfig.name == "Release" ? "dwarf-with-dsym" : "dwarf"
        ]) { $1 }
        
    }
    
    if let debug = buildConfig.configuration(named: "Debug") {
        let debugLan = try debug.copy(with: Guid.random, name: "DebugLan")
        buildConfig.addBuildConfiguration(debugLan)
    }
    
}
    
/// TO BE PUT IN LIB
dependenciesProject.project.target(named: "COpenSSL")?.setBuildSetting(key: "WARNING_CFLAGS", value: "-w")
///

    
let jsCore = dependenciesProject.project.newFrameworkReference(path: "System/Library/Frameworks/JavaScriptCore.framework")
try dependenciesProject.project.addFramework(framework: jsCore, frameworkType: .library, targetNames: ["XMLHTTPRequest", "RClaymoreShared"])

let mainProject = try XCProjectFile(xcodeprojURL: URL(fileURLWithPath: "/Workspace/RClaymore/RClaymore.xcodeproj"))
guard let externalRef = mainProject.project.mainGroup.value?.subGroups.first(where: { $0.value?.path == "External" }), let externalGroup = externalRef.value else {
    fatalError("External Group not found!")
}
guard let mainTarget =  mainProject.project.target(named: "RClaymore") else {
    fatalError("Main Target not found!")
}

mainProject.project.removeFrameworks(frameworks: externalGroup.frameworks, groups: [externalGroup])
for ref in dependenciesProject.project.targets {
    guard let target = ref.value, !target.name.hasSuffix("PackageDescription") else {
        continue
    }
    let framework = mainProject.project.newFrameworkReference(path: "\(target.name).framework", sourceTree: .relativeTo(.buildProductsDir))
    try mainProject.project.addFramework(framework: framework, frameworkType: target.name == "XMLHTTPRequest" ? .both : .embeddedBinary, group: externalRef, targets: [mainTarget])
}

guard let targetConfig = dependenciesProject.project.target(named: "Dependencies")?.buildConfigurationList.value?.buildConfigurations.first?.value else {
    fatalError("Swift flags not found for dependencies project")
}

var swiftFlags : String
if let stringValue = targetConfig.buildSettings["OTHER_SWIFT_FLAGS"] as? String {
    swiftFlags = stringValue
} else if let array = targetConfig.buildSettings["OTHER_SWIFT_FLAGS"] as? [String] {
    swiftFlags = array.joined(separator: " ")
} else {
    fatalError("Other swift flags not found!")
}

print("Swift flags: \(swiftFlags)")
guard let newFlags = swiftFlags.substring(fromFirst: " ") else {
    fatalError("swiftFlags is nil!")
}
swiftFlags = newFlags

let smParsedConfig = swiftFlags
    .replacingOccurrences(of: "-Xcc ", with: " ")
    .replacingOccurrences(of: "$(SRCROOT)/", with: "$(SRCROOT)/Dependencies/")
    .split(separator: " ")
//                .filter({ !$0.contains("COpenSSL") })

let headerSearchPath = smParsedConfig.map({ subStr in
    let str = subStr.description
    return "$" + (str.substring(fromFirst: "$")?.substring(toLast: "/") ?? "")
}).joined(separator: " ")

let flagsString = smParsedConfig.joined(separator: " -Xcc ")
let otherSwiftFlags = "$(inherited) $(DEFINES) -Xcc " + flagsString

print("SM Swift flags: \(otherSwiftFlags)")

guard let switchMapsConfigs = mainTarget.buildConfigurationList.value?.buildConfigurations else {
    fatalError("No Configurations")
}
for ref in switchMapsConfigs {
    guard let config = ref.value else {
        continue
    }
    config.buildSettings["OTHER_SWIFT_FLAGS"] = otherSwiftFlags
    config.buildSettings["HEADER_SEARCH_PATHS"] = headerSearchPath
}
    
try dependenciesProject.write(format: .openStep)
try mainProject.write(format: .openStep)

} catch {
    print("Error \(error)")
}
