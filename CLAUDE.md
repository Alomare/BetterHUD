# Rules for this repository

**Every release has a changelog.** Before tagging, add `docs/releases/<version>.md` with one line per change, such as `- Removed the black outline around the player health bars.`, and nothing else. Each line describes the change briefly and directly. The Release workflow publishes the file as the release notes on GitHub and the version's changelog on Nexus, and stops if the file is missing or `python tools/nexus_release.py check` rejects the wording.
