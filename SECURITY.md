# Security

Please do not open public issues for security problems. Report them privately through GitHub's [private vulnerability reporting](https://github.com/kimjisub/toolsmith/security/advisories/new), with steps to reproduce and the version you used.

Of particular interest:

- the charge helper (`App/Helper`), which runs as root once a user installs it, and its XPC code-signing checks;
- the update check (`App/Kit/Update`, `App/Main/Update`), which must install only builds signed by the maintainer's Developer ID and notarized by Apple;
- anything that could expose clipboard history, snippets, screen time or other data recorded on the Mac;
- the OpenRouter key kept in the Keychain.

Only the latest release is supported. I aim to answer within a week.
