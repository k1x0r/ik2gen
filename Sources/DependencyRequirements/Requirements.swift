import XcodeEdit

public enum ProjectPlatform {
    case macOS
    case iOS
    case watchOS
    case tvOS
}

public class ProjectContext {
    
    public var frameworks : [PBXReferenceKey : PBXFileReference] = [:]
    public var spmFrameworks : [PBXReferenceKey : PBXFileReference] = [:]
    
    public var spmProject : XCProjectFile
    public var targets : [String : TargetProcessing]
    open var platform : ProjectPlatform
    public init(spmProject : XCProjectFile, targets : [String : TargetProcessing]) {
        self.platform = .macOS
        self.spmProject = spmProject
        self.targets = targets
    }
}

public class IosProjectContext : ProjectContext {
    
    public var mainProject : XCProjectFile
    
    public init(spmProject : XCProjectFile, mainProject : XCProjectFile, targets : [String : TargetProcessing]) {
        self.mainProject = mainProject
        super.init(spmProject: spmProject, targets: targets)
        self.platform = .iOS
    }
    
    
}


public protocol MainIosProjectRequirements : MainProjectRequirements {
        
    var iosContext : IosProjectContext { get }
    var externalGroup : PBXGroup { get }

    func addNewFrameworks() throws

    init(context : IosProjectContext)
}

public extension MainIosProjectRequirements {
    
    var context : ProjectContext {
        return iosContext
    }
    
}



public protocol MainSpmProjectRequirements : MainProjectRequirements {
    

    init(context : ProjectContext)

}

public extension MainProjectRequirements {
    
    @inline(__always)
    var targets : [Reference<PBXTarget>] {
        return context.spmProject.project.targets
    }
    
}

public protocol MainProjectRequirements : class {

// It's always needed to be implemented exactly like the line below
//  static let filePath : String = #file
    static var filePath : String { get }
    var context : ProjectContext { get }
    func mainBuildConfigurationLoop(config: XCBuildConfiguration) throws
    func mainBuildConfigurationDidFinish(configList : XCConfigurationList) throws

    func targetBuildConfigurationLoop(target: PBXTarget, list : XCConfigurationList) throws
    func targetBuildConfigurationDidFinish() throws

}

open class TargetProcessing {
    
    public let name : String
    public let extensionApiOnly : Bool
    public let prefferedLinkage : PBXProject.FrameworkType
    
    public typealias ProcessClosure = (TargetProcessing, PBXTarget) throws -> ()
    public typealias AddFrameworksClosure = (TargetProcessing, ProjectContext, PBXTarget) throws -> ()
    internal let process : ProcessClosure?
    internal let addFrameworks : AddFrameworksClosure?

    public init(name : String, extensionApiOnly : Bool = true, prefferedLinkage : PBXProject.FrameworkType = .embeddedBinary, process : ProcessClosure? = nil, addFrameworks : AddFrameworksClosure? = nil) {
        self.name = name
        self.extensionApiOnly = extensionApiOnly
        self.prefferedLinkage = prefferedLinkage
        self.process = process
        self.addFrameworks = addFrameworks
    }
    
    open func process(target: PBXTarget) throws {
        try process?(self, target)
    }
    open func addFrameworks(context: ProjectContext, target : PBXTarget) throws {
        try addFrameworks?(self, context, target)
    }
}

public protocol ModuleRequirements {

    static var targets : [TargetProcessing] { get }

}
