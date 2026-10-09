import Testing
import Foundation
@testable import DICOMCore

@Suite("WindowSettings Tests")
struct WindowSettingsTests {
    
    // MARK: - Initialization Tests
    
    @Test("Create window settings")
    func testCreateWindowSettings() {
        let window = WindowSettings(center: 40.0, width: 400.0)
        
        #expect(window.center == 40.0)
        #expect(window.width == 400.0)
        #expect(window.explanation == nil)
        #expect(window.function == .linear)
    }
    
    @Test("Create window settings with explanation")
    func testCreateWindowSettingsWithExplanation() {
        let window = WindowSettings(center: 50.0, width: 350.0, explanation: "SOFT TISSUE")
        
        #expect(window.explanation == "SOFT TISSUE")
    }
    
    @Test("Create window settings with sigmoid function")
    func testCreateWindowSettingsWithSigmoid() {
        let window = WindowSettings(center: 100.0, width: 200.0, function: .sigmoid)
        
        #expect(window.function == .sigmoid)
    }
    
    @Test("Width minimum is 1")
    func testWidthMinimumIsOne() {
        let window = WindowSettings(center: 0.0, width: 0.5)
        
        #expect(window.width == 1.0)
    }

    /// PS3.3 C.11.2.1.3.1 / C.11.2.1.3.2: SIGMOID and LINEAR_EXACT only require
    /// Window Width > 0; the LINEAR minimum of 1 (C.11.2.1.2.1) does not apply (D64).
    @Test("SIGMOID and LINEAR_EXACT keep widths between 0 and 1")
    func testNonLinearFunctionsKeepSubUnitWidths() {
        #expect(WindowSettings(center: 0.5, width: 0.25, function: .linearExact).width == 0.25)
        #expect(WindowSettings(center: 0.5, width: 0.25, function: .sigmoid).width == 0.25)
        #expect(WindowSettings(center: 0.5, width: 0.25, function: .linear).width == 1.0)
        // Forbidden for every function: applied as 1.
        #expect(WindowSettings(center: 0, width: 0, function: .linearExact).width == 1.0)
        #expect(WindowSettings(center: 0, width: -3, function: .sigmoid).width == 1.0)
        // LINEAR_EXACT over c = 0.5, w = 0.25: 0.375 is the lower edge, 0.625 the upper.
        let exact = WindowSettings(center: 0.5, width: 0.25, function: .linearExact)
        #expect(exact.apply(to: 0.375) == 0.0)
        #expect(exact.apply(to: 0.5) == 0.5)
        #expect(exact.apply(to: 0.625) == 1.0)
    }
    
    // MARK: - Range Tests
    
    @Test("minValue calculation")
    func testMinValueCalculation() {
        let window = WindowSettings(center: 100.0, width: 200.0)
        
        #expect(window.minValue == 0.0)
    }
    
    @Test("maxValue calculation")
    func testMaxValueCalculation() {
        let window = WindowSettings(center: 100.0, width: 200.0)
        
        #expect(window.maxValue == 200.0)
    }
    
    // MARK: - Linear Transform Tests
    
    @Test("Linear transform - below window")
    func testLinearTransformBelowWindow() {
        let window = WindowSettings(center: 100.0, width: 200.0)
        
        let result = window.apply(to: -100.0)
        #expect(result == 0.0)
    }
    
    @Test("Linear transform - above window")
    func testLinearTransformAboveWindow() {
        let window = WindowSettings(center: 100.0, width: 200.0)
        
        let result = window.apply(to: 300.0)
        #expect(result == 1.0)
    }
    
    @Test("Linear transform - at center")
    func testLinearTransformAtCenter() {
        let window = WindowSettings(center: 100.0, width: 200.0)
        
        let result = window.apply(to: 100.0)
        // Should be approximately 0.5
        #expect(result > 0.49)
        #expect(result < 0.51)
    }
    
    @Test("Linear transform - within window")
    func testLinearTransformWithinWindow() {
        let window = WindowSettings(center: 100.0, width: 200.0)
        
        let result = window.apply(to: 50.0)
        // Should be between 0 and 0.5
        #expect(result > 0.0)
        #expect(result < 0.5)
    }
    
    // MARK: - Linear Exact Transform Tests
    
    @Test("Linear exact transform - below window")
    func testLinearExactTransformBelowWindow() {
        let window = WindowSettings(center: 100.0, width: 200.0, function: .linearExact)
        
        let result = window.apply(to: -50.0)
        #expect(result == 0.0)
    }
    
    @Test("Linear exact transform - above window")
    func testLinearExactTransformAboveWindow() {
        let window = WindowSettings(center: 100.0, width: 200.0, function: .linearExact)
        
        let result = window.apply(to: 250.0)
        #expect(result == 1.0)
    }
    
    @Test("Linear exact transform - at center")
    func testLinearExactTransformAtCenter() {
        let window = WindowSettings(center: 100.0, width: 200.0, function: .linearExact)
        
        let result = window.apply(to: 100.0)
        #expect(result == 0.5)
    }
    
    // MARK: - Sigmoid Transform Tests
    
    @Test("Sigmoid transform - at center")
    func testSigmoidTransformAtCenter() {
        let window = WindowSettings(center: 100.0, width: 200.0, function: .sigmoid)
        
        let result = window.apply(to: 100.0)
        #expect(result == 0.5)
    }
    
    @Test("Sigmoid transform - below center")
    func testSigmoidTransformBelowCenter() {
        let window = WindowSettings(center: 100.0, width: 200.0, function: .sigmoid)
        
        let result = window.apply(to: 0.0)
        #expect(result < 0.5)
        #expect(result > 0.0)
    }
    
    @Test("Sigmoid transform - above center")
    func testSigmoidTransformAboveCenter() {
        let window = WindowSettings(center: 100.0, width: 200.0, function: .sigmoid)
        
        let result = window.apply(to: 200.0)
        #expect(result > 0.5)
        #expect(result < 1.0)
    }
    
    // MARK: - Equality Tests
    
    @Test("Equality")
    func testEquality() {
        let w1 = WindowSettings(center: 100.0, width: 200.0)
        let w2 = WindowSettings(center: 100.0, width: 200.0)
        let w3 = WindowSettings(center: 100.0, width: 300.0)
        
        #expect(w1 == w2)
        #expect(w1 != w3)
    }
}

@Suite("VOILUTFunction Tests")
struct VOILUTFunctionTests {
    
    @Test("Parse LINEAR")
    func testParseLinear() {
        let function = VOILUTFunction.parse("LINEAR")
        #expect(function == .linear)
    }
    
    @Test("Parse LINEAR_EXACT")
    func testParseLinearExact() {
        let function = VOILUTFunction.parse("LINEAR_EXACT")
        #expect(function == .linearExact)
    }
    
    @Test("Parse SIGMOID")
    func testParseSigmoid() {
        let function = VOILUTFunction.parse("SIGMOID")
        #expect(function == .sigmoid)
    }
    
    @Test("Parse nil defaults to linear")
    func testParseNilDefaultsToLinear() {
        let function = VOILUTFunction.parse(nil)
        #expect(function == .linear)
    }
    
    @Test("Parse invalid defaults to linear")
    func testParseInvalidDefaultsToLinear() {
        let function = VOILUTFunction.parse("INVALID")
        #expect(function == .linear)
    }
    
    @Test("Parse lowercase")
    func testParseLowercase() {
        let function = VOILUTFunction.parse("sigmoid")
        #expect(function == .sigmoid)
    }
}
