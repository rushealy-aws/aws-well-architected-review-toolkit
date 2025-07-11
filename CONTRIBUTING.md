# Contributing to AWS Well-Architected Review Toolkit

Thank you for your interest in contributing to the AWS Well-Architected Review Toolkit! This document provides guidelines and information for contributors.

## 🤝 Code of Conduct

This project adheres to a code of conduct that we expect all contributors to follow:

- **Be respectful**: Treat everyone with respect and kindness
- **Be inclusive**: Welcome newcomers and help them get started
- **Be collaborative**: Work together to improve the project
- **Be constructive**: Provide helpful feedback and suggestions
- **Be professional**: Maintain a professional tone in all interactions

## 🚀 Getting Started

### Prerequisites

Before contributing, ensure you have:

- AWS CLI installed and configured
- Bash shell environment (Linux/macOS/WSL)
- Git installed and configured
- Basic understanding of AWS Well-Architected Framework
- Familiarity with Markdown and shell scripting

### Development Setup

1. **Fork the repository**
   ```bash
   # Fork via GitHub UI, then clone your fork
   git clone https://github.com/YOUR-USERNAME/aws-well-architected-review-toolkit.git
   cd aws-well-architected-review-toolkit
   ```

2. **Set up upstream remote**
   ```bash
   git remote add upstream https://github.com/original-owner/aws-well-architected-review-toolkit.git
   ```

3. **Create a development branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

4. **Install development dependencies**
   ```bash
   # Make scripts executable
   find . -name "*.sh" -exec chmod +x {} \;
   
   # Install shellcheck for script validation (optional)
   # On macOS: brew install shellcheck
   # On Ubuntu: apt-get install shellcheck
   ```

## 📝 Types of Contributions

We welcome various types of contributions:

### 🐛 Bug Reports

When reporting bugs, please include:

- **Clear description** of the issue
- **Steps to reproduce** the problem
- **Expected vs. actual behavior**
- **Environment details** (OS, AWS CLI version, etc.)
- **Error messages** or logs if applicable

Use the bug report template when creating issues.

### ✨ Feature Requests

For feature requests, please provide:

- **Clear description** of the proposed feature
- **Use case** and business justification
- **Proposed implementation** approach (if applicable)
- **Potential impact** on existing functionality

### 📚 Documentation Improvements

Documentation contributions are highly valued:

- Fix typos, grammar, or formatting issues
- Improve clarity and readability
- Add missing information or examples
- Update outdated content
- Translate content to other languages

### 🔧 Code Contributions

Code contributions should:

- Follow the established coding standards
- Include appropriate tests and validation
- Update documentation as needed
- Pass all existing tests and checks

## 📋 Contribution Guidelines

### File Organization

When contributing, follow the established directory structure:

```
pillars/[pillar-name]/
├── GUIDE.md                    # Main pillar guide
├── README.md                   # Pillar overview
├── scripts/                    # Automation scripts
│   ├── assessment/            # Assessment scripts
│   ├── testing/               # Testing scripts
│   └── utilities/             # Utility scripts
├── templates/                  # Configuration templates
├── docs/                      # Additional documentation
└── examples/                  # Usage examples
```

### Coding Standards

#### Shell Scripts

- Use `#!/bin/bash` shebang
- Include descriptive comments and headers
- Use meaningful variable names
- Implement error handling and validation
- Follow consistent formatting and indentation
- Use shellcheck for validation when possible

Example script header:
```bash
#!/bin/bash
# Script Name: example-assessment.sh
# Description: Performs example assessment for Well-Architected review
# Author: Your Name
# Version: 1.0
# Last Modified: YYYY-MM-DD

set -euo pipefail  # Exit on error, undefined vars, pipe failures
```

#### Markdown Documentation

- Use consistent heading hierarchy
- Include table of contents for long documents
- Use code blocks with appropriate syntax highlighting
- Include examples and practical guidance
- Follow the established template structure
- Use relative links for internal references

#### YAML/JSON Configuration

- Use consistent indentation (2 spaces for YAML)
- Include comments explaining configuration options
- Validate syntax before committing
- Follow AWS naming conventions

### Commit Guidelines

Follow conventional commit format:

