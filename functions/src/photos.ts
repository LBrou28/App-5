import { getApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';

// Match the Flutter project's bucket; ITEM_PHOTO_BUCKET supports other deployments.
export function photoBucket() {
  return getStorage().bucket(process.env.ITEM_PHOTO_BUCKET ??
    (process.env.FIREBASE_STORAGE_EMULATOR_HOST ? `${getApp().options.projectId}.appspot.com` : 'app-5-741f2.firebasestorage.app'));
}

// Immutable photo names make replacement cleanup safe with concurrent edits.
export const cleanupItemPhoto = onDocumentWritten({ document: 'households/{householdId}/items/{itemId}', retry: true }, async event => {
  const oldPath = event.data?.before.data()?.photoPath;
  const newPath = event.data?.after.data()?.photoPath;
  const prefix = `households/${event.params.householdId}/items/${event.params.itemId}/`;
  if (typeof oldPath === 'string' && oldPath.startsWith(prefix) && oldPath !== newPath) {
    const current = await getFirestore().doc(`households/${event.params.householdId}/items/${event.params.itemId}`).get();
    if (current.data()?.photoPath !== oldPath) await photoBucket().file(oldPath).delete({ ignoreNotFound: true });
  }
});

// Failed/abandoned uploads have no item reference. Allow 24 hours before removal.
export const cleanupAbandonedPhotos = onSchedule('every 24 hours', async () => {
  const bucket = photoBucket();
  const [files] = await bucket.getFiles({ prefix: 'households/' });
  for (const file of files) {
    const match = /^households\/([^/]+)\/items\/([^/]+)\/[^/]+$/.exec(file.name);
    if (!match) continue;
    const [metadata] = await file.getMetadata();
    if (!metadata.timeCreated || Date.parse(metadata.timeCreated) > Date.now() - 86400000) continue;
    const item = await getFirestore().doc(`households/${match[1]}/items/${match[2]}`).get();
    if (item.data()?.photoPath !== file.name) await file.delete({ ignoreNotFound: true });
  }
});
