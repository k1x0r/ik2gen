
public struct DependencyRequirements {
    public var hello = "World"
}

public protocol ModuleRequirements : class {
    func foo()
}

public protocol MainProjectRequirements : class {
}
