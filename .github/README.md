# Manual source and release workflows

`Bump version` and `Build` are independent manual workflows. Bump has exactly
one required patch/minor/major choice, default patch; Build has zero custom
inputs. Use GitHub's built-in ref selector. Neither workflow dispatches the
other, and there are no push/tag triggers. All checkouts use `github.sha`.

## USB source authority

The immutable intake is `11b24c7e0c794c7d732f4d0da62131323a800072`,
canonical repository `miyako/4d-plugin-usb`, default branch `master`.
The header of Bump at `3b30725b94ddcce9f242bdb9d9c9e48dc61b22d1`
explicitly coordinates MARKETING_VERSION/CURRENT_PROJECT_VERSION and
Info.plist. Its marketing-only implementation failed that contract.
This migration aligns exactly three stale source CURRENT tokens from 2.1.0
to the existing marketing authority **2.1.2**, without an intake increment.

The three version-bearing configurations are the project-level Development,
Deployment and Default configurations in `LIBUSB.xcodeproj/project.pbxproj`;
the corresponding target configurations have no version fields.
Source `Info.plist` requires CFBundleShortVersionString and retains its
`$(CURRENT_PROJECT_VERSION)` reference. Its absent CFBundleVersion remains
absent. The actually copied source `English.lproj/InfoPlist.strings` overrides
display metadata; its short-version and LIBUSB information-string tokens are
aligned from 2.1 to 2.1.2 and co-bumped. ASCII CR-only serialization and all
source executable modes are preserved. Prebuilt destination localization
(UTF-16LE BOM, still 2.1) is not authority and remains unchanged at intake.

Known references are preserved. Missing, invalid, unresolved, cyclic,
duplicate (including quoted/inline assignments), configuration-drifting or
uncoordinated metadata fails before writes. Edits replace only token spans,
preserving supported encodings, BOMs, individual line endings and modes.

## Bump safety

Before any edit, every guard check, and after the second actual remote read
immediately before push, the mandatory `.github/hooks/pre-push` must be a
regular nonsymlink executable matching its raw HEAD blob and committed
100755 mode. An exit-zero replacement or same-bytes symlink is rejected.
Bump checks the selected SHA against the exact remote branch, creates one
nonempty source-only direct child, uses explicit Actions bot author and
committer identities, and requires the literal ending trailer:

`Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>`

The actual pre-push advertisement must contain exactly one literal new
SHA/HEAD, local SHA, selected branch ref and selected old SHA record.
Advance, rewind, delete and same-result races fail without retries.
Both `push.followTags=false` and `--no-follow-tags` suppress followed tags.
There is no force, amend, build, tag, release or workflow dispatch.

## Native preservation

Despite its old Windows header, the actual release workflow has only version
and macOS jobs. Build preserves that topology: macOS Default universal
arm64+x86_64, deployment override 11.0, project/target/product LIBUSB,
package root `LIBUSB.4dbase/Plugins/LIBUSB.bundle`. The Windows64
`LIBUSB.4DX` is prebuilt and retained byte-for-byte; there is no Windows job,
download, merge or invented CMD adapter. The linked static `a/libusb-1.0.a`
and IOKit/Security/Cocoa/CoreGraphics/AppKit framework policy is unchanged.
`dylib/libusb-1.0.0.dylib` is not packaged; no runtime dependency policy,
nested dependency-clone exceptions or 4D execution is added.

The existing credential/altool project phase is unchanged and runs only for
Deployment. Selected Default leaves it inactive; `CODE_SIGNING_ALLOWED=NO`
only disables ordinary Xcode signing, not custom phases.

Cleanup prevalidates every target before the first deletion. Only exact
generated macOS leaves and proven project intermediates are removed; never
the whole bundle, static resources, prebuilt Windows or unrelated Default
siblings. Built XML/binary plist and copied/compiled English localization are
validated. The unsigned gate is separate from the final signed gate.
Every packaged leaf must be nonempty, regular and nonsymlink. Final resources
must exactly equal source; Windows must match its selected raw Git blob.
Architecture tokens must include arm64 and x86_64. Signing requires strict
verification. Notarytool requires both exit zero and strict JSON Accepted,
followed by stapling and strict signing verification.

## Publication safety and recovery

A constant repository-wide publication concurrency group disables
cancellation; serialization is not FIFO. No new default-only branch gate is
introduced. Explicit nonempty GH_TOKEN and case-exact canonical repository
identity are mandatory. Early availability checks precede native work, and
final checks follow all build/sign/notary/staple work.

Initial checkout cleanliness is global. Final validation retains generated
bytes without resetting outputs: immutable HEAD, the entire index and raw
nongenerated source/config bytes are independently checked. Both
`git ls-files -v` and `-f` reject hidden stat/index flags, including fsmonitor
H/h differences. Untracked and ignored unexpected source/config files fail.
Only exact generated paths, proven project intermediates, exact XCBuildData
build.db/WAL/SHM and 32-hex `.xcbuilddata` descendants are final allowances.
Pre-existing ignored build databases fail the initial gate.
Scoped inherited `core.autocrlf=false` applies before Build checkouts without
changing host/global configuration.

Availability reads strict JSON, all release pages through the empty page
(including drafts), exact matching API refs and exact remote advertisements.
Malformed/schema/duplicate/nonfinite/later-page/auth/network errors abort.
Publication uses separate create-only POSTs for a tag at selected SHA, a new
public release ID not previously observed, and exact nonempty ZIP/DMG assets
only on that new ID. The original empty-body/generated-notes-false policy
is preserved. Names are `LIBUSB-X.Y.Z.zip` and `LIBUSB-X.Y.Z.dmg`.
No tag/release reuse, update, clobber, delete, rollback or retry is performed.

Existing v2.1.2 is occupied. Build at unchanged intake authority intentionally
fails early; run the independent source-only Bump before a new release.
Any failed POST may have succeeded remotely, leaving partial tags, releases
or uploads. **Manual recovery:** inspect the reported tag/new release ID and
retained assets, including unknown-response operations, and deliberately
resolve that state before another Build. A same-SHA race also fails.

## Offline validation

Run `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`
and `actionlint .github/workflows/*.yml`. Tests run actual helpers, local bare
Git races, fake gh and real extracted Bash with closed-PATH native/credential
doubles. They never run real compilers, signing, notarization, 4D or read
secrets. Fixtures remain pinned to immutable intake; live expectations work
after a genuine guarded Bump. Reference pins are in
`tests/reference-pins.json`; provenance pins do not themselves claim that
another reader's required prior-art review has completed.
