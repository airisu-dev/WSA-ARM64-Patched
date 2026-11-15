# Research notes

Background for `..\README.md` (the build recipe). None of this is needed to build WSA; it explains why the build does what it does
and how to debug it when something changes.

| Read | When |
|---|---|
| [findings.md](findings.md) | You want the root cause, the reason for every patch, what was verified, and the list of theories that turned out wrong |
| [tooling-notes.md](tooling-notes.md) | Something fails and you want to see the guest log, or you hit a WSL/PowerShell/ADB gotcha |
| [package-analysis.md](package-analysis.md) | You want to know what is inside the WSA package and which parts are open source |
| [tools/](tools/README.md) | Research scripts and sample logs (not part of the build) |

The docs describe the current, verified state. Where an earlier assumption was disproved, only the corrected fact is stated, and the
old theory is listed once in "Disproved theories" in `findings.md` so it is not tried again.
