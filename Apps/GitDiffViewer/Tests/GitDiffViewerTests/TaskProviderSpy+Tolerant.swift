import AemiTesting

extension TaskProviderSpy {
    /// The failure bound every suite's waits use. A passing wait returns the moment its tasks finish, so the bound
    /// only decides how long a genuinely stuck test takes to fail; one second failed spuriously while parallel builds
    /// saturated the machine.
    static let failureBound: Duration = .seconds(15)

    /// A spy whose waits fail only after ``failureBound``, reporting the caller as its creation site.
    static func tolerant(file: StaticString = #fileID, function: String = #function, line: UInt = #line)
        -> TaskProviderSpy
    {
        TaskProviderSpy(defaultTimeout: failureBound, file: file, function: function, line: line)
    }
}
