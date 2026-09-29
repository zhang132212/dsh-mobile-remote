# Device2 mobile repair — 2026-09-25

Backend package: `3.1.5-eun.1`. Android: `3.1.5+23` (development signing).
Base: upstream commit `7e2e2def0795d83ff8921f0296f6f2118bdb6d16`.

## Findings and changes

- The live `/m/api/bootstrap` reported plugin 3.1.1. Its legacy apiProxy bridge did not support the running Harness user-questions waterfall. Deploy the 3.1.5 bridge and the repairs below together with this APK.
- Reset event-channel readiness when its stream closes or fails, so subsequent requests can use the connected phone's direct waterfall handler. Resolve the session through the existing `agentSessionId` helper, including agents which expose only `id`. Generate unique pending-question identifiers.
- Preserve `sourceKind`, `senderSessionId` and `sourceForm` in message summaries. Subagent reports, completion notices and coordinator messages have explicit labels and expandable content in ordinary mode; they are not human bubbles or hidden system context.
- Adapt the official Harness neutral light/dark colors, primary actions, typography, 22px user bubbles and 20px question composer. Questions paginate with a scrolling body and fixed footer. Multi-select answers retain selections when custom details are added.

Official references inspected on device2: `packages/client/ui-theme/src/styles/design-platform.css`, `packages/client/ui-chat/src/client/chat/MessageItem.module.css`, and `packages/client/ui-user-questions/src/client/QuestionComposer.module.css` in the existing DeepSeek Harness checkout. This is a Flutter adaptation, not a copy of the desktop React application.

## Validation

- Backend: `node --test test/*.test.mjs` — 31 passed, including offline question replay, answer settlement, stream-disconnect fallback and message provenance.
- Flutter: `flutter analyze --no-pub`; `flutter test --no-pub` — clean analysis and 136 passed.
- Android: `:app:testDebugUnitTest` — 27 passed; release APK signature verified with apksigner.
- Widget scenarios: small phone viewport, multi-question paging, custom multi-select answers, ordinary-mode subagent attribution. Question composer image inspected with actual Chinese fonts.
- Live deployment verified as 3.1.5-eun.1, with `userQuestions=true`, `remoteEvents=true`, `approvalMode=both`.
- No physical Android device was connected for end-to-end testing.

## Locations

- Remote source: `F:\dsh-build-kit\workspace\dsh-mobile-remote`, branch `fix/mobile-question-agent-ui`.
- Build entry: `F:\dsh-build-kit\build.ps1`, offline by default.
- Updated plugin copies: `C:\Users\Administrator\.dsh\plugins\dsh-mobile-remote` and `C:\Users\Administrator\.dsh\profiles\web\node_modules\dsh-mobile-remote`.
- Old plugin backup: `F:\dsh-build-kit\backups\mobile-20260925-181301`.
- Deployment script: `F:\dsh-build-kit\deploy-reviewed.ps1`, with non-idle agent guard and rollback on failed startup.
- The added `@deepseek-ai/dsh-scope` dependency resolves to the installed Harness checkout via a junction in the web profile's node_modules. The source test checkout uses the web profile's dependencies through its own node_modules junction.

The backend update and restart were completed after explicit user approval. The desktop reverse proxy and other services were not restarted.
