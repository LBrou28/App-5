# Deployment and two-phone verification

## Firebase prerequisites

The repository targets Firebase project `app-5-741f2` and photo bucket `app-5-741f2.firebasestorage.app`. For another project, regenerate Flutter configuration and set the Functions environment variable `ITEM_PHOTO_BUCKET` to its bucket name.

1. Enable the Blaze plan for Cloud Functions and Cloud Storage. Billing changes must be performed by the project owner.
2. Enable Google as a Firebase Authentication provider and configure its support email.
3. Create the Firestore database and Storage bucket if they do not already exist.
4. Register the Android signing certificate SHA-1/SHA-256 for application ID `com.app5.app_5`. Download updated `android/app/google-services.json` when Firebase requests it.
5. Install server dependencies, then authenticate the Firebase CLI and deploy from the repository root:

```sh
cd functions
pnpm install --frozen-lockfile
pnpm run build
pnpm exec firebase login
pnpm exec firebase deploy --project app-5-741f2 --only functions,firestore,storage --config ../firebase.json
```

This deploy includes callable item/location/household/loan functions, a photo cleanup trigger, a daily abandoned-upload cleanup job, and both access rules. The first deployment may require permission to enable Cloud Functions, Cloud Run, Eventarc, Scheduler and related APIs, and to grant Storage Rules access to Firestore membership documents. The deploying account needs the corresponding project permissions.

Coordinate this deployment with the updated app: old versions that mutate shared Firestore documents directly will be denied by the new rules. Existing item/location records remain readable. Legacy location counters are ignored; server queries check whether locations contain items or child containers before deletion.

## Automated APK signing and Google sign-in

The GitHub workflow creates a debug APK on pushes and pull requests. Android debug signing is suitable for a class demo, not Play Store distribution.

For a stable certificate across workflow runs:

1. Use a dedicated Android **debug** keystore, with alias `androiddebugkey`, store password `android`, and key password `android`.
2. Store its Base64 content in the repository Actions secret `ANDROID_DEBUG_KEYSTORE_BASE64`. Never commit the keystore or print the secret.
3. Register that keystore's SHA-1 and SHA-256 in Firebase. The workflow's **Show demo signing fingerprint** step prints only public certificate information.
4. Download the `app-5-debug-apk` artifact from a successful Actions run, extract it and install the APK on both phones.

Without the secret, the APK still builds with the runner's generated debug key. That certificate varies between runners, so native Google sign-in needs its fingerprint registered for each resulting key. Pull requests from forks do not receive repository secrets.

## Two-phone acceptance check

- Sign in on A. Invite a member from the account menu.
- Sign in with another Google account on B. Join with A's code. Codes expire after 24 hours and admit only one account; retries by that same account are safe.
- On A, create a room/container and an item with name, category, notes and a camera/gallery photo.
- On B, verify the item and photo appear. Restart B and confirm the joined household and item persist.
- Edit the item on B and change its location. Verify A updates. Concurrent stale edits should ask the user to reopen the item rather than overwrite newer changes.
- Cancel an edit and confirm nothing changes. Try an empty name and confirm validation.
- Delete with confirmation and verify the item disappears on both phones. Referenced photos are removed by a server trigger. Unreferenced uploads from failed/abandoned saves are removed after 24 hours by the daily job.
- Verify an unrelated account cannot read the household or photos. Emulator tests exercise this as well as simultaneous loan attempts and deletion of loaned items.

This checklist still needs to be performed on physical phones after deployment; local tests and a successful APK build do not establish live deployment or native sign-in configuration.