```
type(scope): brief description

Detailed explanation of changes (if needed)

- List specific changes
- Include breaking changes
- Reference related issues

Closes #123
```

**Commit Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(cost-optimization): add automated right-sizing recommendations

docs(security): update IAM policy analysis guide

fix(reliability): correct auto-scaling assessment script

test(performance): add load testing validation
```

### Pull Request Process

1. **Before submitting:**
   - Ensure your branch is up to date with main
   - Run all relevant tests and validations
   - Update documentation as needed
   - Add or update examples if applicable

2. **Pull Request Requirements:**
   - Use the provided PR template
   - Include clear description of changes
   - Reference related issues
   - Add screenshots for UI changes
   - Ensure all checks pass

3. **Review Process:**
   - PRs require at least one approval
   - Address all review feedback
   - Maintain clean commit history
   - Squash commits if requested

### Testing Guidelines

#### Script Testing

- Test scripts in multiple environments when possible
- Include error handling and edge cases
- Validate AWS CLI commands and permissions
- Test with different AWS account configurations

#### Documentation Testing

- Verify all links work correctly
- Test code examples and commands
- Ensure formatting renders correctly
- Check for spelling and grammar

#### Integration Testing

- Test end-to-end workflows
- Validate cross-pillar dependencies
- Ensure backward compatibility
- Test with different AWS service configurations

## 🏷️ Issue Labels

We use the following labels to categorize issues:

**Type Labels:**
- `bug`: Something isn't working
- `enhancement`: New feature or request
- `documentation`: Improvements or additions to docs
- `question`: Further information is requested

**Priority Labels:**
- `priority/high`: High priority
- `priority/medium`: Medium priority
- `priority/low`: Low priority

**Pillar Labels:**
- `pillar/cost-optimization`
- `pillar/reliability`
- `pillar/security`
- `pillar/performance-efficiency`
- `pillar/operational-excellence`
- `pillar/sustainability`

**Status Labels:**
- `status/needs-triage`: Needs initial review
- `status/in-progress`: Currently being worked on
- `status/blocked`: Blocked by external dependency
- `status/ready-for-review`: Ready for review

## 🔍 Review Criteria

Pull requests are evaluated based on:

### Technical Quality
- Code follows established patterns and standards
- Proper error handling and validation
- Appropriate use of AWS services and APIs
- Security best practices followed

### Documentation Quality
- Clear and comprehensive documentation
- Proper formatting and structure
- Accurate and up-to-date information
- Helpful examples and use cases

### Testing Coverage
- Adequate testing for new functionality
- Existing tests continue to pass
- Edge cases considered and handled
- Integration testing where applicable

### User Experience
- Intuitive and easy to use
- Clear error messages and guidance
- Consistent with existing patterns
- Accessible to target audience

## 🎯 Contribution Ideas

Looking for ways to contribute? Consider these areas:

### High-Impact Contributions
- Add support for new AWS services
- Improve automation and scripting
- Enhance error handling and validation
- Add comprehensive examples and use cases

### Documentation Improvements
- Create video tutorials or walkthroughs
- Add troubleshooting guides
- Improve getting started documentation
- Translate content to other languages

### Tool Enhancements
- Add integration with other AWS tools
- Improve reporting and visualization
- Add support for different output formats
- Enhance cross-platform compatibility

### Community Building
- Answer questions in discussions
- Help review pull requests
- Mentor new contributors
- Share the project with others

## 📞 Getting Help

If you need help with contributing:

1. **Check existing documentation** in the `docs/` directory
2. **Search existing issues** for similar questions
3. **Join the discussion** in GitHub Discussions
4. **Ask questions** in new issues with the `question` label
5. **Reach out to maintainers** for complex questions

## 🙏 Recognition

Contributors are recognized in several ways:

- Listed in the project's contributors section
- Mentioned in release notes for significant contributions
- Invited to join the maintainer team for ongoing contributors
- Featured in project announcements and blog posts

## 📄 License

By contributing to this project, you agree that your contributions will be licensed under the same MIT License that covers the project.

---

Thank you for contributing to the AWS Well-Architected Review Toolkit! Your contributions help make AWS architecture reviews more accessible and effective for everyone.
