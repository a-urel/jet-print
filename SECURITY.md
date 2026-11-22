# Security policy

## Supported versions

Security fixes go into the latest `1.x` release of `jet_print` on
[pub.dev](https://pub.dev/packages/jet_print). Older minor releases do not get
backports; upgrading within `1.x` is non-breaking (see the package
[CHANGELOG](packages/jet_print/CHANGELOG.md)).

| Version | Supported |
|---|---|
| latest `1.x` | yes |
| older `1.x` minors | upgrade to the latest |
| `0.x` (preview) | no |

## Reporting a vulnerability

Please do not open a public issue. Report it privately through
[GitHub's private vulnerability reporting](https://github.com/a-urel/jet-print/security/advisories/new).

Useful to include: the affected version, what an attacker controls (for
example a report JSON file or the data bound into a report), and the smallest
input that shows the problem.

You can expect an acknowledgement within a week. Once the issue is confirmed,
a fix is released and a GitHub security advisory is published, crediting you
unless you prefer otherwise.
