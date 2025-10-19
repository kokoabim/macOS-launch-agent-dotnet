macOS Launch Agent Template

### Dependencies

-   [CommandLineInterface library](https://github.com/kokoabim/CommandLineInterface-DotNet): Referenced by this project
-   `jq`: For JSON parsing. Install via Homebrew: `brew install jq`

### How-To

There are two ways to create a new launch agent project from this template.

#### Using Script

Use the provided `create-launchagent.sh` script to generate a new launch agent project from this template.

#### Manually

1. **Namespace**: Find and replace `Kokoabim.LaunchAgent` to launch agent namespace
2. **Title**: Find and replace `AGENTTITLE_CHANGEME` to launch agent title
3. **Name**: Find and replace `AGENTNAME_CHANGEME` to launch agent tool name
4. **LaunchAgent**:
    - Find and replace `me.swsj.launch-agent` to launch agent label
    - Rename and modify `me.swsj.launch-agent.plist` as needed

### Notes

-   **Build & Deploy**: Use `manage-launchagent.sh` to build, copy, and deploy the launch agent
    -   Modify the script to set default options as needed
-   **.gitignore**: You may want to modify `.gitignore` to exclude launch agent plist
