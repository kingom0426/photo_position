# Project delivery requirements

- Treat backend changes as incomplete until they are built, tested, deployed, and verified through the public API.
- Apply Flyway migrations to the configured RDS as part of the same delivery whenever migrations are added.
- Deploy the backend JAR to the existing `lumen.service` on the Lumen ECS, preserving a rollback copy before replacement.
- After deployment, verify service status, recent logs, `/api/health`, and every changed public endpoint.
- Do not report a backend feature as complete when only local source code has changed.
- After every iOS source change, build, install, and launch the `Lumen` app on the paired device named `杜鑫` before reporting completion.
- Use CoreDevice identifier `C2564A70-2D79-52AE-990E-1FB4685E2CB7` for the `杜鑫` device unless device discovery shows that it has changed.
- Use `bash scripts/deploy-ios.sh` for signed iOS build, installation, and launch. In a sandboxed execution environment, request elevated execution so Xcode can access macOS device services and signing credentials. Sandboxed CoreDevice/CoreSimulator connection errors do not establish that the device or Xcode installation is broken; verify with authorized system access first.
