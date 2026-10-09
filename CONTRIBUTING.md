# Contributing to DICOMKit

Thank you for your interest in contributing to DICOMKit! This document provides guidelines for contributing to the project.

## Code of Conduct

Be respectful and professional in all interactions. We aim to create a welcoming environment for all contributors.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/DICOMKit.git`
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Run tests: `swift test`
6. Commit your changes
7. Push to your fork
8. Open a Pull Request

## Development Requirements

- macOS 14.0 or later
- Xcode 16.0 or later (for Swift 6.2 support)
- Apple Silicon Mac (M1, M2, M3, M4, or later)

## Code Style

DICOMKit follows standard Swift conventions with these specific requirements:

### Formatting
- Use 4 spaces for indentation (no tabs)
- Maximum line length: 120 characters
- Use Swift's standard naming conventions (camelCase for variables/functions, PascalCase for types)

### Documentation
- All public types, properties, and methods must have doc comments (`///`)
- Include parameter and return value documentation
- Cite DICOM standard sections where applicable (e.g., `/// Reference: PS3.5 Section 7.1`)

### Type Design
- Prefer value types (`struct`, `enum`) over reference types (`class`)
- All public types must conform to `Sendable` for Swift 6 concurrency
- Use `let` over `var` wherever possible
- Avoid force unwrapping (`!`) in library code - use optional chaining or proper error handling

### Example

```swift
/// Patient Name data element
///
/// Stores the patient's name in DICOM PN format (family^given^middle^prefix^suffix).
/// Reference: DICOM PS3.5 Section 6.2 - PN Value Representation
public struct PatientName: Sendable {
    /// Family name component
    public let familyName: String
    
    /// Given name component
    public let givenName: String
    
    /// Creates a patient name
    /// - Parameters:
    ///   - familyName: Family name
    ///   - givenName: Given name
    public init(familyName: String, givenName: String) {
        self.familyName = familyName
        self.givenName = givenName
    }
}
```

## DICOM Standard Compliance

**This is critical**: DICOMKit must faithfully implement the DICOM standard.

### Requirements

1. **Use DICOM 2026a only** - Do not reference older editions
2. **Cite sections** - All parsing behavior must cite specific PS3.x sections
3. **No translation** - Do not port code from other libraries (DCMTK, pydicom, fo-dicom)
4. **Authoritative sources**:
   - Use DICOM XML for structure definitions (PS3.6)
   - Use DICOM PS3.5 text for parsing and encoding rules
5. **Never invent** - If the standard doesn't specify behavior, ask or leave it unimplemented
6. **Never type a tag number without its PS3.6 keyword beside it** - a `Tag.xxx`
   constant is named exactly by the PS3.6 keyword (lower-camel-cased); a raw
   `Tag(group:element:)` or `"GGGGEEEE"` literal carries the attribute name in a
   comment on the same line. `Scripts/audit_tags.py --strict` runs in CI and
   fails the build when a name and its number disagree, and
   `DICOMDictionaryTests/TagConstantAuditTests` checks every constant against the
   bundled dictionary. Never define the same tag twice under two names; alias
   through a `@available(*, deprecated, renamed:)` forwarder instead.

### Example Citation

```swift
// CORRECT
/// Reads the Value Length field.
/// For VRs with 16-bit length, reads 2 bytes (PS3.5 Section 7.1.2).
/// For VRs with 32-bit length, skips 2 reserved bytes then reads 4 bytes (PS3.5 Section 7.1.2).

// INCORRECT
/// Reads the length field (like pydicom does)
```

## Testing

- All new features must include tests
- Use Swift Testing framework (`@Test`, `#expect`)
- Organize tests by module (DICOMCoreTests, DICOMDictionaryTests, DICOMKitTests)
- Test both success and failure cases
- Test edge cases (empty data, maximum values, etc.)

### Running Tests

```bash
swift test
```

### Continuous Integration

DICOMKit uses GitHub Actions for automated testing and validation:

- **CI Workflow**: Runs on every push and pull request
  - Builds the package on multiple Xcode versions
  - Runs the comprehensive test suite (1,464+ tests)
  - Validates code quality and compiler warnings
  - Tests platform compatibility (iOS, macOS, visionOS)
  
- **Scheduled Tests**: Runs weekly on Mondays
  - Comprehensive test suite with verbose output
  - Memory leak detection with sanitizers
  - Performance benchmarking
  - Dependency update checks
  
- **Documentation Build**: Deploys to GitHub Pages on main branch updates
  - Builds DocC documentation for all modules
  - Creates searchable API reference
  
- **Release Workflow**: Triggered on version tags (v*.*.*)
  - Builds and packages CLI tools
  - Creates GitHub releases with artifacts
  - Generates release notes

All CI workflows are located in `.github/workflows/`:
- `ci.yml` - Main continuous integration
- `scheduled-tests.yml` - Weekly comprehensive testing
- `docs.yml` - Documentation deployment
- `release.yml` - Release automation

Before submitting a PR, ensure your changes pass locally:
```bash
# Build the project
swift build

# Run all tests
swift test

# Build in release mode
swift build -c release
```

The CI will automatically run these checks when you open a pull request.

### Test Example

```swift
import Testing
@testable import DICOMCore

@Suite("Tag Tests")
struct TagTests {
    @Test("Private tag detection")
    func testPrivateTagDetection() {
        let privateTag = Tag(group: 0x0011, element: 0x0010)
        #expect(privateTag.isPrivate == true)
        
        let standardTag = Tag(group: 0x0010, element: 0x0010)
        #expect(standardTag.isPrivate == false)
    }
}
```

## Pull Request Process

1. **Update documentation** - If you change public API, update README.md and doc comments
2. **Add tests** - All new functionality must be tested
3. **Cite DICOM standard** - Include PS3.x section references in code comments
4. **Run tests** - Ensure `swift test` passes
5. **Keep PRs focused** - One feature or fix per PR
6. **Write clear commit messages** - Explain what and why, not just what

### Commit Message Format

```
Brief summary (50 chars or less)

More detailed explanation if needed. Wrap at 72 characters.

- List specific changes
- Reference DICOM sections if applicable
- Link to issues: Fixes #123
```

## What to Contribute

### High Priority
- Additional data element dictionary entries from PS3.6 2026a
- Additional UID dictionary entries
- Bug fixes
- Documentation improvements
- Test coverage improvements

### Future Enhancements
- DICOMweb services (WADO-RS, QIDO-RS, STOW-RS)
- Structured Reporting (SR documents)
- Presentation State support
- Extended character set support (beyond UTF-8)

### Not Accepting
- Features outside DICOM 2026a specification
- Changes that break Apple platform compatibility
- Changes that remove strict concurrency support
- Dependencies on third-party libraries (prefer pure Swift)

## Questions?

- Open an issue for bugs or feature requests
- Start a discussion for questions or ideas
- Tag maintainers for urgent issues

## License

By contributing to DICOMKit, you agree that your contributions will be licensed under the MIT License.

---

Thank you for helping make DICOMKit better!