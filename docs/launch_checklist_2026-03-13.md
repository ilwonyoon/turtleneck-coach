# TurtleneckCoach Launch Checklist

Date: 2026-03-13
Scope: first paid public launch via notarized DMG on Lemon Squeezy
Status: Stabilize `main`, then run clean-user QA, then publish

## Product Direction

- Sell one notarized DMG as a one-time purchase.
- Keep the first launch simple.
- Do not block v1 on Sparkle or in-app license activation.

## Current Decision

- Public release path: bundled MediaPipe-enabled build from `main`
- Keep one paid SKU and one notarized DMG deliverable
- MediaPipe is non-negotiable for launch; do not ship a Vision-only build

## Launch Blocks

- [x] `main` release path re-verified with current code
- [ ] Fresh macOS user install smoke test passed
- [ ] Lemon Squeezy store activated
- [ ] Lemon Squeezy product created
- [ ] Final price chosen
- [ ] Support/refund/privacy links prepared

## Release Commands

```bash
./scripts/build-release.sh "Developer ID Application: ILWON YOON (LG7667PAS6)"
./scripts/create-dmg.sh ./TurtleneckCoach.app
./scripts/notarize.sh ./TurtleneckCoach-1.0.0.dmg turtle-notary
```

## Lemon Squeezy Recommendation

- Product type: one-time purchase
- Variants: one
- Deliverable: notarized DMG
- License enforcement in app: no for v1
- Refund/support handling: manual and simple

## Pricing Recommendation

- Recommended launch price: `$12`
- Safe range if you want to test faster: `$9.99` to `$15`
- Recommended default: keep one price, no discount ladder, no subscription

## Next Action

- Rebuild and notarize from `main`
- Then run clean-user smoke test
