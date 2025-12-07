# Contributing to ARBOR

Thank you for your interest in contributing to ARBOR! This document provides guidelines and instructions for contributing.

## Development Setup

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/your-username/arbor.git
   cd arbor
   ```

2. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

3. **Run the server**
   ```bash
   python upload_server.py
   ```

## Code Style

- Follow PEP 8 style guidelines
- Use type hints where appropriate
- Write docstrings for functions and classes
- Keep functions focused and single-purpose
- Use meaningful variable names

## Testing

Before submitting a pull request:

1. **Test the server starts correctly**
   ```bash
   python upload_server.py --help
   ```

2. **Run the test suite** (if available)
   ```bash
   python test_server.py
   ```

3. **Test with different configurations**
   ```bash
   python upload_server.py --config config.yaml
   ```

4. **Check for syntax errors**
   ```bash
   python -m py_compile upload_server.py
   ```

## Making Changes

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Keep changes focused and minimal
   - Update documentation if needed
   - Add comments for complex logic

3. **Test your changes**
   - Ensure the server starts without errors
   - Test affected functionality manually
   - Verify no regressions

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "Brief description of changes"
   ```

5. **Push and create a pull request**
   ```bash
   git push origin feature/your-feature-name
   ```

## Pull Request Guidelines

- **Title**: Use a clear, descriptive title
- **Description**: Explain what changes were made and why
- **Testing**: Describe how you tested the changes
- **Documentation**: Update README.md if needed
- **Breaking Changes**: Clearly mark any breaking changes

## Reporting Issues

When reporting issues, please include:

- ARBOR version
- Python version
- Operating system
- Steps to reproduce
- Expected behavior
- Actual behavior
- Error messages or logs

## Feature Requests

Feature requests are welcome! Please:

- Check if the feature already exists
- Explain the use case
- Describe the expected behavior
- Consider implementation complexity

## Security

If you discover a security vulnerability:

- **DO NOT** open a public issue
- Email the maintainers privately
- Include steps to reproduce
- Wait for confirmation before public disclosure

## Code of Conduct

- Be respectful and professional
- Welcome newcomers
- Focus on constructive feedback
- Keep discussions on-topic

## Questions?

If you have questions:

- Check the README.md documentation
- Search existing issues
- Open a new issue with the "question" label

Thank you for contributing to ARBOR!
