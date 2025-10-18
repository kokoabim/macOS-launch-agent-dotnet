macOS Launch Agent Template

### How-To

1. **Namespace**: Find and replace `Kokoabim.LaunchAgent` to launch agent namespace
2. **Title**: Find and replace `AGENTTITLE_CHANGEME` to launch agent title
3. **Name**: Find and replace `AGENTNAME_CHANGEME` to launch agent tool name
4. **LaunchAgent**:
    - Find and replace `me.swsj.launch-agent` to launch agent label
    - Rename and modify `me.swsj.launch-agent.plist` as needed
5. **Build & Deploy**: Use `manage-launchagent.sh` to build, copy, and deploy the launch agent
    - Modify this file to set default options as needed
6. **.gitignore**: You may want to modify `.gitignore` to exclude launch agent plist
