# Contributing to Tickr

Thank you for your interest in contributing to Tickr! This document provides guidelines for contributing to this project.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/h4ux/Tickr.git`
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Open `Tickr.xcodeproj` in Xcode

## Development Setup

- **Xcode 15.0+** required
- **macOS 13.0+** deployment target
- No external dependencies — the project uses only Apple frameworks (SwiftUI, AppKit, Combine, Foundation)

### Building

```bash
# Via Xcode
# Open Tickr.xcodeproj → ⌘B

# Via command line
xcodebuild -project Tickr.xcodeproj -scheme Tickr -configuration Debug build
```

### Generating Icons

```bash
# Requires librsvg (brew install librsvg) or ImageMagick
./scripts/generate_icon.sh
```

## Making Changes

### Code Style

- Follow standard Swift conventions and the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Use SwiftUI for all new UI components
- Keep the app lightweight — avoid adding external dependencies unless absolutely necessary

### What We're Looking For

- Bug fixes with clear descriptions
- Performance improvements
- UI/UX enhancements
- Support for additional data sources
- Accessibility improvements
- Localization support

### What to Avoid

- Adding external package dependencies without discussion
- Changes that break macOS 13.0 compatibility
- Features that require user accounts or collect personal data
- Hard-coded API keys or credentials

## Submitting Changes

1. Commit your changes with clear, descriptive messages
2. Push to your fork
3. Open a Pull Request against the `main` branch
4. Describe what your changes do and why

### Pull Request Guidelines

- Keep PRs focused — one feature or fix per PR
- Include screenshots for UI changes
- Update documentation if your change affects usage
- Ensure the app builds without warnings

## Reporting Issues

- Use GitHub Issues for bug reports and feature requests
- Include macOS version, app version, and steps to reproduce for bugs
- Check existing issues before creating duplicates

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
