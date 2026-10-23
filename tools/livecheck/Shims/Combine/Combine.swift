// Minimal stand-in for Apple's Combine, so the Foundation-only parts of
// the app can be compiled and unit-tested on Linux.
import Foundation

public protocol ObservableObject: AnyObject {
    var objectWillChange: ObservableObjectPublisher { get }
}

public final class ObservableObjectPublisher {
    public init() {}
    public func send() {}
}

extension ObservableObject {
    public var objectWillChange: ObservableObjectPublisher { ObservableObjectPublisher() }
}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public var projectedValue: Published<Value> { self }
}
